# DEPRECATED

See [#4](https://github.com/tianon/pgp-happy-eyeballs/issues/4) for some discussion around why this tool is no longer actively maintained (nor recommended for use).

The TL;DR is that the SKS network is mostly too decentralized now to track well with a naive approach like that of this tool.

# PGP "Happy Eyeballs"

PGP keyservers are flaky:

- https://github.com/docker-library/official-images/issues/4252#issuecomment-381783035
- https://github.com/docker-library/cassandra/pull/131#issuecomment-358444537
- https://github.com/docker-library/tomcat/issues/87
- https://github.com/docker-library/tomcat/pull/108
- https://github.com/docker-library/mysql/issues/263#issuecomment-354025886
- https://github.com/docker-library/httpd/issues/66#issuecomment-316832441
- https://github.com/docker-library/php/issues/586
- https://github.com/docker-library/wordpress/pull/291
- https://github.com/docker-library/postgres/pull/471#issuecomment-407902513

This tool was intended to sit in front of clients to keyservers (most easily via DNS or transparent traffic hijacking) and "multiplex" requests across several servers simultaneously, returning the fastest successful result.

**Note:** if you're looking at this tool, you should seriously consider using [the `hkps://keys.openpgp.org` server](https://keys.openpgp.org/about) / ["Hagrid"](https://gitlab.com/hagrid-keyserver/hagrid) instead! (It's a refreshingly modern take on OpenPGP infrastructure in general.)

Barring that, I would recommend sticking with a single stable server like `hkps://keyserver.ubuntu.com`.

## How to Use

The easiest/intended way to use this (and the way Tianon used it) is to hijack your personal DNS requests and redirect relevant domains to a running instance of it. The hard part of that is doing so in a way that also affects any Docker instances and works in a way that other Docker instances can hit the running instance of `pgp-happy-eyeballs` successfully.

See [rawdns](https://github.com/tianon/rawdns) for the tool Tianon uses; example configuration snippet:

```json
...
	"ha.pool.sks-keyservers.net.": {
		"type": "static",
		"cnames": [
			"pgp-happy-eyeballs.docker"
		],
		"nameservers": [
			"127.0.0.1"
		]
	},
...
```

See also [the `hack-my-builds.sh` script](hack-my-builds.sh) which was intended for use in disposable CI environments such as those provided by Travis CI (see [docker-library/php#666](https://github.com/docker-library/php/pull/666) and the linked PRs for implementation examples).

## Known Issues

- using `gpg --send-keys` doesn't work, among other things (our server hijacking is a tad too aggressive -- should probably *only* perform our aggressive logic for `.../pks/lookup?op=get...` requests and pass everything else through as-is as a standard transparent proxy)

## "Happy Eyeballs" ?

See [RFC 6555](https://tools.ietf.org/html/rfc6555).
