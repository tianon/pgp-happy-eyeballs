FROM golang:1.10-alpine3.7

RUN apk add --no-cache --virtual .lol \
		git \
	&& go get -v -d -u github.com/valyala/fasthttp \
	&& apk del .lol

WORKDIR /go/src/pgp-happy-eyeballs
COPY *.go ./

RUN go install -v -ldflags '-d -s -w' -a -tags netgo -installsuffix netgo ./...

# set up nsswitch.conf for Go's "netgo" implementation (which we explicitly use)
# - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
# - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf
RUN [ ! -e /etc/nsswitch.conf ] && echo 'hosts: files dns' > /etc/nsswitch.conf

EXPOSE 9000
CMD ["pgp-happy-eyeballs"]
