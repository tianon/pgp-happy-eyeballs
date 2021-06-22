package main

// this file implements the "child" half of our CGI server

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/valyala/fasthttp"
)

var servers = [][2]string{
	{"pgp.mit.edu", "11371"},
	{"pgp.mit.edu", "80"},
	{"keyserver.ubuntu.com", "11371"},
	{"keyserver.ubuntu.com", "80"},

	// 2021-06-22, scraped from https://sks-keyservers.net/status/
	{"agora.cenditel.gob.ve", "11371"},
	{"gozer.rediris.es", "11371"},
	{"keys.andreas-puls.de", "11371"},
	{"keys.niif.hu", "11371"},
	{"keys2.andreas-puls.de", "11371"},
	{"keys3.andreas-puls.de", "11371"},
	{"keyserver-01.2ndquadrant.com", "11371"},
	{"keyserver-02.2ndquadrant.com", "11371"},
	{"keyserver-03.2ndquadrant.com", "11371"},
	{"keyserver.dobrev.eu", "11371"},
	{"keyserver.escomposlinux.org", "11371"},
	{"keyserver.taygeta.com", "11371"},
	{"keyserver1.computer42.org", "11371"},
	{"keywin.trifence.ch", "11371"},
	{"pgp.cyberbits.eu", "11371"},
	{"pgpkeys.eu", "11371"},
	{"sks.hnet.se", "11371"},
	{"sks.pgpkeys.eu", "11371"},
	{"sks.pod01.fleetstreetops.com", "11371"},
	{"sks.pod02.fleetstreetops.com", "11371"},
	{"sks.pyro.eu.org", "11371"},
	{"sks.srv.dumain.com", "11371"},
	{"sks.stsisp.ro", "11371"},
	{"zuul.rediris.es", "11371"},
}

var (
	fasthttpClient = fasthttp.Client{
		Name: "pgp-happy-eyeballs",

		DialDualStack: true,
	}

	start = time.Now()

	successMutex = &sync.Mutex{}
	failureMutex = &sync.Mutex{}
	finalFailure = &bytes.Buffer{}
)

func writeResponse(resp *fasthttp.Response, w io.Writer) error {
	// this returns the full "HTTP/x.x 2xx ..." status line as well, which CGI requires as a "Status:" header instead
	head := resp.Header.Header()
	statusEnd := bytes.IndexByte(head, '\n')
	statusLine := head[:statusEnd+1]
	statusSpace := bytes.IndexByte(statusLine, ' ')
	head = append([]byte("Status: "+string(statusLine[statusSpace+1:])), head[statusEnd+1:]...)

	_, err := w.Write(head)
	if err != nil {
		return err
	}

	err = resp.BodyWriteTo(w)
	if err != nil {
		return err
	}

	return nil
}

func doTheThing(server string, ip net.IP, port, path string) {
	thisReqStart := time.Now()

	ipName := ip.String()
	if ip.To4() == nil {
		// must be IPv6, and need extra [...] for disambiguation
		ipName = "[" + ipName + "]"
	}
	url := "http://" + ipName + ":" + port + path

	req, resp := fasthttp.AcquireRequest(), fasthttp.AcquireResponse()
	req.Reset()
	resp.Reset()
	req.SetRequestURI(url)
	req.Header.SetHost(server)

	// TODO consider making timeout configurable
	err := fasthttpClient.DoTimeout(req, resp, 1*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: fetching %s: %s\n", url, err)
		return
	}

	if resp.Header.StatusCode() != fasthttp.StatusOK {
		fmt.Fprintf(os.Stderr, "error: fetching %s: unexpected status code: %d\n", url, resp.Header.StatusCode())
		failureMutex.Lock()
		defer failureMutex.Unlock()
		finalFailure.Reset()
		err = writeResponse(resp, finalFailure)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: saving failure from %s: %s\n", url, err)
		}
		return
	}

	successMutex.Lock()

	fmt.Fprintf(os.Stderr, "note: yay, winner (%s / %s): %s\n", time.Since(thisReqStart).Round(time.Millisecond), time.Since(start).Round(time.Millisecond), url)

	err = writeResponse(resp, os.Stdout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: printing reply from %s: %s\n", url, err)
	}

	os.Exit(0)
}

func handleRequest(path string) {
	if path == "" || path[0] != '/' {
		path = "/" + path
	}

	seenIP := sync.Map{}

	var wg sync.WaitGroup
	for _, server := range servers {
		wg.Add(1)
		go func(name, port string) {
			defer wg.Done()

			ips, err := net.LookupIP(name)
			if err != nil {
				fmt.Fprintf(os.Stderr, "warning: failed to lookup %s (ignoring): %s\n", name, err)
				return
			}

			for _, ip := range ips {
				// skip any IP+port combo we've already checked (especially since *.pool.sks-keyservers.net will likely have lots of overlapping servers)
				ipStr := ip.String() + ":" + port
				if _, loaded := seenIP.LoadOrStore(ipStr, true); loaded {
					continue
				}

				doTheThing(name, ip, port, path)
			}
		}(server[0], server[1])
	}
	wg.Wait()

	// FAILURE!!! so sad (return the final failing result so we have something useful to report back)
	failureMutex.Lock()
	fmt.Fprintf(os.Stderr, "error: wow, total failure (%s)\n", time.Since(start).Round(time.Millisecond))
	_, err := finalFailure.WriteTo(os.Stdout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: writing final failure failed: %s\n", err)
	}
	os.Exit(1)
}
