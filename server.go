package main

import (
	"net/http"
	"net/http/cgi"
)

func cgiServer() {
	cgiHandler := &cgi.Handler{
		Path: "/proc/self/exe",
		Dir:  ".",
	}
	go http.ListenAndServe(":80", cgiHandler)
	http.ListenAndServe(":11371", cgiHandler)
}
