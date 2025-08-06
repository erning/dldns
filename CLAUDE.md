# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

The project is designed to be cross-compiled for MIPS architecture routers:

```bash
# Build for MIPS64 (target architecture)
GOOS=linux GOARCH=mips64 GOMIPS64=softfloat go build -ldflags "-s -w"

# Build for current system
go build

# Run tests (if any were added)
go test ./...
```

## Project Architecture

This is a Dynamic DNS (DDNS) client specifically designed for Linode DNS. The project consists of:

### Core Components

- **main.go**: Entry point with command-line interface and IP detection logic
  - Command-line flags for Linode token, domain ID, IPv4/IPv6 selection
  - Outbound IP detection via UDP connections to DNS servers
  - Record comparison and update orchestration

- **linode.go**: Linode API integration
  - OAuth2 authentication with Linode API
  - Domain record management (create, update, delete)
  - Conflict resolution with CNAME records
  - Duplicate record cleanup

### Key Design Patterns

1. **Outbound IP Detection**: Uses UDP connections to public DNS servers (114.114.114.114:53 for IPv4, 2400:3200:baba::1:53 for IPv6) to determine the router's external IP

2. **Smart Record Management**: 
   - Automatically removes conflicting CNAME records
   - Cleans up duplicate A/AAAA records
   - Updates existing records when IP changes
   - Only creates new records when none exist

3. **Efficient Updates**: Skips API calls when current IP matches DNS record

### Configuration

- TTL is hardcoded to 30 seconds
- Supports both IPv4 and IPv6 simultaneously
- Requires Linode API token and domain ID as command-line parameters
- Binary is statically linked and stripped for deployment on embedded routers

### Dependencies

- `github.com/linode/linodego`: Linode API client
- `golang.org/x/oauth2`: OAuth2 authentication

The compiled binary is designed to be deployed on routers and run as a cron job or persistent service to keep DNS records updated with the current external IP address.