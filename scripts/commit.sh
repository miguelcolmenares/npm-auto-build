#!/usr/bin/env bash
# Step 5, mode commit only. Stage the build output, commit it with the configured
# author and push it to the current branch.
#
# May do: run git in the repository, read NAB_TOKEN, write GITHUB_OUTPUT. May not: put
# the token on a command line, in a URL, in a git config file, in a file on the runner
# or in the output; force-push; run the project's code.
#
# How the token is used. The script copies NAB_TOKEN into a shell variable and removes it
# from the environment, so no git command sees it by default. Only `git fetch` and
# `git push` get it, as an `http.extraheader` passed through GIT_CONFIG_COUNT,
# GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n. Those variables are exported inside a subshell
# for that one command, so the header is not in the process arguments (`git -c` would
# show it in `ps`), not in `.git/config` and not in `git config --global`. The token and
# its base64 form are masked with `::add-mask::` first. Needs git 2.31 or newer.
#
# What the workflow must do (see docs/testing.md):
#   - `actions/checkout` with `persist-credentials: false`, so the build cannot read a
#     token from `.git/config`
#   - `permissions: contents: write` on the job
#   - a `concurrency` group when several jobs can push to the same branch. The retry
#     below rebases and pushes again, but a group avoids the race and the extra build.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Push attempts before the step gives up.
NAB_PUSH_ATTEMPTS=3
# A value, never exported. It holds the Authorization header for fetch and push.
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
        die "git $major.$minor is too old. Mode commit needs git 2.31 or newer to pass the credential without putting it in a command line."
    fi
}

# Set NAB_BRANCH to the branch that is checked out, or fail when HEAD is detached.
nab_current_branch() {
    if ! NAB_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || [ -z "$NAB_BRANCH" ]; then
        die "HEAD is detached, so there is no branch to push the build output to. This happens on a tag push and on a pull_request event, where the checkout is a merge commit. Use 'mode: check' for pull requests, run this workflow on a branch push (on: push: branches), or use 'mode: pr' once it is available (issue #5)."
    fi
    # The checked out branch is the one that is pushed. GITHUB_REF_NAME only explains a
    # surprise, it never picks the branch.
    if [ -n "${GITHUB_REF_NAME:-}" ] && [ "${GITHUB_REF_TYPE:-branch}" = "branch" ] && [ "$GITHUB_REF_NAME" != "$NAB_BRANCH" ]; then
        printf '::notice::%s\n' "$(nab_escape_command_data "The workflow ran for '$GITHUB_REF_NAME' but the checked out branch is '$NAB_BRANCH'. The build output is pushed to '$NAB_BRANCH'.")"
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
    local segment net=0
    # read -a splits on "/" without any glob expansion.
    IFS=/ read -r -a parts <<<"$prefix"
    for segment in ${parts[@]+"${parts[@]}"}; do
        [ -n "$segment" ] || continue
        stack[${#stack[@]}]=$segment
    done
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
                net=$((net - 1))
                ;;
            *)
                stack[${#stack[@]}]=$segment
                net=$((net + 1))
                ;;
        esac
    done

    if [ "$net" -eq 0 ]; then
        die "paths entry '$entry' is the working directory itself. List the build folder, for example 'dist', not '.'."
    fi
    if [ "${#stack[@]}" -eq 0 ]; then
        die "paths entry '$entry' is the repository root. List the build folder, for example 'dist'."
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

# Move the one local commit on top of the remote branch. On a conflict, abort and fail.
# Sets NAB_REBASE_EMPTY to "true" when the remote already holds the same output.
nab_rebase_onto_remote() {
    local branch=$1 name=$2 email=$3 output
    NAB_REBASE_EMPTY=false
    if ! output=$(nab_git_remote fetch --quiet --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>&1); then
        nab_print_git_output "$output"
        die "git fetch of '$branch' failed, so the build commit cannot be moved onto the new remote commits."
    fi
    # --onto with HEAD~1 moves only our commit, so a shallow checkout works too.
    if ! output=$(nab_git -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
        rebase --autostash --onto "refs/remotes/origin/$branch" HEAD~1 2>&1); then
        nab_print_git_output "$output"
        nab_git rebase --abort >/dev/null 2>&1 || true
        die "The branch '$branch' changed while the build ran and the build commit conflicts with the new commits. The rebase was aborted and nothing was pushed. Run the workflow again, and use a concurrency group so runs on the same branch go one at a time."
    fi
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse "refs/remotes/origin/$branch")" ]; then
        NAB_REBASE_EMPTY=true
    fi
}

# Push HEAD to the branch. Up to NAB_PUSH_ATTEMPTS attempts, never a force-push. Sets
# NAB_PUSHED to "true" when a commit was pushed, "false" when the remote already had it.
nab_push_with_retry() {
    local branch=$1 name=$2 email=$3
    local attempt=1 output kind
    NAB_PUSHED=true
    while :; do
        if output=$(nab_git_remote push --no-verify origin "HEAD:refs/heads/$branch" 2>&1); then
            nab_print_git_output "$output"
            return 0
        fi
        kind=$(nab_classify_push_failure "$output")
        case "$kind" in
            protected)
                nab_print_git_output "$output"
                die "The push to '$branch' was rejected because the branch is protected. Two options work: give the 'token' input a personal access token or a GitHub App token that may bypass the protection, or use 'mode: pr' (issue #5) to put the build output on its own branch. The action never force-pushes."
                ;;
            behind)
                if [ "$attempt" -ge "$NAB_PUSH_ATTEMPTS" ]; then
                    nab_print_git_output "$output"
                    die "The push to '$branch' was still rejected after $NAB_PUSH_ATTEMPTS attempts, other runs keep pushing to it. Use a concurrency group so runs on the same branch go one at a time."
                fi
                log_info "The push was rejected because '$branch' moved (attempt $attempt of $NAB_PUSH_ATTEMPTS). Rebasing onto it and trying again."
                nab_rebase_onto_remote "$branch" "$name" "$email"
                if [ "$NAB_REBASE_EMPTY" = "true" ]; then
                    log_info "The remote branch already holds the same build output, nothing is left to push."
                    NAB_PUSHED=false
                    return 0
                fi
                attempt=$((attempt + 1))
                ;;
            *)
                nab_print_git_output "$output"
                if printf '%s' "$output" | grep -Eqi 'permission to .* denied|403|authentication failed|could not read username|invalid credentials'; then
                    die "The push to '$branch' was refused. Check that the job has 'permissions: contents: write' and that the 'token' input is valid. Set 'persist-credentials: false' on actions/checkout."
                fi
                die "git push to '$branch' failed."
                ;;
        esac
    done
}

main() {
    [ "${NAB_MODE:-}" = "commit" ] || die "commit.sh runs only in mode commit, the mode is '${NAB_MODE:-}'."

    # Take the token out of the environment first. From here on only nab_git_remote
    # gives git a credential.
    local token=${NAB_TOKEN:-}
    unset NAB_TOKEN
    local paths=${NAB_PATHS:-}
    local message=${NAB_COMMIT_MESSAGE-}
    local name=${NAB_GIT_USER_NAME-}
    local email=${NAB_GIT_USER_EMAIL-}
    [ -n "$paths" ] || die "NAB_PATHS is empty, run validate-inputs.sh first."
    [ -n "$message" ] || die "Input 'commit-message' is empty."
    [ -n "$name" ] || die "Input 'git-user-name' is empty."
    [ -n "$email" ] || die "Input 'git-user-email' is empty."

    # The commit author comes from the inputs only, never from the environment.
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE \
        GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE

    nab_enter_workdir
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "working-directory '${NAB_WORKDIR:-.}' is not inside a git repository. Run actions/checkout before this action."
    nab_check_git_version
    nab_current_branch
    nab_warn_persisted_credentials
    nab_build_auth_header "$token"
    token=""

    NAB_HOOKS_DIR=$(mktemp -d)
    trap 'rm -rf "$NAB_HOOKS_DIR"' EXIT

    # Resolve every path before staging any, so a refused path leaves the index alone.
    local root prefix entry rels=""
    root=$(git rev-parse --show-toplevel)
    prefix=$(git rev-parse --show-prefix)
    while IFS= read -r entry; do
        nab_resolve_repo_path "$prefix" "$entry"
        rels="${rels}${NAB_REL_PATH}"$'\n'
    done <<<"$paths"
    rels=${rels%$'\n'}

    if ! git diff --cached --quiet; then
        die "The index already has staged changes. The action commits only the 'paths', so it will not add them to the build commit. Unstage them before this action runs."
    fi

    # --force: the build folder is usually in .gitignore, which is the point of the action.
    # --literal-pathspecs: a file name is never read as a glob or a pathspec magic.
    while IFS= read -r entry; do
        nab_git -C "$root" --literal-pathspecs add --force -- "$entry" ||
            die "git add failed for '$entry'."
    done <<<"$rels"

    if git diff --cached --quiet; then
        log_info "The build output is the same as in the repository, nothing to commit."
        nab_write_output changed false
        return 0
    fi

    nab_notice_skip_ci "$message"
    nab_git -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
        commit --no-verify --quiet -m "$message" ||
        die "git commit failed."
    log_info "Committed the build output on '$NAB_BRANCH'."

    nab_push_with_retry "$NAB_BRANCH" "$name" "$email"
    if [ "$NAB_PUSHED" = "true" ]; then
        local sha
        sha=$(git rev-parse HEAD)
        log_info "Pushed $sha to '$NAB_BRANCH'."
        nab_write_output changed true
        nab_write_output commit-sha "$sha"
    else
        nab_write_output changed false
    fi
}

# Run only when executed, so the tests can source this file and call its functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main
fi
