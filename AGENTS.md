# AGENTS.md

OpenWrt Shell client for Linode dynamic DNS. It discovers addresses from `ubus` and reconciles A/AAAA records through the Linode API.

## Structure

```text
dldns/
├── dldns                       # BusyBox ash program: ip, update, and sync
├── tests/
│   ├── test-dldns-ip.sh        # Interface discovery and output tests
│   ├── test-dldns-update.sh    # Single-record reconciliation tests
│   ├── test-dldns-sync.sh      # UCI-driven synchronization tests
│   └── mocks/                  # ubus, jsonfilter, UCI, curl, and notify fakes
└── .github/workflows/release.yml
```

## Where to Look

| Task | Location |
| --- | --- |
| Change CLI or help | `dldns` `show_*_help` and `run_*` functions |
| Change interface discovery | `load_interface_snapshot`, `select_sync_interfaces`, `run_ip` |
| Change address validation | `valid_ipv4`, `valid_ipv6`, `ipv4_scope`, `public_ipv6` |
| Change Linode API transport | `linode_request` |
| Change DNS reconciliation | `reconcile_record_type`, `sync_one_record`, `run_update` |
| Change UCI configuration | `load_sync_config`, `append_sync_record` |
| Change notifications | `append_sync_event`, `run_sync_notify` |
| Change release behavior | `.github/workflows/release.yml` |

## Runtime

There is no build step and no architecture-specific output. The executable is the `dldns` source file itself.

OpenWrt runtime dependencies vary by command:

- `ip`: `ubus`, `jsonfilter`; JSON output also needs `jshn.sh`.
- `update`: `curl`, `jsonfilter`.
- `sync`: `ubus`, `curl`, `jsonfilter`, `/lib/functions.sh`.

The script uses `local`, which is supported by BusyBox ash. Lint it with the ShellCheck `dash` dialect rather than strict POSIX `sh`.

## Test

```sh
shellcheck -s dash \
    dldns tests/test-dldns-*.sh \
    tests/mocks/curl tests/mocks/functions.sh \
    tests/mocks/notify tests/mocks/ubus
tests/test-dldns-ip.sh
tests/test-dldns-update.sh
tests/test-dldns-sync.sh
```

Tests must use the dependency overrides (`DLDNS_UBUS`, `DLDNS_JSONFILTER`, `DLDNS_CURL`, `DLDNS_UCI_FUNCTIONS_LIB`, and `DLDNS_LINODE_API_URL`) and must never call the real Linode API.

## Conventions

- Keep the program compatible with OpenWrt BusyBox ash.
- No command may mutate UCI, netifd, routes, cron, or other local router state.
- `ip` is read-only; `--external` may only perform an address probe.
- Default and minimum Linode TTL is 300 seconds; accept only values supported by `valid_record_ttl`.
- Token files are read from the first line. Never print the token or place it directly in curl arguments.
- `update` changes only explicitly selected address families.
- `sync` reconciles both A and AAAA for every configured record, clearing a family omitted from that record's UCI entry.
- Remove same-name CNAME records before creating A/AAAA records and deduplicate all reconciled records.
- Refuse synchronization when a required family has no discovered public address.

## Release

A `v*` tag triggers GitHub Actions. The workflow lints and tests the script, then publishes `dldns` and `dldns.sha256` as release assets.
