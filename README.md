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

This tool is intended to sit in front of clients to keyservers (most easily via DNS or transparent traffic hijacking) and "multiplex" requests across several servers simultaneously, returning the fastest successful result.

## Known Issues

- using `gpg --send-keys` doesn't work, among other things (our server hijacking is a tad too aggressive -- should probably *only* perform our aggressive logic for `.../pks/lookup?op=get...` requests and pass everything else through as-is as a standard transparent proxy)

## "Happy Eyeballs" ?

See [RFC 6555](https://tools.ietf.org/html/rfc6555).
