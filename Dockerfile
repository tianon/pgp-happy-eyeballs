FROM golang:1.12-alpine

RUN set -eux; \
	apk add --no-cache --virtual .lol git; \
	go get -v -d -u github.com/valyala/fasthttp; \
	apk del --no-network .lol

WORKDIR /go/src/pgp-happy-eyeballs
COPY *.go ./

RUN go install -v -ldflags '-d -s -w' -a -tags netgo -installsuffix netgo ./...

EXPOSE 9000
CMD ["pgp-happy-eyeballs"]
