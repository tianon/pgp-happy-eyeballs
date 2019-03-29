FROM perl:5.28-slim

SHELL ["bash", "-Eeuo", "pipefail", "-xc"]

# secure by default ♥ (thanks to sri!)
RUN apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates wget \
		gnupg dirmngr \
		gcc libc6-dev \
	; \
	rm -rf /var/lib/apt/lists/*
ENV PERL_CPANM_OPT --verbose --mirror https://cpan.metacpan.org
# TODO find a way to make --mirror-only / SSL work with backpan too :(
RUN cpanm Digest::SHA Module::Signature
# TODO find a way to make --verify work with backpan as well :'(
#ENV PERL_CPANM_OPT $PERL_CPANM_OPT --verify

RUN apt-get update; \
	apt-get install -y --no-install-recommends \
		libpq-dev \
		libssl-dev \
		zlib1g-dev \
# "watch" for a poor-man's cron
		procps \
	; \
	rm -rf /var/lib/apt/lists/*

# https://metacpan.org/pod/release/SRI/Mojolicious-7.94/lib/Mojo/IOLoop.pm#DESCRIPTION
ENV LIBEV_FLAGS 4
# epoll (Linux)

COPY cpanfile /tmp/phe/
RUN cpanm --installdeps --with-recommends --notest --verbose /tmp/phe; \
	rm -rf ~/.cpanm

COPY lite.pl /usr/local/bin/

ENV MOJO_LISTEN http://*:11371,http://*:80
# if we can't get the key within one HTTP redirect, this server isn't worth it
ENV MOJO_MAX_REDIRECTS 1
# if a server can't respond within a second, cut it from your life
ENV MOJO_REQUEST_TIMEOUT 1
# if a key is more than one megabyte (ascii armoured, sometimes + HTML), it isn't worth the time
ENV MOJO_MAX_MESSAGE_SIZE 1048576

# PostgreSQLLLLLL (auto_migrations and Minion try to connect even for "version" or "help")
#RUN lite.pl help; lite.pl version

CMD ["lite.pl", "daemon"]
