#!/bin/sh

set -u

TEST_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
SCRIPT=$PROJECT_DIR/dldns
MOCK_DIR=$TEST_DIR/mocks
TMP_ROOT=${TMPDIR:-/tmp}/dldns-test.$$
mkdir "$TMP_ROOT" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export DLDNS_JSONFILTER="$MOCK_DIR/jsonfilter"
export DLDNS_CURL="$MOCK_DIR/curl"
export DLDNS_LINODE_API_URL=https://mock.invalid/v4
TOKEN_FILE=$TMP_ROOT/linode.token
printf '%s\n' mock-token >"$TOKEN_FILE"

failures=0

run_case()
{
	name=$1
	expected_status=$2
	scenario=$3
	shift 3
	MOCK_CURL_LOG=$TMP_ROOT/$name.curl
	: >"$MOCK_CURL_LOG"
	export MOCK_CURL_LOG
	MOCK_SCENARIO=$scenario
	export MOCK_SCENARIO

	if output=$("$SCRIPT" update --domain-id 123 --token-file "$TOKEN_FILE" "$@" 2>&1); then
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

expect_methods()
{
	expected=$1
	actual=$(tr '\n' ' ' <"$MOCK_CURL_LOG" | sed 's/ $//')
	if [ "$actual" != "$expected" ]; then
		printf 'not ok - methods: got "%s", expected "%s"\n' "$actual" "$expected"
		failures=$((failures + 1))
	fi
}

run_case unchanged 0 unchanged -4 116.237.37.232 soda.p
expect_output unchanged
expect_methods GET

run_case create 0 create -4 116.237.37.232 soda.p
expect_output created
expect_methods 'GET POST'

run_case update 0 update -4 116.237.37.232 soda.p
expect_output updated
expect_methods 'GET PUT'

run_case multiple_ipv6 0 multi6 -6 240e::1 --ipv6 240e::2 soda.p
expect_output '240e::1'
expect_output '240e::9 -> 240e::2'
expect_methods 'GET PUT'

run_case delete_surplus_ipv6 0 surplus6 -6 240e::1 -6 240e::2 soda.p
expect_output 'surplus record'
expect_methods 'GET DELETE'

run_case replace_cname 0 cname -4 116.237.37.232 soda.p
expect_output 'conflicting CNAME'
expect_output created
expect_methods 'GET DELETE POST'

run_case update_ttl 0 ttl --ttl 300 -4 116.237.37.232 soda.p
expect_output updated
expect_methods 'GET PUT'

run_case duplicate_input 0 create -4 116.237.37.232 --ipv4 116.237.37.232 soda.p
expect_output created
expect_methods 'GET POST'

run_case invalid_ipv4 2 unchanged -4 999.1.2.3 soda.p
expect_output 'invalid IPv4 address'
expect_methods ''

run_case invalid_ipv6 2 unchanged -6 240e::1::2 soda.p
expect_output 'invalid IPv6 address'
expect_methods ''

run_case clear_ipv4 0 unchanged --clear-ipv4 soda.p
expect_output '116.237.37.232'
expect_output 'surplus record'
expect_methods 'GET DELETE'

run_case clear_ipv6 0 multi6 --clear-ipv6 soda.p
expect_output '240e::1'
expect_output '240e::9'
expect_methods 'GET DELETE DELETE'

run_case clear_does_not_delete_cname 0 cname --clear-ipv4 soda.p
expect_methods GET

run_case clear_ipv4_conflict 2 unchanged --clear-ipv4 -4 116.237.37.232 soda.p
expect_output 'cannot be combined'
expect_methods ''

run_case clear_ipv6_conflict 2 unchanged --clear-ipv6 -6 240e::1 soda.p
expect_output 'cannot be combined'
expect_methods ''

if [ "$failures" -ne 0 ]; then
	printf '%s test assertion(s) failed\n' "$failures" >&2
	exit 1
fi

printf 'all update tests passed\n'
