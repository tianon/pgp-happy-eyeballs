FROM golang:1.10-alpine3.7

RUN apk add --no-cache --virtual .lol \
		git \
	&& go get -v -d -u github.com/valyala/fasthttp \
	&& apk del .lol

WORKDIR /go/src/pgp-happy-eyeballs
COPY *.go ./

RUN go install -v -ldflags '-d -s -w' -a -tags netgo -installsuffix netgo ./...

EXPOSE 9000
CMD ["pgp-happy-eyeballs"]
