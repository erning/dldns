#!/bin/sh

set -u

TEST_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
SCRIPT=$PROJECT_DIR/dldns
MOCK_DIR=$TEST_DIR/mocks

export DLDNS_UBUS="$MOCK_DIR/ubus"
export DLDNS_JSONFILTER="$MOCK_DIR/jsonfilter"

failures=0

run_case()
{
	name=$1
	expected_status=$2
	shift 2
	if output=$("$SCRIPT" ip "$@" 2>&1); then
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

expect_exact_output()
{
	expected=$1
	if [ "$output" != "$expected" ]; then
		printf 'not ok - output: got "%s", expected "%s"\n' "$output" "$expected"
		failures=$((failures + 1))
	fi
}

run_case auto_discovery 0
expect_output 'pppoe1'
expect_output '100.100.135.196'
expect_output 'cgnat'
expect_output 'pppoe2'
expect_output '116.237.37.232'
expect_output 'public'

run_case ipv4_value 0 -4 --format value pppoe2
expect_exact_output '116.237.37.232'

run_case child_interface_is_canonicalized 0 -6 --format value pppoe1_6
expect_exact_output '2409:8a1e:8f01:2a3c::1'

run_case standalone_child_interface 0 -6 --format value standalone_6
expect_exact_output '240e::1'

export MOCK_UBUS_SCENARIO=canonical_parent_error
run_case child_parent_read_failure 1 pppoe1 pppoe2_6
expect_output 'unable to resolve interface names'
unset MOCK_UBUS_SCENARIO

run_case value_requires_one_interface 2 -4 --format value
expect_output 'value format requires exactly one interface'

run_case invalid_format 2 --format yaml pppoe1
expect_output 'unsupported output format: yaml'

run_case missing_interface 1 missing
expect_output 'interface not found: missing'

export MOCK_UBUS_SCENARIO=ipv6_scope
run_case public_ipv6_prefix_boundaries 0 -6 --format value pppoe3
expect_exact_output '2000::1
3FFF::1'
unset MOCK_UBUS_SCENARIO

if [ "$failures" -ne 0 ]; then
	printf '%s test assertion(s) failed\n' "$failures" >&2
	exit 1
fi

printf 'all ip tests passed\n'
