#!/usr/bin/env bash

# version   <your version>
# executed  <how it should be executed>
# task      <description>

set -euEo pipefail   # Error handling
#shopt -s extglob     # Expand file globs 

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
#SCRIPT_PATH="$(cd -- "$(dirname "$0")" > /dev/null 2>&1 ; pwd -P )"

WP_TEMP_DIR="wp-content/temp"
WP_SITE_DIR="${PWD}/test"
WP_CONFIG_FILE="wp-config.php"

WP_DB_NAME="works"

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
    _fn_msg "

SYNOPSIS
    ./${SCRIPT_NAME:-${0}} [ OPTION... ] COMMAND 

    COMMAND := {} 

DESCRIPTION
    bla blub my description

    This is the sub headline

      -h --help     The usage...



"
}
# --- custom functions ---

# --- wp-config ---

function fn_config_list {
    if [ ! -f "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
        _fn_msg "wp-config does not exist at '${WP_SITE_DIR}/${WP_CONFIG_FILE}'"
        return 1
    fi

    sed -En \
        -e "s|^[[:space:]]*define\([[:space:]]*['\"](.*)['\"][[:space:]]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\);[[:space:]]*$|\"\1\": \"\2\"|p" \
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

    # TODO Make posix complient
    # TODO Find booleans and numbers, too
    # TODO Find table_prefix, too
    grep -oP "^\s*define\(\s*['\"]${name}['\"]\s*,\s*['\"]\K[^'\"]+(?=[\'\"]\s*\)\s*;)" "${WP_SITE_DIR}/${WP_CONFIG_FILE}" || "${default}"
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

    # TODO Set booleans and numbers, too
    # TODO Set table_prefix, too

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

    if [ ! -f "${WP_SITE_DIR}/${WP_CONFIG_FILE}" ]; then
        _fn_msg "Oh, no wp-config. Let's initialize it..."
        cp "${WP_SITE_DIR}/${WP_TEMP_DIR}/wordpress/wp-config-sample.php" "${WP_SITE_DIR}/${WP_CONFIG_FILE}"

        fn_config_set "DB_NAME" "${WP_DB_NAME}"
    fi

    _fn_msg "Cleanup ..."
    [ -f "${WP_SITE_DIR}/.maintenance" ] && rm -rf "${WP_SITE_DIR}/.maintenance"
    [ -d "${WP_SITE_DIR}/wp-admin.old" ] && rm -rf "${WP_SITE_DIR}/wp-admin.old"
    [ -d "${WP_SITE_DIR}/wp-includes.old" ] && rm -rf "${WP_SITE_DIR}/wp-includes.old"
    rm -rf "${WP_SITE_DIR}/wordpress"

    _fn_msg "Done. Please login to your site as admin to upgrade the db."
}

function fn_load_env {
    echo "param1: $1"
}

# --- main ---

function fn_main {
    while :; do
        case "${1:-}" in
            -e | --env ) fn_load_env "${2-}"; shift 2;;

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
