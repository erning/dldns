# README

Dynamic DNS for Linode.

This program detects the local IP address and automatically updates the
corresponding DNS record if it changes.  IPv6 is also supported.

### Quick start

```sh
git clone https://github.com/erning/dldns
cd dldns
GOOS=linux GOARCH=mips64 GOMIPS64=softfloat go build -ldflags "-s -w"
scp dldns user@router:
```
