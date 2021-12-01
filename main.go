package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
)

var token string
var domainID int
var v4 bool
var v6 bool
var verbose bool

const TTL = 30
const IPv4_TO_ROUTE = "114.114.114.114:53"
const IPv6_TO_ROUTE = "[2400:3200:baba::1]:53"

func main() {
	flag.StringVar(&token, "token", "", "token")
	flag.IntVar(&domainID, "domain", 0, "domainID")
	flag.BoolVar(&v4, "4", false, "ipv4")
	flag.BoolVar(&v6, "6", false, "ipv6")
	flag.BoolVar(&verbose, "v", false, "verbose")
	flag.Parse()

	if len(token) == 0 || domainID == 0 {
		fmt.Printf("Usage: %s [options] name\n", os.Args[0])
		flag.PrintDefaults()
		return
	}

	if !v4 && !v6 {
		fmt.Printf("Usage: %s [options] name\n", os.Args[0])
		flag.PrintDefaults()
		return
	}

	if flag.NArg() <= 0 {
		fmt.Printf("Usage: %s [options] name\n", os.Args[0])
		flag.PrintDefaults()
		return
	}

	name := flag.Arg(0)
	domain, err := getDomain(token, domainID)
	if err != nil {
		fmt.Println(err)
		return
	}

	if v4 {
		process(getOutboundIPv4(), name, domain)
	}
	if v6 {
		process(getOutboundIPv6(), name, domain)
	}
}

func process(ip net.IP, name string, domain string) {
	if ip == nil {
		return
	}
	var ipv string
	if ip.To4() == nil {
		ipv = "ip6"
	} else {
		ipv = "ip4"
	}
	ips, _ := net.DefaultResolver.LookupIP(context.Background(), ipv,
		fmt.Sprintf("%s.%s", name, domain),
	)
	if len(ips) == 1 && ips[0].Equal(ip) {
		if verbose {
			fmt.Printf("skip %s\n", ip)
		}
		return
	}
	err := updateDomainRecord(token, domainID, name, ip.String(), TTL)
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("updated %s -> %s\n", name, ip)
}

func getOutboundIPv4() net.IP {
	conn, err := net.Dial("udp", IPv4_TO_ROUTE)
	if err != nil {
		return nil
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP
}

func getOutboundIPv6() net.IP {
	conn, err := net.Dial("udp6", IPv6_TO_ROUTE)
	if err != nil {
		return nil
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP
}
