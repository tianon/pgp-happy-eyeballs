FROM golang:1.13-buster AS build

WORKDIR /phe

COPY go.mod go.sum ./
RUN go mod verify
RUN go mod download

COPY *.go ./
RUN go build -v -tags netgo -installsuffix netgo -ldflags '-d -s -w' -o /pgp-happy-eyeballs ./...

# # TODO make proper tagged releases (with binaries) and consume those instead
FROM alpine:3.11

COPY --from=build /pgp-happy-eyeballs /usr/local/bin/

EXPOSE 9000
CMD ["pgp-happy-eyeballs"]
