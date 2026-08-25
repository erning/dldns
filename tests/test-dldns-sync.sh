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
export DLDNS_UCI_FUNCTIONS_LIB="$MOCK_DIR/functions.sh"
export DLDNS_LINODE_API_URL=https://mock.invalid/v4

failures=0

reset_config()
{
	MOCK_CONFIG_DOMAIN_ID=123
	MOCK_CONFIG_TOKEN=mock-token
	MOCK_CONFIG_TTL=300
	MOCK_CONFIG_NOTIFY=
	MOCK_CONFIG_INTERFACES=
	MOCK_CONFIG_RECORDS='soda 4 6'
	export MOCK_CONFIG_DOMAIN_ID MOCK_CONFIG_TOKEN MOCK_CONFIG_TTL
	export MOCK_CONFIG_NOTIFY MOCK_CONFIG_INTERFACES MOCK_CONFIG_RECORDS
}

run_case()
{
	name=$1
	expected_status=$2
	scenario=$3
	shift 3
	MOCK_CURL_LOG=$TMP_ROOT/$name.curl
	: >"$MOCK_CURL_LOG"
	MOCK_SCENARIO=$scenario
	export MOCK_CURL_LOG MOCK_SCENARIO
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
	if ! printf '%s\n' "$output" | grep -F "$needle" >/dev/null; then
		printf 'not ok - output missing: %s\n%s\n' "$needle" "$output"
		failures=$((failures + 1))
	fi
}

expect_no_output()
{
	needle=$1
	if printf '%s\n' "$output" | grep -F "$needle" >/dev/null; then
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
expect_methods 'GET POST POST POST POST GET POST GET POST POST POST'

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
MOCK_CONFIG_RECORDS='soda-v4 4'
export MOCK_CONFIG_RECORDS
run_case missing_public_ipv4 1 sync pppoe1
expect_output 'no public IPv4 address was found'
expect_methods ''

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
