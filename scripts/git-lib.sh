#!/usr/bin/env bash
# Git helpers shared by the two modes that push: commit.sh and pr.sh. Sourced, never run
# on its own. It holds the credential handling, so both modes reach the same security bar:
# the token is turned into an Authorization header that only `git fetch`, `git push` and
# `git ls-remote` receive, through GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n
# of that one command. It is never in an argument list, a URL, `.git/config` or a file.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A value, never exported. It holds the Authorization header for the remote commands.
NAB_AUTH_HEADER=""
# An empty directory used as core.hooksPath, so no hook of the repository runs.
NAB_HOOKS_DIR=""
# Set by nab_resolve_repo_path.
NAB_REL_PATH=""
# Set by nab_current_branch.
NAB_BRANCH=""

# Mask a value in the workflow log. The runner removes the command from the log.
nab_mask() {
    printf '::add-mask::%s\n' "$(nab_escape_command_data "$1")"
}

# Git with the hooks of the repository switched off.
nab_git() {
    git -c core.hooksPath="$NAB_HOOKS_DIR" "$@"
}

# Git with the credential for the remote. Used only for fetch and push. The variables are
# exported in a subshell, so they last for this one command and appear in no argument list.
# An existing GIT_CONFIG_COUNT is kept: the header is added after the entries it counts.
nab_git_remote() {
    (
        local count=${GIT_CONFIG_COUNT:-0}
        case "$count" in
            '' | *[!0-9]*) count=0 ;;
        esac
        export "GIT_CONFIG_KEY_$count=http.extraheader"
        export "GIT_CONFIG_VALUE_$count=$NAB_AUTH_HEADER"
        export GIT_CONFIG_COUNT=$((count + 1))
        export GIT_TERMINAL_PROMPT=0
        export GIT_TRACE_REDACT=1
        nab_git -c credential.helper= "$@"
    )
}

# Build the Authorization header for the token into NAB_AUTH_HEADER and mask the token
# and the base64 value. It prints only the two ::add-mask:: commands, never a value. The
# token reaches base64 on standard input, not as an argument.
nab_build_auth_header() {
    local token=$1 encoded
    [ -n "$token" ] || die "The token is empty. Set the 'token' input, for example token: \${{ secrets.GITHUB_TOKEN }}."
    case "$token" in
        *$'\n'* | *$'\r'*) die "The token has a line break, so it cannot be a valid token." ;;
    esac
    # tr removes the line wrapping that some base64 tools add.
    encoded=$(printf '%s' "x-access-token:$token" | base64 | tr -d '\n\r')
    nab_mask "$token"
    nab_mask "$encoded"
    NAB_AUTH_HEADER="AUTHORIZATION: basic $encoded"
}

# GIT_CONFIG_COUNT needs git 2.31 or newer. Older git ignores it and the push would fail
# without a credential, so say it now.
nab_check_git_version() {
    local version major minor
    version=$(git --version | sed -n 's/^git version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
    [ -n "$version" ] || die "Cannot read the git version from '$(git --version)'."
    major=${version% *}
    minor=${version#* }
    if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 31 ]; }; then
        die "git $major.$minor is too old. Modes commit and pr need git 2.31 or newer to pass the credential without putting it in a command line."
    fi
}

# Set NAB_BRANCH to the branch that is checked out, or fail when HEAD is detached. In mode
# pr that branch is the base of the pull request, in mode commit it is the push target.
nab_current_branch() {
    if ! NAB_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || [ -z "$NAB_BRANCH" ]; then
        if [ "${NAB_MODE:-}" = "pr" ]; then
            die "HEAD is detached, so there is no base branch for the pull request. This happens on a tag push and on a pull_request event, where the checkout is a merge commit. Run this workflow on a branch push (on: push: branches), or use 'mode: check' for pull requests."
        fi
        die "HEAD is detached, so there is no branch to push the build output to. This happens on a tag push and on a pull_request event, where the checkout is a merge commit. Use 'mode: check' for pull requests, run this workflow on a branch push (on: push: branches), or use 'mode: pr' to put the build output on a branch of its own."
    fi
    # The checked out branch is the one that is pushed. GITHUB_REF_NAME only explains a
    # surprise, it never picks the branch.
    if [ -n "${GITHUB_REF_NAME:-}" ] && [ "${GITHUB_REF_TYPE:-branch}" = "branch" ] && [ "$GITHUB_REF_NAME" != "$NAB_BRANCH" ]; then
        local what="The build output is pushed to '$NAB_BRANCH'."
        [ "${NAB_MODE:-}" != "pr" ] || what="The pull request is opened against '$NAB_BRANCH'."
        printf '::notice::%s\n' "$(nab_escape_command_data "The workflow ran for '$GITHUB_REF_NAME' but the checked out branch is '$NAB_BRANCH'. $what")"
    fi
}

# A checkout that kept its credentials adds its own Authorization header, and the build
# could read it. Print the key names only, never the values.
nab_warn_persisted_credentials() {
    local keys
    keys=$(git config --local --name-only --get-regexp '^http\..*extraheader$' 2>/dev/null || true)
    if [ -n "$keys" ]; then
        log_warn "The repository config holds credentials from actions/checkout (${keys//$'\n'/, }). Use 'persist-credentials: false' on actions/checkout, so the build cannot read a token from .git/config. The push may fail with two Authorization headers."
    fi
}

# Resolve one `paths` entry (relative to the working directory) against the repository
# root. Sets NAB_REL_PATH, relative to the root, or fails. $1 is the output of
# `git rev-parse --show-prefix` (the working directory inside the repository).
nab_resolve_repo_path() {
    local prefix=$1 entry=$2
    [ -n "$entry" ] || die "A 'paths' entry is empty."
    case "$entry" in
        /* | \\* | [A-Za-z]:*) die "paths entry '$entry' must be relative to working-directory." ;;
    esac

    local -a stack=() parts=()
    local segment base joined
    # read -a splits on "/" without any glob expansion.
    IFS=/ read -r -a parts <<<"$prefix"
    for segment in ${parts[@]+"${parts[@]}"}; do
        [ -n "$segment" ] || continue
        stack[${#stack[@]}]=$segment
    done
    base=${prefix%/}
    parts=()
    IFS=/ read -r -a parts <<<"$entry"
    for segment in ${parts[@]+"${parts[@]}"}; do
        case "$segment" in
            '' | .) ;;
            ..)
                if [ "${#stack[@]}" -eq 0 ]; then
                    die "paths entry '$entry' resolves outside the repository."
                fi
                unset "stack[$((${#stack[@]} - 1))]"
                ;;
            *)
                stack[${#stack[@]}]=$segment
                ;;
        esac
    done

    if [ "${#stack[@]}" -eq 0 ]; then
        die "paths entry '$entry' is the repository root. List the build folder, for example 'dist'."
    fi
    joined=""
    for segment in "${stack[@]}"; do
        joined="${joined:+$joined/}$segment"
    done
    if [ "$joined" = "$base" ]; then
        die "paths entry '$entry' is the working directory itself. List the build folder, for example 'dist', not '.'."
    fi

    NAB_REL_PATH=""
    for segment in "${stack[@]}"; do
        if [ "$(nab_lower "$segment")" = ".git" ]; then
            die "paths entry '$entry' is inside the .git directory. It is never committed."
        fi
        NAB_REL_PATH="${NAB_REL_PATH:+$NAB_REL_PATH/}$segment"
    done
}

# Print git output, one prefixed line each, so a line from a remote can never start a
# workflow command.
nab_print_git_output() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        printf '[git] %s\n' "$line"
    done <<<"$1"
}

# Print a notice when the commit message cannot stop the next workflow run.
nab_notice_skip_ci() {
    local lower
    lower=$(nab_lower "$1")
    case "$lower" in
        *"[skip ci]"* | *"[ci skip]"* | *"[no ci]"* | *"[skip actions]"* | *"[actions skip]"*) return 0 ;;
    esac
    printf '::notice::%s\n' "$(nab_escape_command_data "The commit message has no [skip ci]. A push made with GITHUB_TOKEN does not start workflows, but a push made with a personal access token or a GitHub App token does, so this commit would start the workflow again and could loop. Add [skip ci] to commit-message, or make sure the workflow ignores this commit.")"
}

# Classify the output of a failed push. Prints "protected", "behind" or "other".
nab_classify_push_failure() {
    local output=$1
    if printf '%s' "$output" | grep -Eqi 'GH006|GH013|protected branch|repository rule violations'; then
        printf 'protected'
    elif printf '%s' "$output" | grep -Eqi 'non-fast-forward|fetch first|tip of your current branch is behind|stale info'; then
        printf 'behind'
    else
        printf 'other'
    fi
}
