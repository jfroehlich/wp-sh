#!/usr/bin/env bash

set -euEo pipefail   # Error handling
#shopt -s extglob     # Expand file globs 

VERSION="0.0.1"
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
#SCRIPT_PATH="$(cd -- "$(dirname "$0")" > /dev/null 2>&1 ; pwd -P )"

# --- START OF ENV VARS ---

WP_TEMP_DIR="wp-content/temp"
WP_SITE_DIR="${PWD}/test"
WP_CONFIG_FILE="wp-config.php"

WP_DB_NAME="dbname"
WP_DB_USER="dbuser"
WP_DB_PASSWORD="dbpassword"
WP_DB_HOST="localhost"
WP_DB_CHARSET="utf-8"
WP_DB_COLLATE=""

# --- END OF ENV VARS ---


function _fn_cleanup {
	unset WP_TEMP_DIR
}

function _fn_log_err {
	printf "\n=== \e[1m\e[31mUNCHECKED ERROR\e[0m\n%s\n%s\n%s\n%s\n\n" \
		"  - script    = ${SCRIPT_NAME:-${0}}" \
		"  - function  = ${1} / ${2}" \
		"  - line      = ${3}" \
		"  - exit code = ${4}" >&2
}

trap '_fn_log_err "${FUNCNAME[0]:-?}" "${BASH_COMMAND:-?}" "${LINENO:-?}" "${?:-?}"' ERR
trap '_fn_cleanup || :' SIGINT SIGTERM EXIT

_fn_msg() {
	echo >&2 -e "${1-}"
}

function fn_usage {
	cat <<- EOM
	SYNOPSIS
	    ./${SCRIPT_NAME:-${0}} [ OPTION... ] core [ latest ] 
	    ./${SCRIPT_NAME:-${0}} [ OPTION... ] config [ list | get | set ] 

	DESCRIPTION
	    There is wp-cli but that is php itself and doesn't work it's 'magic' on
	    some webhosts where things are locked down. This is a posix compliant
	    bash script to do the most basic maintenance things.

	OPTIONS

	    -h --help		This help message and exits.
	    -v --version	Display the version and exits.
	    -e --env		Loads a file with the environement settings.
	
	COMMANDS

	    core
	       This command handles management of WordPress core like upgrading
	       files or setting up the basic WordPress. Like bringing you there as
	       far as possible.

	       latest   
	            Install the latest version of WordPress. This installs core if
	            there is none yet and upgrades existing installations.
 
	    config
	        Handles constants in the wp-config.php file.
	
	        list
	            List the constants (and table_prefix) with keys and values in
	            the wp-config.php as a list that could be easily parsed e.g.
	            with sed or awk. It does not list dynamic values like 
	            "__dir__ . 'somevalue'" or multiline values.
	        
	        get <key> <fallback>
	            Get the value for a constant or the table_prefix. It takes an
	            optional fallback value which is returned when the option was
	            not found.
	EOM
}
# --- custom functions ---

function fn_version {
	echo "${VERSION}"
}

function fn_load_env {
	echo "param1: $1"
}

# --- wp-config ---

function fn_config_list {
	if [ ! -f "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_SITE_DIR}/${WP_CONFIG_FILE}'"
		return 1
	fi

	sed -En \
		-e "s/^[[:space:]]*define\([[:space:]]*['\"](.*)['\"][[:space:]]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\);[[:space:]]*$/\"\1\": \"\2\"/p" \
		-e "s/^[[:space:]]*define\([[:space:]]*['\"](.*)['\"][[:space:]]*,[[:space:]]*(false|true|[[:digit:]]\+)[[:space:]]*\);[[:space:]]*$/\"\1\": \2/p" \
		-e "s/^[[:space:]]*\\\$table_prefix[[:space:]]*=[[:space:]]*[\"'](.*)[\"'][[:space:]]*;/\"table_prefix\": \"\1\"/p" \
		"${WP_SITE_DIR}/${WP_CONFIG_FILE}"
}

function fn_config_get {
	local name="$1"
	local default="${2:-}"

	if [ ! -r "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_SITE_DIR}/${WP_CONFIG_FILE}'"
		return 1
	fi

	if [ "${name}" == 'table_prefix' ]; then
		sed -En \
			-e "s/^[[:space:]]*\\\$table_prefix[[:space:]]*=[[:space:]]*[\"'](.*)[\"'][[:space:]]*;/\1/p" \
			"${WP_SITE_DIR}/${WP_CONFIG_FILE}" || echo "${default}"
	else 
		sed -En \
			-e "s/^[[:space:]]*define\([[:space:]]*['\"]${name}['\"][[:space:]]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\);[[:space:]]*$/\1/p" \
			-e "s/^[[:space:]]*define\([[:space:]]*['\"]${name}['\"][[:space:]]*,[[:space:]]*(false|true|[[:digit:]]\+)[[:space:]]*\);[[:space:]]*$/\1/p" \
			"${WP_SITE_DIR}/${WP_CONFIG_FILE}" || echo "${default}"
	fi
}

function fn_config_set {
	local KEY="${1}"
	local VALUE="${2}"

	if [ ! -f "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_SITE_DIR}/${WP_CONFIG_FILE}'"
		return 1
	fi
	
	if [ ! -w "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config is not writable at '${WP_SITE_DIR}/${WP_CONFIG_FILE}'"
		return 1
	fi

	# TODO Set table_prefix, too
	if [ "${KEY}" == 'table_prefix' ]; then
		echo "Setting the table_prefix is not implemented yet."
	fi

	if [ "${VALUE}" == 'true' ] || [ "${VALUE}" == 'false' ] || [[ "${VALUE}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
		# inspired from: https://superuser.com/questions/590630/sed-how-to-replace-line-if-found-or-append-to-end-of-file-if-not-found
		# should be posix compliend and run on osx and linux
		sed -i.tmp -E -e "/^[[:space:]]*define\([[:space:]]*['\"]${KEY}['\"][[:space:]]*,[[:space:]]*/{" \
			-e 'h' \
			-e "s/.*/define( '${KEY}', ${VALUE} );/" \
			-e '}' \
			-e '/Add any custom values between this line and the "stop editing" line./{x' \
			-e '/^$/{' \
			-e "s//define( '${KEY}', ${VALUE} );/" \
			-e 'H' \
			-e '}' \
			-e 'x' \
			-e '}' "${WP_SITE_DIR}/${WP_CONFIG_FILE}"
	else
		# inspired from: https://superuser.com/questions/590630/sed-how-to-replace-line-if-found-or-append-to-end-of-file-if-not-found
		# should be posix compliend and run on osx and linux
		sed -i.tmp -E -e "/^[[:space:]]*define\([[:space:]]*['\"]${KEY}['\"][[:space:]]*,[[:space:]]*/{" \
			-e 'h' \
			-e "s/.*/define( '${KEY}', '${VALUE}' );/" \
			-e '}' \
			-e '/Add any custom values between this line and the "stop editing" line./{x' \
			-e '/^$/{' \
			-e "s//define( '${KEY}', '${VALUE}' );/" \
			-e 'H' \
			-e '}' \
			-e 'x' \
			-e '}' "${WP_SITE_DIR}/${WP_CONFIG_FILE}"
	fi
	rm -rf "${WP_SITE_DIR}/${WP_CONFIG_FILE}.tmp"
}

#
# Downloads and installs the latest WordPress
#
function fn_core_latest {
	# TODO Create the force attribute to override an existing installation
	# TODO Make the wordpress file url a variable.
	# TODO Hash the salts
	# TODO Set the db parameters

	_fn_msg "Cleaning up temp folder..."
	mkdir -p "${WP_SITE_DIR}/${WP_TEMP_DIR}"
	rm -rf "${WP_SITE_DIR}/${WP_TEMP_DIR}/wordpress" || true
	rm -rf "${WP_SITE_DIR}/${WP_TEMP_DIR}/latest.tar.gz" || true

	_fn_msg "Downloading and unpacking the latest WordPress in temp folder..."
	(cd "${WP_SITE_DIR}/${WP_TEMP_DIR}" && curl -O "https://wordpress.org/latest.tar.gz")
	(cd "${WP_SITE_DIR}/${WP_TEMP_DIR}" && tar -zxvf latest.tar.gz)
	
	_fn_msg "Setting WordPress in maintenance mode..."
	touch "${WP_SITE_DIR}/.maintenance"

	_fn_msg "Upgrading admin..."
	mv -f "${WP_SITE_DIR}/wp-admin" "${WP_SITE_DIR}/wp-admin.old" || true
	mv -f "${WP_SITE_DIR}/${WP_TEMP_DIR}/wordpress/wp-admin" "${WP_SITE_DIR}/"

	_fn_msg "Upgrading includes..."
	mv -f "${WP_SITE_DIR}/wp-includes" "${WP_SITE_DIR}/wp-includes.old" || true
	mv -f "${WP_SITE_DIR}/${WP_TEMP_DIR}/wordpress/wp-includes" "${WP_SITE_DIR}/"

	_fn_msg "Upgrading top level scripts..."
	cp -rf "${WP_SITE_DIR}/${WP_TEMP_DIR}"/wordpress/*.php "${WP_SITE_DIR}/"

	# TODO Check plugins
	# TODO Check themes

	if [ ! -f "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
		_fn_msg "Oh, no wp-config. Let's initialize it..."
		cp "${WP_SITE_DIR}/${WP_TEMP_DIR}/wordpress/wp-config-sample.php" "${WP_SITE_DIR}/${WP_CONFIG_FILE}"

		fn_config_set "DB_NAME" "${WP_DB_NAME}"
		fn_config_set "DB_USER" "${WP_DB_USER}"
		fn_config_set "DB_PASSWORD" "${WP_DB_PASSWORD}"
		fn_config_set "DB_HOST" "${WP_DB_HOST}"
		fn_config_set "DB_CHARSET" "${WP_DB_CHARSET}"
		fn_config_set "DB_COLLATE" "${WP_DB_COLLATE}"
	fi

	_fn_msg "Cleanup ..."
	[ -f "${WP_SITE_DIR}/.maintenance" ] && rm -rf "${WP_SITE_DIR}/.maintenance"
	[ -d "${WP_SITE_DIR}/wp-admin.old" ] && rm -rf "${WP_SITE_DIR}/wp-admin.old"
	[ -d "${WP_SITE_DIR}/wp-includes.old" ] && rm -rf "${WP_SITE_DIR}/wp-includes.old"
	rm -rf "${WP_SITE_DIR}/wordpress"

	_fn_msg "Done. Please login to your site as admin to upgrade the db."
}


# --- main ---

function fn_main {
	while :; do
		case "${1:-}" in
			-e | --env ) fn_load_env "${2-}"; shift 2;;
			-v | --version ) fn_version; exit;;

			core )
				case ${2:-} in
					latest ) fn_core_latest; exit;;
					* ) _fn_msg "Manages WordPress core files.\n  wp core latest\n"; exit;;
				esac;;
				

			config )
				case ${2:-} in
					list ) fn_config_list; exit;;
					get ) fn_config_get "${3}" "${4:-}"; exit;;
					set ) fn_config_set "${3}" "${4}"; exit;;
					* ) _fn_msg "Manages the wp-config.php file.\n  wp config list\n  wp config [ get | set ] <key> <value>\n"; exit;;
				esac;;
			
			-h | --help ) fn_usage; exit ;;
			*           ) _fn_msg "${SCRIPT_NAME:-}: unrecognized option '${1:-}'"; fn_usage; exit 1;;
		esac
	done
}

fn_main "${@}"
