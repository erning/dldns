# README

Dynamic DNS for Linode.

This program detects the local IP address and automatically updates the
corresponding DNS record if it changes.  IPv6 is also supported.

### Quick start

```
$ git clone https://github.com/erning/dldns
$ cd dldns
$ GOOS=linux GOARCH=mips go build
$ scp dldns user@router:
```
