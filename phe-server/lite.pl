#!/usr/bin/env perl
use Mojolicious::Lite;

use Minion;
use Mojo::Pg;
use Mojo::Promise;
use Mojo::URL;

helper pg => sub { state $pg = Mojo::Pg->new($ENV{'PG_URL'} // 'postgresql://missing-PG_URL-environment-variable/test') };
app->pg->auto_migrate(1)->migrations->name('phe')->from_data(undef, 'migrations.sql');

plugin Minion => { Pg => app->pg };

# the only key format we accept
my $reSearch = qr/^0x[0-9a-fA-F]{40}$/;
# some important cache time periods
my $expireAfter = 24 * 60 * 60;
my $refreshAfter = 2 * 60 * 60;

# take a keyserver response and remove noise like HTML and "Comment:" (which causes non-determinism)
sub _normalize_key {
	my $keydata = shift;
	$keydata =~ s/\r//g;
	$keydata =~ s/^.*(-----BEGIN PGP PUBLIC KEY BLOCK-----.*-----END PGP PUBLIC KEY BLOCK-----).*$/$1/s or return '';
	$keydata .= "\n";
	# https://github.com/gpg/gnupg/blob/b46382dd47731231ff49b59c486110a25e08e985/g10/armor.c#L373-L377 ("Comment" typically holds noise like the name of the server we fetched from)
	$keydata =~ s/\nComment: [^\n]+\n/\n/g;
	return $keydata;
}

# a spin on Mojo::Promise->race such that we return the fastest success _or_ the sum of all rejects
helper p_race => sub {
	my $c = shift;
	my @promises = @_;
	my $new = Mojo::Promise->new;
	my ($resolved, $rejected) = (0, 0);
	my @rejects;
	for my $promise (@promises) {
		$promise->then(sub {
			++$resolved;
			$new->resolve(@_);
		}, sub {
			++$rejected;
			push @rejects, @_;
			if (!$resolved && $rejected == @promises) {
				# if this is the last reject, reject the whole promise
				$new->reject(@rejects);
			}
		});
	}
	return $new;
};
# a spin on UA->get_p to only resolve on a 200/404 exit code
helper get_200_p => sub {
	my $c = shift;
	my $promise = Mojo::Promise->new;
	$c->ua->get_p(@_)->then(sub {
		my $tx = shift;
		$promise->resolve($tx) if $tx->res->code == 200;
		$promise->reject($tx->res->code) if $tx->res->code == 404;
		if (my $err = $tx->error) { return $promise->reject($err->{message}) }
		$promise->reject('unexpected non-error exit code: ' . $tx->res->code);
	})->catch(sub { $promise->reject(@_) });
	return $promise;
};

helper lookup_p => sub {
	my $c = shift;
	my $search = shift // '';

	state $lookupUrlBase = Mojo::URL->new->scheme('http')->path('/pks/lookup')->query(
		op => 'get',
		options => 'mr',
	);

	my $urlBase = $lookupUrlBase->clone->query({ search => $search });
	my @promises = map { $c->get_200_p($urlBase->clone->host_port($_)) } (
		# https://sks-keyservers.net/overview-of-pools.php
		'ha.pool.sks-keyservers.net:11371',
		'p80.pool.sks-keyservers.net:80',
		'ipv4.pool.sks-keyservers.net:11371',
		'pgp.mit.edu:11371',
		'pgp.mit.edu:80',
		'keyserver.ubuntu.com:11371',
		'keyserver.ubuntu.com:80',
		'subset.pool.sks-keyservers.net:11371',
		'pool.sks-keyservers.net:11371',
	);
	return $c->p_race(@promises)->then(sub {
		return _normalize_key(shift->res->body);
	})->catch(sub {
		# if any error was a 404, prefer 404
		return undef if List::Util::any { $_ == 404 } @_;
		# otherwise, pass it all along
		return @_;
	});
};

# "cron" minion job that deletes expired keys and schedules minion jobs for any keys that are stale enough to need an update
app->minion->add_task(phe_update => sub {
	my $job = shift;
	return $job->finish('previous job still active') unless my $guard = $job->minion->guard('phe_update_job', 60 * 60);

	# delete expired cache entries
	$job->app->pg->db->query_p(
		'delete from phe_cache where atime + cast(? as interval) <= current_timestamp',
		"$expireAfter seconds",
	)->then(sub {
		# schedule refresh for outdateds
		return $job->app->pg->db->query_p(
			'select fingerprint from phe_cache where coalesce(mtime, ctime) + cast(? as interval) <= current_timestamp',
			"$refreshAfter seconds",
		);
	})->then(sub {
		my $results = shift;
		while (my $fingerprint = $results->array) {
			$fingerprint = $fingerprint->[0];
			$job->minion->enqueue(phe_update_fingerprint => [ $fingerprint ]);
		}
	})->catch(sub { $job->fail(@_) })->wait;
})->add_task(phe_update_fingerprint => sub {
	my $job = shift;
	my $fingerprint = $job->args->[0];
	return unless $fingerprint =~ $reSearch; # ignore bad input here

	$job->app->lookup_p($fingerprint)->then(sub {
		my $keydata = shift;
		return unless $keydata; # ignore missing keys
		my $sha1 = Mojo::Util::sha1_sum($keydata);
		return $job->app->pg->db->query_p(<<~'SQL', $fingerprint, $sha1, $keydata);
			insert into phe_cache (fingerprint, sha1, keydata)
			values (?, ?, ?)
			on conflict (fingerprint) do update set
				sha1 = excluded.sha1,
				keydata = excluded.keydata,
				mtime = current_timestamp
		SQL
	})->catch(sub { $job->fail(@_) })->wait;
});

helper keydata_p => sub {
	my $c = shift;
	my $search = shift;
	my $promise = Mojo::Promise->new;
	$c->pg->db->update_p(
		'phe_cache',
		{ atime => \'current_timestamp' },
		{ fingerprint => $search },
		{ returning => [
			\'extract(epoch from coalesce(mtime, ctime)) as mtime',
			'sha1',
			'keydata',
		] },
	)->then(sub {
		if (my $cache = shift->hashes->first) {
			$c->app->log->debug("cache hit: $search");
			return $promise->resolve($cache);
		}

		return $c->lookup_p($search)->then(sub {
			my $keydata = shift;
			unless ($keydata) {
				return $promise->resolve(undef);
			}
			$c->app->log->info("cache fill: $search");
			return $c->pg->db->insert_p('phe_cache', {
				fingerprint => $search,
				atime => \'current_timestamp',
				sha1 => Mojo::Util::sha1_sum($keydata),
				keydata => $keydata,
			}, { returning => [
				\'extract(epoch from coalesce(mtime, ctime)) as mtime',
				'sha1',
			] })->then(sub {
				my $cache = shift->hashes->first;
				$cache->{keydata} = $keydata;
				return $promise->resolve($cache);
			});
		});
	})->catch(sub { $promise->reject(@_) });
	return $promise;
};

# If a keyserver does not support adding keys via HTTP, then requests to do so should return an appropriate HTTP error code, such as 403 ("Forbidden") if key submission has been disallowed, or 501 ("Not Implemented") if the server does not support HTTP key submission.
sub _not_implemented {
	my $c = shift;
	my $text = shift // 'http://beesbeesbees.com/';
	$c->res->headers->cache_control('public, max-age=' . $expireAfter);
	return $c->render(status => 501, format => 'text', text => $text . "\n");
}

get '/pks/lookup' => sub {
	my $c = shift;

	return _not_implemented($c, "unsupported 'op' value") unless ($c->param('op') // '') eq 'get';

	my $search = $c->param('search') // '';
	return _not_implemented($c, "unsupported 'search' format (expected $reSearch)") unless $search =~ $reSearch;

	$c->app->log->info($c->req->url->to_abs->to_string);

	$c->render_later;
	return $c->keydata_p($search)->then(sub {
		my $res = shift;
		return $c->reply->not_found unless $res;

		return $c->rendered(304) if $c->is_fresh(
			etag => 'sha1:' . $res->{sha1},
			last_modified => Mojo::Date->new($res->{mtime}),
		);

		my $expires = Mojo::Date->new($res->{mtime} + $expireAfter);
		$c->res->headers->expires($expires)->cache_control('public');

		return $c->render(
			format => 'text',
			text => $res->{keydata},
		);
	})->catch(sub { $c->reply->exception(@_) })->wait;
};

if (app->mode eq 'development') {
	# TODO secure this
	my $minionRoute = app->routes->under('/minion');
	plugin 'Minion::Admin' => { route => $minionRoute };
}

get '/' => 'index';

any '/*' => sub { return _not_implemented(shift) };

# https://tools.ietf.org/html/draft-shaw-openpgp-hkp-00

app->start;

__DATA__
@@ index.html.ep
# TODO a "pretty" homepage (redirect to github?)
@@ migrations.sql
-- 1 up
create table phe_cache (
	fingerprint text not null primary key,
	atime timestamp,
	mtime timestamp,
	ctime timestamp not null default current_timestamp,
	sha1 text not null,
	keydata text not null
);
-- 1 down
drop table phe_cache;
