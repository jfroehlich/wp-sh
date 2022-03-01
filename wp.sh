#!/usr/bin/env bash

set -euEo pipefail   # Error handling
#shopt -s extglob     # Expand file globs 

VERSION="0.0.1"
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
#SCRIPT_PATH="$(cd -- "$(dirname "$0")" > /dev/null 2>&1 ; pwd -P )"

# --- START OF ENV VARS ---
# These settings can be adjusted with an .env file

WP_SITE_DIR="${PWD}"
WP_CONTENT_DIR="${WP_SITE_DIR}/wp-content"
WP_PLUGIN_DIR="${WP_CONTENT_DIR}/plugins"
WP_THEME_DIR="${WP_CONTENT_DIR}/themes"
WP_TEMP_DIR="${WP_CONTENT_DIR}/temp"
WP_CONFIG_FILE="${WP_SITE_DIR}/wp-config.php"
WP_SALT_LENGTH=80

WP_DB_NAME="dbname"
WP_DB_USER="dbuser"
WP_DB_PASSWORD="dbpassword"
WP_DB_HOST="localhost"
WP_DB_CHARSET="utf-8"
WP_DB_COLLATE=""

WP_INSTALLED_PLUGINS=(
	"wordpress-seo"
	"contact-form-7"
	"duplicate-post"
)

WP_REMOVED_PLUGINS=(
	"hello"
)

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

function fn_env_load {
	default_env="${PWD}/.env"
	local env_path="${1:-$default_env}"
	set -a
	# shellcheck source=/dev/null
	source "${env_path}"
	set +a
}

# --- CONFIG MANAGEMENT ---

function fn_config_list {
	if [ ! -f "${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_CONFIG_FILE}'"
		return 1
	fi

	sed -En \
		-e "s/^[[:space:]]*define\([[:space:]]*['\"](.*)['\"][[:space:]]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\);[[:space:]]*$/\"\1\": \"\2\"/p" \
		-e "s/^[[:space:]]*define\([[:space:]]*['\"](.*)['\"][[:space:]]*,[[:space:]]*(false|true|[[:digit:]]\+)[[:space:]]*\);[[:space:]]*$/\"\1\": \2/p" \
		-e "s/^[[:space:]]*\\\$table_prefix[[:space:]]*=[[:space:]]*[\"'](.*)[\"'][[:space:]]*;/\"table_prefix\": \"\1\"/p" \
		"${WP_CONFIG_FILE}"
}

function fn_config_get {
	local name="$1"
	local default="${2:-}"

	if [ ! -r "${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_CONFIG_FILE}'"
		return 1
	fi

	if [ "${name}" == 'table_prefix' ]; then
		sed -En \
			-e "s/^[[:space:]]*\\\$table_prefix[[:space:]]*=[[:space:]]*[\"'](.*)[\"'][[:space:]]*;/\1/p" \
			"${WP_CONFIG_FILE}" || echo "${default}"
	else 
		sed -En \
			-e "s/^[[:space:]]*define\([[:space:]]*['\"]${name}['\"][[:space:]]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\);[[:space:]]*$/\1/p" \
			-e "s/^[[:space:]]*define\([[:space:]]*['\"]${name}['\"][[:space:]]*,[[:space:]]*(false|true|[[:digit:]]\+)[[:space:]]*\);[[:space:]]*$/\1/p" \
			"${WP_CONFIG_FILE}" || echo "${default}"
	fi
}

function fn_config_set {
	local KEY="${1}"
	local VALUE="${2}"

	if [ ! -f "${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config does not exist at '${WP_CONFIG_FILE}'"
		return 1
	fi
	
	if [ ! -w "${WP_CONFIG_FILE}" ]; then
		_fn_msg "wp-config is not writable at '${WP_CONFIG_FILE}'"
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
			-e '}' "${WP_CONFIG_FILE}"
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
			-e '}' "${WP_CONFIG_FILE}"
	fi
	rm -rf "${WP_CONFIG_FILE}.tmp"
}

function fn_config_resalt {
	fn_config_set 'AUTH_KEY' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'SECURE_AUTH_KEY' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'LOGGED_IN_KEY' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'NONCE_KEY' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'AUTH_SALT' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'SECURE_AUTH_SALT' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'LOGGED_IN_SALT' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
	fn_config_set 'NONCE_SALT' "$(openssl rand -base64 ${WP_SALT_LENGTH} | tr -d '\n/\"')"
}

# --- CORE ---------------------------------------------------------------------

#
# Downloads and installs the latest WordPress
#
function fn_core_latest {
	# TODO Create the force attribute to override an existing installation
	# TODO Make the wordpress file url a variable.

	if [ ! -w "${WP_SITE_DIR}" ]; then
		mkdir -p "${WP_SITE_DIR}"
	fi

	_fn_msg "Cleaning up temp folder..."
	mkdir -p "${WP_TEMP_DIR}"
	rm -rf "${WP_TEMP_DIR}/wordpress" || true
	rm -rf "${WP_TEMP_DIR}/latest.tar.gz" || true

	_fn_msg "Downloading and unpacking the latest WordPress in temp folder..."
	(cd "${WP_TEMP_DIR}" && curl -O "https://wordpress.org/latest.tar.gz")
	(cd "${WP_TEMP_DIR}" && tar -zxvf latest.tar.gz)
	
	_fn_msg "Setting WordPress in maintenance mode..."
	touch "${WP_SITE_DIR}/.maintenance"

	_fn_msg "Upgrading admin..."
	mv -f "wp-admin" "${WP_SITE_DIR}/wp-admin.old" || true
	mv -f "${WP_TEMP_DIR}/wordpress/wp-admin" "${WP_SITE_DIR}/"

	_fn_msg "Upgrading includes..."
	mv -f "${WP_SITE_DIR}/wp-includes" "${WP_SITE_DIR}/wp-includes.old" || true
	mv -f "${WP_TEMP_DIR}/wordpress/wp-includes" "${WP_SITE_DIR}/"

	_fn_msg "Upgrading top level scripts..."
	cp -rf "${WP_TEMP_DIR}"/wordpress/*.php "${WP_SITE_DIR}/"

	if [ ! -d "${WP_THEME_DIR}" ]; then
		mkdir -p "${WP_THEME_DIR}"	
		printf "<?php\n// Silence is golden.\n" > "${WP_THEME_DIR}/index.php"
		# TODO Download and unpack required themes
	fi

	if [ ! -f "${WP_CONFIG_FILE}" ]; then
		_fn_msg "Oh, no wp-config. Let's initialize it..."
		cp "${WP_TEMP_DIR}/wordpress/wp-config-sample.php" "${WP_CONFIG_FILE}"

		fn_config_set "DB_NAME" "${WP_DB_NAME}"
		fn_config_set "DB_USER" "${WP_DB_USER}"
		fn_config_set "DB_PASSWORD" "${WP_DB_PASSWORD}"
		fn_config_set "DB_HOST" "${WP_DB_HOST}"
		fn_config_set "DB_CHARSET" "${WP_DB_CHARSET}"
		fn_config_set "DB_COLLATE" "${WP_DB_COLLATE}"

		fn_config_resalt
	fi

	if [ ! -d "${WP_PLUGIN_DIR}" ]; then
	 	_fn_msg "Initializing the plugin directory"
		mkdir -p "${WP_PLUGIN_DIR}"	
		printf "<?php\n// Silence is golden.\n" > "${WP_PLUGIN_DIR}/index.php"

		_fn_msg "Installing latest plugins..."
		fn_plugin_latest "--all"

		_fn_msg "Removing plugins..."
		for plugin_name in "${WP_REMOVED_PLUGINS[@]}"; do
			fn_plugin_remove "${plugin_name}"
		done
	fi

	_fn_msg "Cleanup ..."
	[ -f "${WP_SITE_DIR}/.maintenance" ] && rm -rf "${WP_SITE_DIR}/.maintenance"
	[ -d "${WP_SITE_DIR}/wp-admin.old" ] && rm -rf "${WP_SITE_DIR}/wp-admin.old"
	[ -d "${WP_SITE_DIR}/wp-includes.old" ] && rm -rf "${WP_SITE_DIR}/wp-includes.old"
	rm -rf "${WP_SITE_DIR}/wordpress"

	_fn_msg "Done. Please login to your site as admin to upgrade the db."
}

# --- PLUGIN FUNCTIONS ---

function fn_plugin_latest {
	local plugin_name="${1:-}"

	if [ -z "${plugin_name}" ]; then
		_fn_msg "No plugin to install"
		return 1
	fi

	if [ "${plugin_name}" == '--all' ]; then
		for plugin_name in "${WP_INSTALLED_PLUGINS[@]}"; do
			fn_plugin_latest "${plugin_name}"
		done
		return
	fi

	_fn_msg "Finding the download link..."
	PLUGIN_PACKAGE_URL=$(curl "https://wordpress.org/plugins/${plugin_name}/" 2>/dev/null | grep -Eo "https://downloads\.wordpress\.org/[a-zA-Z0-9./?=_%:-]*" | head -1)

	_fn_msg "Downloading from '${PLUGIN_PACKAGE_URL}'"
	(cd "${WP_TEMP_DIR}" && curl -O "${PLUGIN_PACKAGE_URL}")
	(cd "${WP_TEMP_DIR}" && unzip "${PLUGIN_PACKAGE_URL##*/}")

	if [ -d "${WP_PLUGIN_DIR}/${plugin_name}" ]; then
		mv -f "${WP_PLUGIN_DIR}/${plugin_name}" "${WP_PLUGIN_DIR}/${plugin_name}.old"
	fi

	_fn_msg "Installing '${plugin_name}'. Cleanup..."
	mv -f "${WP_TEMP_DIR}/${plugin_name}" "${WP_PLUGIN_DIR}/"

	_fn_msg "Done. Cleanup..."
	rm -rf "${WP_PLUGIN_DIR:?}/${plugin_name}.old"
	rm -rf "${WP_TEMP_DIR:?}/plugin_name"
	rm -rf "${WP_TEMP_DIR:?}/${PLUGIN_PACKAGE_URL##*/}"
}

function fn_plugin_remove {
	local plugin_name="${1}"

	_fn_msg "NOT IMPLEMENTED YET" 
}

# --- main ---

function fn_main {
	# Try to load the local env for this project
	if [ -f "${PWD}/.env" ]; then
		fn_env_load "${PWD}/.env"
	fi

	while :; do
		case "${1:-}" in
			-e | --env ) fn_env_load "${2:-}"; shift 2;;
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
					resalt ) fn_config_resalt; exit;;
					* ) _fn_msg "Manages the wp-config.php file.\n  wp config list\n  wp config [ get | set ] <key> <value>\n"; exit;;
				esac;;
			
			plugin )
				case ${2:-} in
				 	latest ) fn_plugin_latest "${3}"; exit;;
					remove ) fn_plugin_remove "${3}"; exit;; 
					* ) _fn_msg "Manages plugins.\n wp plugin [ latest ] <plugin>\n"; exit;;
				esac;;
			
			-h | --help ) fn_usage; exit ;;
			*           ) _fn_msg "${SCRIPT_NAME:-}: unrecognized option '${1:-}'"; fn_usage; exit 1;;
		esac
	done
}

fn_main "${@}"
