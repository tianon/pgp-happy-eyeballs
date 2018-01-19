package main

import (
	"os"
)

func main() {
	path := os.Getenv("REQUEST_URI")
	if path != "" {
		handleRequest(path)
	} else {
		cgiServer()
	}
}
