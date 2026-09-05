#!/bin/sh

set -u

TEST_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
SCRIPT=$PROJECT_DIR/dldns
MOCK_DIR=$TEST_DIR/mocks
TMP_ROOT=${TMPDIR:-/tmp}/dldns-sync-test.$$
mkdir "$TMP_ROOT" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export DLDNS_UBUS="$MOCK_DIR/ubus"
export DLDNS_JSONFILTER="$MOCK_DIR/jsonfilter"
export DLDNS_CURL="$MOCK_DIR/curl"
export DLDNS_DIG="$MOCK_DIR/dig"
export DLDNS_UCI_FUNCTIONS_LIB="$MOCK_DIR/functions.sh"
export DLDNS_LINODE_API_URL=https://mock.invalid/v4

failures=0

reset_config()
{
	MOCK_CONFIG_DOMAIN_ID=123
	MOCK_CONFIG_DOMAIN=example.com
	MOCK_CONFIG_TOKEN=mock-token
	MOCK_CONFIG_TTL=300
	MOCK_CONFIG_NOTIFY=
	MOCK_CONFIG_INTERFACES=
	MOCK_CONFIG_NAMESERVERS=
	MOCK_CONFIG_RECORDS='soda 4 6'
	MOCK_DIG_SCENARIO=mismatch
	MOCK_UBUS_SCENARIO=
	MOCK_JSONFILTER_FAIL_EXPRESSION=
	DLDNS_DIG=$MOCK_DIR/dig
	export MOCK_CONFIG_DOMAIN_ID MOCK_CONFIG_DOMAIN MOCK_CONFIG_TOKEN MOCK_CONFIG_TTL
	export MOCK_CONFIG_NOTIFY MOCK_CONFIG_INTERFACES MOCK_CONFIG_NAMESERVERS MOCK_CONFIG_RECORDS
	export MOCK_DIG_SCENARIO DLDNS_DIG
	export MOCK_UBUS_SCENARIO MOCK_JSONFILTER_FAIL_EXPRESSION
}

run_case()
{
	name=$1
	expected_status=$2
	scenario=$3
	shift 3
	MOCK_CURL_LOG=$TMP_ROOT/$name.curl
	MOCK_DIG_LOG=$TMP_ROOT/$name.dig
	: >"$MOCK_CURL_LOG"
	: >"$MOCK_DIG_LOG"
	MOCK_SCENARIO=$scenario
	export MOCK_CURL_LOG MOCK_DIG_LOG MOCK_SCENARIO
	if output=$("$SCRIPT" sync "$@" 2>&1); then
		status=0
	else
		status=$?
	fi
	if [ "$status" -ne "$expected_status" ]; then
		printf 'not ok - %s (status %s, expected %s)\n%s\n' "$name" "$status" "$expected_status" "$output"
		failures=$((failures + 1))
		return
	fi
	printf 'ok - %s\n' "$name"
}

expect_output()
{
	needle=$1
	if ! printf '%s\n' "$output" | grep -F -- "$needle" >/dev/null; then
		printf 'not ok - output missing: %s\n%s\n' "$needle" "$output"
		failures=$((failures + 1))
	fi
}

expect_no_output()
{
	needle=$1
	if printf '%s\n' "$output" | grep -F -- "$needle" >/dev/null; then
		printf 'not ok - unexpected output: %s\n%s\n' "$needle" "$output"
		failures=$((failures + 1))
	fi
}

expect_methods()
{
	expected=$1
	actual=$(tr '\n' ' ' <"$MOCK_CURL_LOG" | sed 's/ $//')
	if [ "$actual" != "$expected" ]; then
		printf 'not ok - methods: got "%s", expected "%s"\n' "$actual" "$expected"
		failures=$((failures + 1))
	fi
}

expect_dns_output()
{
	needle=$1
	if ! grep -F -- "$needle" "$MOCK_DIG_LOG" >/dev/null; then
		printf 'not ok - DNS query missing: %s\n' "$needle"
		failures=$((failures + 1))
	fi
}

expect_no_dns_queries()
{
	if [ -s "$MOCK_DIG_LOG" ]; then
		printf 'not ok - unexpected DNS queries:\n'
		cat "$MOCK_DIG_LOG"
		failures=$((failures + 1))
	fi
}

reset_config
MOCK_CONFIG_INTERFACES='pppoe1|pppoe2'
MOCK_CONFIG_RECORDS='soda 4 6|soda-v4 4|soda-v6 6'
export MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS
run_case configured_interfaces 0 sync --verbose
expect_output 'interface source: UCI configuration'
expect_output 'public IPv4 set: 116.237.37.232'
expect_output 'soda-v4 AAAA: clear'
expect_output 'summary: changes=8 status=0'
expect_no_output mock-token
expect_methods 'GET POST POST POST POST POST POST POST POST'

reset_config
MOCK_CONFIG_RECORDS='soda-v6 6'
export MOCK_CONFIG_RECORDS
run_case auto_discovery 0 sync --verbose
expect_output 'discovered proto=pppoe interfaces'
expect_methods 'GET POST POST POST'

reset_config
MOCK_CONFIG_INTERFACES=pppoe1
export MOCK_CONFIG_INTERFACES
run_case cli_overrides_config 0 sync --verbose pppoe2
expect_output 'interface source: command line'
expect_output 'interfaces: pppoe2'
expect_methods 'GET POST POST POST'

reset_config
MOCK_DIG_SCENARIO=match_pppoe2
export MOCK_DIG_SCENARIO
run_case system_dns_match_skips_api 0 sync --verbose pppoe2
expect_output 'DNS system soda.example.com. A: match'
expect_output 'DNS preflight matched; skipping Linode API'
expect_methods ''
expect_dns_output 'system soda.example.com. A'
expect_dns_output 'system soda.example.com. AAAA'
expect_dns_output 'system soda.example.com. CNAME'

reset_config
MOCK_CONFIG_NAMESERVERS='192.0.2.53|resolver.example'
MOCK_DIG_SCENARIO=match_pppoe2
export MOCK_CONFIG_NAMESERVERS MOCK_DIG_SCENARIO
run_case configured_nameservers_match 0 sync --verbose pppoe2
expect_output 'DNS 192.0.2.53 soda.example.com. A: match'
expect_output 'DNS preflight matched via 192.0.2.53'
expect_methods ''
expect_dns_output '192.0.2.53 soda.example.com. A'
expect_dns_output '192.0.2.53 soda.example.com. CNAME'

reset_config
MOCK_CONFIG_NAMESERVERS='192.0.2.53|resolver.example'
MOCK_DIG_SCENARIO=match_second
export MOCK_CONFIG_NAMESERVERS MOCK_DIG_SCENARIO
run_case any_nameserver_match_skips_api 0 sync --verbose pppoe2
expect_output 'DNS preflight did not match via 192.0.2.53'
expect_output 'DNS preflight matched via resolver.example'
expect_output 'DNS preflight matched; skipping Linode API'
expect_methods ''
expect_dns_output '192.0.2.53 soda.example.com. A'
expect_dns_output 'resolver.example soda.example.com. CNAME'

reset_config
MOCK_CONFIG_RECORDS='soda 4'
MOCK_DIG_SCENARIO=error
export MOCK_CONFIG_RECORDS MOCK_DIG_SCENARIO
run_case dns_error_falls_back_to_api 0 sync_unchanged --verbose pppoe2
expect_output 'DNS system soda.example.com. A: unavailable (command-failed)'
expect_output 'DNS preflight did not match; querying Linode API'
expect_methods 'GET'

reset_config
MOCK_CONFIG_RECORDS='soda 4'
DLDNS_DIG=$TMP_ROOT/missing-dig
export MOCK_CONFIG_RECORDS DLDNS_DIG
run_case missing_dig_warns_and_skips_preflight 0 sync_unchanged pppoe2
expect_output 'warning: DNS preflight skipped: dig command not found'
expect_methods 'GET'
expect_no_dns_queries

reset_config
MOCK_CONFIG_RECORDS='soda 4'
MOCK_DIG_SCENARIO=match_pppoe2
export MOCK_CONFIG_RECORDS MOCK_DIG_SCENARIO
run_case force_api_skips_dns 0 sync_unchanged --force-api --verbose pppoe2
expect_output 'DNS preflight skipped: --force-api'
expect_methods 'GET'
expect_no_dns_queries

reset_config
MOCK_DIG_SCENARIO=match_pppoe2
export MOCK_DIG_SCENARIO
run_case paginated_api_snapshot 0 sync_pages --force-api --verbose pppoe2
expect_output 'summary: changes=0 status=0'
expect_methods 'GET GET'
expect_no_dns_queries

reset_config
MOCK_UBUS_SCENARIO=equivalent_ipv6
export MOCK_UBUS_SCENARIO
run_case equivalent_discovered_and_api_ipv6 0 sync_equivalent6 --force-api --verbose pppoe2
expect_methods GET
expect_output 'summary: changes=0 status=0'

for invalid_response in malformed missing_data invalid_data missing_pages invalid_pages incomplete_record invalid_record; do
	reset_config
	run_case "$invalid_response" 1 "$invalid_response" --force-api pppoe2
	expect_methods GET
	expect_no_dns_queries
done

reset_config
run_case invalid_later_page_does_not_mutate_records 1 bad_second_page --force-api pppoe2
expect_methods 'GET GET'

reset_config
MOCK_CONFIG_RECORDS='soda 4'
export MOCK_CONFIG_RECORDS
run_case unrelated_apex_and_inherited_ttl_are_valid 0 apex_record --force-api pppoe2
expect_methods GET

reset_config
MOCK_UBUS_SCENARIO=ipv6_scope
MOCK_CONFIG_RECORDS='soda 6'
export MOCK_UBUS_SCENARIO MOCK_CONFIG_RECORDS
run_case only_global_ipv6_prefix_is_synchronized 0 ipv6_scope --force-api pppoe3
expect_methods 'GET POST POST'

reset_config
MOCK_CONFIG_RECORDS='soda-v4 4'
export MOCK_CONFIG_RECORDS
run_case no_public_ipv4_clears_a 0 sync_clear4 --verbose pppoe1
expect_output 'soda-v4 A: clear'
expect_output 'deleted       A'
expect_output 'summary: changes=1 status=0'
expect_methods 'GET DELETE'

reset_config
MOCK_CONFIG_RECORDS='soda 4 6'
export MOCK_CONFIG_RECORDS
run_case no_public_ipv4_clears_a_and_syncs_aaaa 0 sync_ipv6_only --verbose pppoe1
expect_output 'soda A: clear'
expect_output 'created       AAAA'
expect_output 'summary: changes=2 status=0'
expect_methods 'GET DELETE POST'

reset_config
MOCK_CONFIG_RECORDS='soda 4 6'
export MOCK_CONFIG_RECORDS
run_case no_public_ipv6_clears_aaaa_and_syncs_a 0 sync_ipv4_only --verbose pppoe3
expect_output 'soda AAAA: clear'
expect_output 'created       A'
expect_output 'summary: changes=2 status=0'
expect_methods 'GET POST DELETE'

reset_config
run_case address_discovery_error_makes_no_api_requests 1 sync missing
expect_output 'unable to read interface addresses: missing'
expect_methods ''
expect_no_dns_queries

for discovery_error in child_error child_down parent_down malformed_child list_error invalid_address incomplete_address; do
	reset_config
	MOCK_UBUS_SCENARIO=$discovery_error
	export MOCK_UBUS_SCENARIO
	run_case "$discovery_error" 1 sync pppoe2
	expect_methods ''
	expect_no_dns_queries
done

reset_config
export MOCK_JSONFILTER_FAIL_EXPRESSION='@["ipv4-address"]'
run_case address_parser_error 1 sync pppoe2
expect_methods ''
expect_no_dns_queries

reset_config
MOCK_UBUS_SCENARIO=canonical_parent_error
export MOCK_UBUS_SCENARIO
run_case canonical_parent_failure_does_not_use_partial_interfaces 1 sync pppoe1 pppoe2_6
expect_methods ''
expect_no_dns_queries

reset_config
export MOCK_JSONFILTER_FAIL_EXPRESSION='@.proto'
run_case canonical_parent_parser_failure 1 sync pppoe1 pppoe2_6
expect_methods ''
expect_no_dns_queries

reset_config
run_case standalone_ipv6_interface 0 sync --force-api standalone_6
expect_methods 'GET POST'

reset_config
MOCK_CONFIG_RECORDS='soda 5'
export MOCK_CONFIG_RECORDS
run_case invalid_family 2 sync pppoe2
expect_output 'unsupported address family'
expect_methods ''

reset_config
MOCK_CONFIG_RECORDS='soda 4|soda 6'
export MOCK_CONFIG_RECORDS
run_case duplicate_record 2 sync pppoe2
expect_output 'duplicate record entry'
expect_methods ''

reset_config
TOKEN_FILE=$TMP_ROOT/token
printf '%s\n' file-token >"$TOKEN_FILE"
MOCK_CONFIG_TOKEN=@$TOKEN_FILE
MOCK_CONFIG_RECORDS='soda-v6 6'
export MOCK_CONFIG_TOKEN MOCK_CONFIG_RECORDS
run_case token_file 0 sync pppoe1
expect_methods 'GET POST'

reset_config
MOCK_CONFIG_TTL=120
MOCK_CONFIG_INTERFACES=pppoe2
MOCK_CONFIG_RECORDS='soda-v4 4'
MOCK_EXPECT_TTL=120
export MOCK_CONFIG_TTL MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS MOCK_EXPECT_TTL
run_case short_ttl 0 sync
expect_methods 'GET POST'
MOCK_EXPECT_TTL=
export MOCK_EXPECT_TTL

reset_config
MOCK_CONFIG_TTL=60
MOCK_CONFIG_INTERFACES=pppoe2
MOCK_CONFIG_RECORDS='soda-v4 4'
MOCK_EXPECT_TTL=60
export MOCK_CONFIG_TTL MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS MOCK_EXPECT_TTL
run_case arbitrary_ttl 0 sync
expect_methods 'GET POST'
MOCK_EXPECT_TTL=
export MOCK_EXPECT_TTL

reset_config
MOCK_CONFIG_TTL=0
export MOCK_CONFIG_TTL
run_case invalid_ttl 2 sync
expect_output 'must be a positive integer'
expect_methods ''

reset_config
MOCK_CONFIG_DOMAIN=
export MOCK_CONFIG_DOMAIN
run_case missing_domain 2 sync
expect_output 'option domain in dldns.main must be a valid DNS name'
expect_methods ''

reset_config
MOCK_NOTIFY_LOG=$TMP_ROOT/notify.log
MOCK_CONFIG_NOTIFY=$MOCK_DIR/notify
MOCK_CONFIG_RECORDS='soda-v4 4'
export MOCK_NOTIFY_LOG MOCK_CONFIG_NOTIFY MOCK_CONFIG_RECORDS
run_case notification 0 sync pppoe2
expect_methods 'GET POST'
if [ ! -f "$MOCK_NOTIFY_LOG" ]; then
	printf 'not ok - notification hook was not called\n'
	failures=$((failures + 1))
else
	grep -F 'status=success changes=1' "$MOCK_NOTIFY_LOG" >/dev/null || failures=$((failures + 1))
	grep -F 'created A soda-v4 - 116.237.37.232' "$MOCK_NOTIFY_LOG" >/dev/null || failures=$((failures + 1))
fi

reset_config
MOCK_NOTIFY_LOG=$TMP_ROOT/unchanged-notify.log
MOCK_CONFIG_NOTIFY=$MOCK_DIR/notify
MOCK_CONFIG_INTERFACES=pppoe2
MOCK_CONFIG_RECORDS='soda 4'
export MOCK_NOTIFY_LOG MOCK_CONFIG_NOTIFY MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS
run_case no_notification_when_unchanged 0 sync_unchanged
expect_methods GET
if [ -e "$MOCK_NOTIFY_LOG" ]; then
	printf 'not ok - unchanged sync called notification hook\n'
	failures=$((failures + 1))
fi

reset_config
MOCK_CONFIG_INTERFACES=pppoe2
MOCK_CONFIG_RECORDS='soda-v4 4'
export MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS
run_case unspecified_family_is_cleared 0 sync_clear6
expect_output 'deleted'
expect_output 'AAAA'
expect_no_output 'unchanged'
expect_methods 'GET DELETE DELETE'

if [ "$failures" -ne 0 ]; then
	printf '%s test assertion(s) failed\n' "$failures" >&2
	exit 1
fi

printf 'all sync tests passed\n'
