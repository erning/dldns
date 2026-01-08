# dldns

Dynamic DNS client for Linode.

This program detects the local IP address and automatically updates the corresponding DNS record if it changes. IPv6 is also supported.

## Supported Devices

Pre-built binaries are available in [Releases](https://github.com/erning/dldns/releases) for the following architectures:

| Binary | Architecture | Devices |
|--------|--------------|---------|
| `dldns-amd64` | x86_64 | Generic x86_64 Linux, OpenWrt x86 |
| `dldns-mips64` | MIPS64 (big-endian, softfloat) | Ubiquiti ER4, ERLite, USG |
| `dldns-mipsle` | MIPS32 (little-endian, softfloat) | Ubiquiti ERX |
| `dldns-arm64` | ARM64 | GL.iNet GL-MT3000, GL-MT2500, GL-BE3600, GL-MT3600BE |

### Device Architecture Reference

| Device | CPU | Go Build Flags |
|--------|-----|----------------|
| **Ubiquiti ER4** | Cavium Octeon MIPS64 | `GOARCH=mips64 GOMIPS64=softfloat` |
| **Ubiquiti ERLite** | Cavium Octeon MIPS64 | `GOARCH=mips64 GOMIPS64=softfloat` |
| **Ubiquiti USG** | Cavium Octeon MIPS64 | `GOARCH=mips64 GOMIPS64=softfloat` |
| **Ubiquiti ERX** | MediaTek MT7621 MIPS | `GOARCH=mipsle GOMIPS=softfloat` |
| **GL.iNet GL-MT3000** | MediaTek MT7981B ARM Cortex-A53 | `GOARCH=arm64` |
| **GL.iNet GL-MT2500** | MediaTek MT7981B ARM Cortex-A53 | `GOARCH=arm64` |
| **GL.iNet GL-BE3600** | MediaTek ARM Cortex-A53 | `GOARCH=arm64` |
| **GL.iNet GL-MT3600BE** | MediaTek Quad A53 | `GOARCH=arm64` |

## Usage

```sh
dldns -token <linode-api-token> -domain <domain-id> -4 -6 [-v] <record-name>
```

| Flag | Description |
|------|-------------|
| `-token` | Linode API token (required) |
| `-domain` | Linode domain ID (required) |
| `-4` | Enable IPv4 update |
| `-6` | Enable IPv6 update |
| `-v` | Verbose mode |
| `<record-name>` | Subdomain name to update (required) |

At least one of `-4` or `-6` must be specified.

## Quick Start

Download the pre-built binary for your device:

```sh
# Example for Ubiquiti ER4/ERLite/USG
curl -L -o dldns https://github.com/erning/dldns/releases/latest/download/dldns-mips64
chmod +x dldns
scp dldns user@router:
```

## Building from Source

```sh
git clone https://github.com/erning/dldns
cd dldns

# For MIPS64 (ER4, ERLite, USG)
CGO_ENABLED=0 GOOS=linux GOARCH=mips64 GOMIPS64=softfloat go build -ldflags "-s -w"

# For MIPS32 little-endian (ERX)
CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -ldflags "-s -w"

# For ARM64 (GL.iNet devices)
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags "-s -w"

# For x86_64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-s -w"
```

## License

MIT
