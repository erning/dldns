# AGENTS.md

Dynamic DNS client for Linode. Detects outbound IP, updates DNS records. Designed for embedded routers.

## Structure

```
dldns/
├── main.go           # CLI, IP detection, update orchestration
├── linode.go         # Linode API: auth, record CRUD, conflict resolution
├── .github/workflows/release.yml  # Multi-arch cross-compilation
└── go.mod
```

## Where to Look

| Task | Location |
|------|----------|
| Add CLI flags | `main.go` flag.* calls |
| Change IP detection | `main.go` getOutboundIPv4/v6 |
| Modify DNS update logic | `linode.go` updateDomainRecord |
| Add new target arch | `.github/workflows/release.yml` |

## Build

```bash
# Dev build
go build

# Cross-compile for routers
CGO_ENABLED=0 GOOS=linux GOARCH=mips64 GOMIPS64=softfloat go build -ldflags "-s -w"  # ER4/ERLite/USG
CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -ldflags "-s -w"    # ERX
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags "-s -w"                       # GL.iNet
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-s -w"                       # x86_64

# Test
go test ./...
```

## Conventions

- TTL hardcoded to 30 seconds (`const TTL = 30`)
- Statically linked (`CGO_ENABLED=0`) for embedded deployment
- Strip symbols (`-ldflags "-s -w"`) to minimize binary size
- Uses UDP connection to detect outbound IP (no actual data sent)

## Key Patterns

**IP Detection**: Opens UDP socket to public DNS server, reads local address. No packets sent.
```go
conn, _ := net.Dial("udp", "114.114.114.114:53")
localAddr := conn.LocalAddr().(*net.UDPAddr)
return localAddr.IP
```

**Smart Updates**: DNS lookup before API call to skip unnecessary updates.

**Conflict Resolution**: Auto-removes CNAME records conflicting with A/AAAA. Deduplicates records.

## Dependencies

- `github.com/linode/linodego` — Linode API client
- `golang.org/x/oauth2` — Token auth

## Release

Tag with `v*` triggers GitHub Actions → builds 4 binaries → creates release.
