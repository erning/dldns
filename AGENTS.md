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
│   └── mocks/                  # ubus, jsonfilter, UCI, curl, dig, and notify fakes
└── .github/workflows/release.yml
```

## Where to Look

| Task | Location |
| --- | --- |
| Change CLI or help | `dldns` `show_*_help` and `run_*` functions |
| Change interface discovery | `load_interface_snapshot`, `select_sync_interfaces`, `run_ip` |
| Change address validation | `valid_ipv4`, `valid_ipv6`, `ipv4_scope`, `public_ipv6` |
| Change Linode API transport | `linode_request` |
| Change DNS preflight | `dns_query_set`, `dns_record_matches`, `dns_preflight_matches` |
| Change DNS reconciliation | `append_record_cache`, `reconcile_record_type`, `sync_one_record`, `run_update` |
| Change UCI configuration | `load_sync_config`, `append_sync_record`, `append_sync_nameserver` |
| Change notifications | `append_sync_event`, `run_sync_notify` |
| Change release behavior | `.github/workflows/release.yml` |

## Runtime

There is no build step and no architecture-specific output. The executable is the `dldns` source file itself.

OpenWrt runtime dependencies vary by command:

- `ip`: `ubus`, `jsonfilter`; JSON output also needs `jshn.sh`.
- `update`: `curl`, `jsonfilter`.
- `sync`: `ubus`, `curl`, `jsonfilter`, `/lib/functions.sh`; optional `dig` for the DNS preflight.

The script uses `local`, which is supported by BusyBox ash. Lint it with the ShellCheck `dash` dialect rather than strict POSIX `sh`.

## Test

```sh
shellcheck -s dash \
    dldns tests/test-dldns-*.sh \
    tests/mocks/curl tests/mocks/dig tests/mocks/functions.sh \
    tests/mocks/notify tests/mocks/ubus
tests/test-dldns-ip.sh
tests/test-dldns-update.sh
tests/test-dldns-sync.sh
```

Tests must use the dependency overrides (`DLDNS_UBUS`, `DLDNS_JSONFILTER`, `DLDNS_CURL`, `DLDNS_DIG`, `DLDNS_UCI_FUNCTIONS_LIB`, and `DLDNS_LINODE_API_URL`) and must never call the real Linode API or DNS resolvers.

## Conventions

- Keep the program compatible with OpenWrt BusyBox ash.
- No command may mutate UCI, netifd, routes, cron, or other local router state.
- `ip` is read-only; `--external` may only perform an address probe.
- Default Linode TTL is 300 seconds. Accept any positive integer and let the API handle normalization.
- Token files are read from the first line. Never print the token or place it directly in curl arguments.
- `update` changes only explicitly selected address families.
- `sync` reconciles both A and AAAA for every configured record, clearing a family omitted from that record's UCI entry.
- The optional DNS preflight skips API access when any configured resolver returns the expected A/AAAA sets and no CNAME for every configured record; `--force-api` bypasses it.
- A missing optional `dig` command must emit a warning before falling back to the API.
- When API access is needed, fetch the domain record list once or by pagination instead of once per configured name.
- Remove same-name CNAME records before creating A/AAAA records and deduplicate all reconciled records.
- Treat successful discovery with no public address for a family as an empty desired set and clear that family; make no DNS changes when address discovery fails.
- Treat interfaces explicitly reported as down as contributing no addresses and continue with other interfaces. A down `_6` child must not discard its up parent's addresses. If all selected interfaces are down, clear the configured records' A/AAAA sets; unreadable or invalid interface state remains a discovery failure.

## Release

A `v*` tag triggers GitHub Actions. The workflow lints and tests the script, then publishes `dldns` and `dldns.sha256` as release assets.
