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

# The package managers the action can drive.
NAB_SUPPORTED_PMS="npm, pnpm and yarn (classic and berry)"

# Leading digits of a version such as "4.1.0" or "9.1.0+sha512.abc": the major version.
# Prints nothing when the value does not start with a number.
nab_major_version() {
    local major=${1%%.*}
    case "$major" in
        '' | *[!0-9]*) ;;
        *) printf '%s' "$major" ;;
    esac
}

# Read the packageManager field of package.json. Sets NAB_FIELD_RAW ("pnpm@9.1.0"),
# NAB_FIELD_NAME ("pnpm") and NAB_FIELD_VERSION ("9.1.0"), all empty when the field is
# absent. Run it inside the project directory.
# shellcheck disable=SC2034
nab_read_package_manager_field() {
    NAB_FIELD_RAW=""
    NAB_FIELD_NAME=""
    NAB_FIELD_VERSION=""
    local raw
    raw=$(node -e '
        let pkg;
        try {
            pkg = JSON.parse(require("fs").readFileSync("package.json", "utf8"));
        } catch (error) {
            process.exit(2);
        }
        const value = pkg.packageManager;
        if (value === undefined) process.exit(0);
        if (typeof value !== "string") process.exit(3);
        process.stdout.write(value);
    ') || die "Could not read the packageManager field: package.json is not valid JSON, or packageManager is not a string."
    [ -n "$raw" ] || return 0
    NAB_FIELD_RAW=$raw
    case "$raw" in
        *@*)
            NAB_FIELD_NAME=${raw%%@*}
            NAB_FIELD_VERSION=${raw#*@}
            ;;
        *) NAB_FIELD_NAME=$raw ;;
    esac
}

# Succeed when the project has a lockfile of the given manager.
nab_has_lockfile() {
    case "$1" in
        npm) [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ] ;;
        yarn) [ -f yarn.lock ] ;;
        pnpm) [ -f pnpm-lock.yaml ] ;;
        *) return 1 ;;
    esac
}

# Pick the package manager: sets NAB_RESOLVED_PM to npm, yarn or pnpm, and NAB_PM_SOURCE
# to input, field, lockfile or default. Run it inside the project directory. It sets
# variables instead of printing, so that a die is not swallowed by $(...). It changes
# nothing and prints nothing, so both the install and the build step can call it.
#
# Order for package-manager: auto
#   1. the packageManager field of package.json
#   2. the lockfile (one manager only: two different lockfiles are an error)
#   3. npm, without a lockfile
# An explicit package-manager input wins over all of it.
# shellcheck disable=SC2034
nab_resolve_package_manager() {
    local requested=${NAB_PACKAGE_MANAGER:-auto}
    NAB_PM_SOURCE=""
    nab_read_package_manager_field

    case "$requested" in
        npm | yarn | pnpm)
            NAB_RESOLVED_PM=$requested
            NAB_PM_SOURCE=input
            return 0
            ;;
        auto) ;;
        *)
            die "package-manager '$requested' is not supported. Use auto, npm, yarn or pnpm."
            ;;
    esac

    if [ -n "$NAB_FIELD_NAME" ]; then
        case "$NAB_FIELD_NAME" in
            npm | yarn | pnpm)
                NAB_RESOLVED_PM=$NAB_FIELD_NAME
                NAB_PM_SOURCE=field
                return 0
                ;;
            *)
                die "The packageManager field of package.json is '$NAB_FIELD_RAW', and '$NAB_FIELD_NAME' is not supported. Supported package managers: $NAB_SUPPORTED_PMS. Set the package-manager input to use another one for the install and the build."
                ;;
        esac
    fi

    local found="" count=0
    if [ -f pnpm-lock.yaml ]; then
        found="pnpm-lock.yaml"
        NAB_RESOLVED_PM=pnpm
        count=$((count + 1))
    fi
    if [ -f yarn.lock ]; then
        found="${found:+$found, }yarn.lock"
        NAB_RESOLVED_PM=yarn
        count=$((count + 1))
    fi
    if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
        [ ! -f package-lock.json ] || found="${found:+$found, }package-lock.json"
        [ ! -f npm-shrinkwrap.json ] || found="${found:+$found, }npm-shrinkwrap.json"
        NAB_RESOLVED_PM=npm
        count=$((count + 1))
    fi

    if [ "$count" -gt 1 ]; then
        die "Found lockfiles of more than one package manager ($found), so the action cannot tell which one to use. Delete the lockfile you do not use, set the packageManager field in package.json, or set the package-manager input."
    fi
    if [ "$count" -eq 1 ]; then
        NAB_PM_SOURCE=lockfile
        return 0
    fi

    if [ -f bun.lock ] || [ -f bun.lockb ]; then
        die "Found a bun lockfile and no other lockfile, and bun is not supported. Supported package managers: $NAB_SUPPORTED_PMS."
    fi
    NAB_RESOLVED_PM=npm
    NAB_PM_SOURCE=default
}

# Make the chosen package manager ready and check that it runs. Only the install step
# calls it. Sets NAB_PM_VERSION. Corepack is used for pnpm and yarn, never npm install -g:
#   - the packageManager field names the chosen manager (pnpm or yarn), or
#   - the chosen manager is pnpm or yarn and its binary is missing.
# Without corepack the manager that is already on PATH is used, with a warning. Without
# corepack and without the binary the step fails.
# npm ships with Node.js, so it never needs corepack here.
# shellcheck disable=SC2034
nab_prepare_package_manager() {
    local pm=$NAB_RESOLVED_PM reason=""

    if [ "$NAB_PM_SOURCE" = "input" ] && [ -n "$NAB_FIELD_NAME" ] && [ "$NAB_FIELD_NAME" != "$pm" ]; then
        log_warn "The package-manager input is '$pm', but package.json says packageManager '$NAB_FIELD_RAW'. The input wins. Corepack may refuse to run '$pm' in this project, and COREPACK_ENABLE_STRICT=0 turns that check off."
    fi

    if [ "$pm" != "npm" ]; then
        if [ "$NAB_FIELD_NAME" = "$pm" ]; then
            reason="the packageManager field is '$NAB_FIELD_RAW'"
        elif ! command -v "$pm" >/dev/null 2>&1; then
            reason="$pm is not installed"
        fi
    fi

    if [ -n "$reason" ]; then
        if command -v corepack >/dev/null 2>&1; then
            log_info "Enabling corepack: $reason"
            run_without_token corepack enable ||
                die "'corepack enable' failed, so $pm was not set up. Install $pm in a step before this action, or set install-command."
        elif command -v "$pm" >/dev/null 2>&1; then
            # For example pnpm/action-setup, or a yarn that the runner image ships.
            log_warn "Corepack is not available ($reason), so the action uses the $pm that is already installed. It may not be the version that package.json asks for."
        else
            die "Corepack is not available on this runner, and $pm is not installed ($reason). Install $pm in a step before this action (for example with pnpm/action-setup for pnpm), use a Node.js version that ships corepack, or set install-command."
        fi
    fi

    command -v "$pm" >/dev/null 2>&1 ||
        die "$pm was not found on PATH. Install $pm in a step before this action, add the packageManager field to package.json so that corepack can provide it, or set install-command."
    local version
    version=$(run_without_token "$pm" --version) ||
        die "'$pm --version' failed, so $pm cannot be used. Install $pm in a step before this action, or set install-command."
    NAB_PM_VERSION=${version%%$'\n'*}
    log_info "Using $pm $NAB_PM_VERSION"
}

# Yarn classic (1.x) or berry (2+): sets NAB_YARN_BERRY to true or false. Call it after
# nab_prepare_package_manager, because it reads the version that yarn reports.
# Order: the packageManager field, a .yarnrc.yml file, a berry lockfile (it has a
# __metadata: line), then the version of the yarn that runs.
# shellcheck disable=SC2034
nab_detect_yarn_berry() {
    NAB_YARN_BERRY=false
    local major=""
    if [ "$NAB_FIELD_NAME" = "yarn" ]; then
        major=$(nab_major_version "$NAB_FIELD_VERSION")
    fi
    if [ -z "$major" ]; then
        if [ -f .yarnrc.yml ]; then
            major=2
        elif [ -f yarn.lock ] && grep -q '^__metadata:' yarn.lock; then
            major=2
        else
            major=$(nab_major_version "${NAB_PM_VERSION:-}")
        fi
    fi
    if [ -n "$major" ] && [ "$major" -ge 2 ]; then
        NAB_YARN_BERRY=true
    fi
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
