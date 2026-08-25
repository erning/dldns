config_load()
{
	[ "$1" = dldns ]
}

config_get()
{
	variable=$1
	section=$2
	option=$3
	default=${4-}
	[ "$section" = main ] || return 1
	case "$option" in
		domain_id) value=${MOCK_CONFIG_DOMAIN_ID:-123} ;;
		token) value=${MOCK_CONFIG_TOKEN:-mock-token} ;;
		ttl) value=${MOCK_CONFIG_TTL:-300} ;;
		notify) value=${MOCK_CONFIG_NOTIFY:-} ;;
		*) value=$default ;;
	esac
	eval "$variable=\$value"
}

config_list_foreach()
{
	section=$1
	option=$2
	callback=$3
	[ "$section" = main ] || return 1
	case "$option" in
		interface) values=${MOCK_CONFIG_INTERFACES:-} ;;
		record) values=${MOCK_CONFIG_RECORDS:-} ;;
		*) values= ;;
	esac
	old_ifs=$IFS
	IFS='|'
	for value in $values; do
		[ -n "$value" ] && "$callback" "$value"
	done
	IFS=$old_ifs
}
