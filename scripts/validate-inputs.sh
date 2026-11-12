#!/usr/bin/env bash
# Step 1. Map the v2 alias inputs, gate the mode, validate and normalize every input,
# and pass the clean values to the next steps as NAB_* variables in GITHUB_ENV.
#
# May do: read INPUT_* variables, write GITHUB_ENV and GITHUB_OUTPUT, print workflow
# commands. May not: read the token value, run the project's code, touch the network.
#
# The token inputs are never passed to this step. Only INPUT_GITHUB_TOKEN_SET
# ("true" or "false") tells it that the v2 alias was used.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Mode gate: which issue implements each mode that is not available yet.
mode_issue() {
    case "$1" in
        pr) printf '5' ;;
        *) printf '' ;;
    esac
}

# Functions below that return a value set a variable instead of printing it. A die
# inside $(...) would lose its error message, because the substitution captures it.

# A boolean input: sets BOOL_VALUE to "true" or "false", or fails.
parse_bool() {
    local name=$1 value
    value=$(nab_lower "$2")
    case "$value" in
        true | false) BOOL_VALUE=$value ;;
        *) die "Input '$name' must be 'true' or 'false', got '$2'." ;;
    esac
}

# Reject a value with a newline or a carriage return, or one that is too long.
check_single_line() {
    local name=$1 value=$2
    case "$value" in
        *$'\n'* | *$'\r'*) die "Input '$name' must be a single line, it contains a line break." ;;
    esac
    if [ "${#value}" -gt "$NAB_MAX_VALUE_LENGTH" ]; then
        die "Input '$name' is too long (${#value} characters, the limit is $NAB_MAX_VALUE_LENGTH)."
    fi
}

# A relative path that stays inside the workspace: not absolute, no "..".
check_relative_path() {
    local name=$1 value=$2
    case "$value" in
        /* | \\* | [A-Za-z]:*) die "$name '$value' must be a relative path, not an absolute one." ;;
    esac
    case "$value" in
        *..*) die "$name '$value' must not contain '..', it would leave the workspace." ;;
    esac
}

# Trim spaces and tabs at both ends of a value.
trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

# Validate the newline list of output paths. Sets PATHS_VALUE, one entry per line.
normalize_paths() {
    local raw=$1 line entry out="" count=0 max_entries=50
    # Drop carriage returns from CRLF values, then walk the lines.
    raw=${raw//$'\r'/}
    # Blank lines at the end are allowed (a YAML block scalar ends with a newline).
    while [[ $raw == *$'\n' ]]; do
        raw=${raw%$'\n'}
    done
    [ -n "$(trim "$raw")" ] || die "Input 'paths' is empty. List at least one path, for example 'dist'."

    while IFS= read -r line || [ -n "$line" ]; do
        entry=$(trim "$line")
        [ -n "$entry" ] || die "Input 'paths' has an empty entry. Remove blank lines between paths."
        if [ "${#entry}" -gt "$NAB_MAX_VALUE_LENGTH" ]; then
            die "A 'paths' entry is too long (${#entry} characters, the limit is $NAB_MAX_VALUE_LENGTH)."
        fi
        case "$entry" in
            -*) die "paths entry '$entry' must not start with '-', it could be read as an option." ;;
        esac
        check_relative_path "paths entry" "$entry"
        count=$((count + 1))
        if [ "$count" -gt "$max_entries" ]; then
            die "Input 'paths' has more than $max_entries entries."
        fi
        out="${out}${entry}"$'\n'
    done <<<"$raw"
    PATHS_VALUE=${out%$'\n'}
}

main() {
    local mode=${INPUT_MODE:-commit}
    local workdir=${INPUT_WORKING_DIRECTORY:-.}
    local command=${INPUT_COMMAND-build}
    local install_command=${INPUT_INSTALL_COMMAND:-}
    local package_manager=${INPUT_PACKAGE_MANAGER:-auto}
    local node_version=${INPUT_NODE_VERSION:-24}
    local node_version_file=${INPUT_NODE_VERSION_FILE:-}
    local registry_url=${INPUT_REGISTRY_URL:-}
    local scope=${INPUT_SCOPE:-}
    local paths=${INPUT_PATHS-dist}
    local ignore_scripts=${INPUT_IGNORE_SCRIPTS:-false}
    local upload_diff=${INPUT_UPLOAD_DIFF:-true}
    local auto_merge=${INPUT_AUTO_MERGE:-false}

    # v2 aliases. A v3 input that was moved away from its default wins over the alias.
    if [ -n "${INPUT_BUILD_ONLY:-}" ]; then
        log_warn "Input 'build-only' is a v2 name. Use 'mode: build' instead."
        parse_bool build-only "$INPUT_BUILD_ONLY"
        if [ "$BOOL_VALUE" = "true" ]; then
            if [ "$mode" = "commit" ]; then
                mode='build'
            else
                log_warn "Input 'build-only' is ignored because 'mode' is already '$mode'."
            fi
        fi
    fi
    if [ -n "${INPUT_CREATE_PR:-}" ]; then
        log_warn "Input 'create-pr' is a v2 name. Use 'mode: pr' instead."
        parse_bool create-pr "$INPUT_CREATE_PR"
        if [ "$BOOL_VALUE" = "true" ]; then
            if [ "$mode" = "commit" ]; then
                mode='pr'
            else
                log_warn "Input 'create-pr' is ignored because 'mode' is already '$mode'."
            fi
        fi
    fi
    if [ -n "${INPUT_DIRECTORY:-}" ]; then
        log_warn "Input 'directory' is a v2 name. Use 'working-directory' instead."
        if [ "$workdir" = "." ]; then
            workdir=$INPUT_DIRECTORY
        elif [ "$workdir" != "$INPUT_DIRECTORY" ]; then
            log_warn "Input 'directory' is ignored because 'working-directory' is already set."
        fi
    fi
    if [ -n "${INPUT_BUILD_DIR:-}" ]; then
        log_warn "Input 'build-dir' is a v2 name. Use 'paths' instead."
        if [ "$paths" = "dist" ]; then
            paths=$INPUT_BUILD_DIR
        elif [ "$paths" != "$INPUT_BUILD_DIR" ]; then
            log_warn "Input 'build-dir' is ignored because 'paths' is already set."
        fi
    fi
    if [ "${INPUT_GITHUB_TOKEN_SET:-false}" = "true" ]; then
        log_warn "Input 'github-token' is a v2 name. Use 'token' instead. Its value still works: it is the token of the commit step and wins over 'token'."
    fi

    # Mode gate. Build, check and commit work on this branch of the rewrite.
    case "$mode" in
        build | check | commit) ;;
        pr)
            die "mode '$mode' is implemented by issue #$(mode_issue "$mode") and is not available yet. Use 'mode: commit', 'mode: check' or 'mode: build' for now, or pin the action to the v2 tag."
            ;;
        *)
            die "Unknown mode '$mode'. Use one of: commit, check, pr, build (pr is not available yet)."
            ;;
    esac

    # Single line text inputs, checked even when build mode does not use them yet.
    local name value
    for name in INPUT_GIT_USER_NAME INPUT_GIT_USER_EMAIL INPUT_BRANCH INPUT_PR_TITLE \
        INPUT_PR_LABELS INPUT_COMMIT_MESSAGE; do
        value=${!name:-}
        check_single_line "${name#INPUT_}" "$value"
    done

    check_single_line working-directory "$workdir"
    check_single_line command "$command"
    check_single_line install-command "$install_command"
    check_single_line package-manager "$package_manager"
    check_single_line node-version "$node_version"
    check_single_line node-version-file "$node_version_file"
    check_single_line registry-url "$registry_url"
    check_single_line scope "$scope"

    # registry-url and scope go to actions/setup-node, which writes them to an .npmrc.
    # Neither is a secret, so a URL with credentials in it is refused.
    if [ -n "$registry_url" ]; then
        case "$registry_url" in
            http://* | https://*) ;;
            *) die "registry-url '$registry_url' must start with http:// or https://." ;;
        esac
        # The part before the first "/" is the host. A "@" there means user:password@host.
        local rest=${registry_url#*://}
        case "${rest%%/*}" in
            *@*) die "registry-url must not contain credentials. Set NODE_AUTH_TOKEN in the env: of the job and let the .npmrc read it." ;;
        esac
    fi
    if [ -n "$scope" ] && ! [[ $scope =~ ^@?[a-z0-9][a-z0-9._~-]*$ ]]; then
        die "scope '$scope' is not a valid npm scope, for example @my-org."
    fi

    [ -n "$workdir" ] || workdir=.
    check_relative_path working-directory "$workdir"

    [ -n "$command" ] || die "Input 'command' is empty."
    case "$command" in
        -*) die "command '$command' must not start with '-', it could be read as an option." ;;
    esac

    case "$package_manager" in
        auto | npm | yarn | pnpm) ;;
        *) die "package-manager '$package_manager' is not supported. Use auto, npm, yarn or pnpm." ;;
    esac

    if [ -n "$node_version_file" ]; then
        check_relative_path node-version-file "$node_version_file"
        # setup-node ignores the file when node-version is set, so the file wins here.
        node_version=""
    elif ! [[ $node_version =~ ^[A-Za-z0-9._*^~\<\>=\|/-]+$ ]]; then
        die "node-version '$node_version' has characters that are not allowed in a version."
    fi

    parse_bool ignore-scripts "$ignore_scripts"
    ignore_scripts=$BOOL_VALUE
    parse_bool upload-diff "$upload_diff"
    parse_bool auto-merge "$auto_merge"
    if [ "$ignore_scripts" = "true" ] && [ -n "$install_command" ]; then
        log_warn "Input 'ignore-scripts' has no effect when 'install-command' is set. Add the flag to your own command."
    fi

    normalize_paths "$paths"
    paths=$PATHS_VALUE

    nab_write_env NAB_MODE "$mode"
    nab_write_env NAB_WORKDIR "$workdir"
    nab_write_env NAB_COMMAND "$command"
    nab_write_env NAB_INSTALL_COMMAND "$install_command"
    nab_write_env NAB_PACKAGE_MANAGER "$package_manager"
    nab_write_env NAB_PATHS "$paths"
    nab_write_env NAB_IGNORE_SCRIPTS "$ignore_scripts"
    nab_write_output node-version "$node_version"
    # The commit step reads this output in its `if:`, a composite step cannot use GITHUB_ENV there.
    nab_write_output mode "$mode"

    log_info "mode: $mode"
    log_info "working-directory: $workdir"
    log_info "command: $command"
    log_info "package-manager: $package_manager"
}

main
