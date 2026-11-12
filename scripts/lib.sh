#!/usr/bin/env bash
# Shared helpers for the npm-auto-build scripts. Sourced, never run on its own.
#
# Rules for every script that sources this file:
#   - inputs arrive only through environment variables, never as interpolated YAML
#   - every expansion is quoted
#   - nothing here reads or prints a token
set -euo pipefail

# Longest accepted value for any single input line (used by validate-inputs.sh).
# shellcheck disable=SC2034
NAB_MAX_VALUE_LENGTH=1024

# Escape a message for a GitHub workflow command, so a value cannot add a line.
nab_escape_command_data() {
    local data=$1
    data=${data//%/%25}
    data=${data//$'\r'/%0D}
    data=${data//$'\n'/%0A}
    printf '%s' "$data"
}

# The "[INFO]" prefix keeps a user value from ever starting a line with "::".
log_info() {
    printf '[INFO] %s\n' "$*"
}

log_warn() {
    printf '::warning::%s\n' "$(nab_escape_command_data "$*")"
}

log_error() {
    printf '::error::%s\n' "$(nab_escape_command_data "$*")"
}

die() {
    log_error "$*"
    exit 1
}

# Lower-case a value (bash 3.2 has no ${var,,}).
nab_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Append KEY=VALUE to the file that GitHub reads between steps. A random delimiter
# keeps a multi-line value safe, and the value is never evaluated by the shell.
nab_write_env() {
    local key=$1 value=$2
    local file=${GITHUB_ENV:-}
    [ -n "$file" ] || die "GITHUB_ENV is not set, so the action cannot pass '$key' to the next step."
    local delimiter="NAB_EOF_${RANDOM}${RANDOM}${RANDOM}"
    while [[ $value == *"$delimiter"* ]]; do
        delimiter="NAB_EOF_${RANDOM}${RANDOM}${RANDOM}"
    done
    {
        printf '%s<<%s\n' "$key" "$delimiter"
        printf '%s\n' "$value"
        printf '%s\n' "$delimiter"
    } >>"$file"
}

# Same for a step output.
nab_write_output() {
    local key=$1 value=$2
    local file=${GITHUB_OUTPUT:-}
    [ -n "$file" ] || die "GITHUB_OUTPUT is not set, so the action cannot write the output '$key'."
    printf '%s=%s\n' "$key" "$value" >>"$file"
}

# Change into the project directory, or fail with a clear message.
nab_enter_workdir() {
    local dir=${NAB_WORKDIR:-.}
    [ -d "$dir" ] || die "working-directory '$dir' does not exist."
    cd -- "$dir"
    [ -f package.json ] || die "package.json not found in working-directory '$dir'."
}

# Pick the package manager: sets NAB_RESOLVED_PM to npm, yarn or pnpm. Run it inside
# the project directory. It sets a variable instead of printing, so that a die is
# not swallowed by $(...). Issue #6 extends this (corepack, yarn berry, packageManager).
# shellcheck disable=SC2034
nab_resolve_package_manager() {
    local requested=${NAB_PACKAGE_MANAGER:-auto}
    case "$requested" in
        npm | yarn | pnpm)
            NAB_RESOLVED_PM=$requested
            ;;
        auto)
            if [ -f package-lock.json ]; then
                NAB_RESOLVED_PM=npm
            elif [ -f yarn.lock ]; then
                NAB_RESOLVED_PM=yarn
            elif [ -f pnpm-lock.yaml ]; then
                NAB_RESOLVED_PM=pnpm
            else
                NAB_RESOLVED_PM=npm
            fi
            ;;
        *)
            die "package-manager '$requested' is not supported. Use auto, npm, yarn or pnpm."
            ;;
    esac
}

# Run a command with the known token variables removed from its environment, even
# when the workflow exported one. This is the guard that keeps the write token away
# from install and build scripts (issue #2). Variables the workflow author sets on
# purpose for a private registry, such as NODE_AUTH_TOKEN, are left alone.
run_without_token() {
    env -u GITHUB_TOKEN -u GH_TOKEN -u INPUT_TOKEN -u INPUT_GITHUB_TOKEN \
        -u ACTIONS_RUNTIME_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_TOKEN \
        "$@"
}
