#!/usr/bin/env bash
# Step 5, mode pr only. Put the build output on a branch of its own and keep one pull
# request up to date against the branch that is checked out (the base).
#
# May do: run git in the repository, run `gh`, read NAB_TOKEN, write GITHUB_OUTPUT. May
# not: put the token on a command line, in a URL, in a git config file, in a file on the
# runner or in the output; write to the base branch, to a protected branch or to a branch
# that this action did not make; force-push without a lease; run the project's code.
#
# How the token is used. It follows the rules of commit.sh. The script copies NAB_TOKEN into
# a shell variable and removes it from the environment. Only `git fetch`, `git ls-remote`
# and `git push` get it, as an `http.extraheader` in the GIT_CONFIG_* variables of that one
# command (nab_git_remote in git-lib.sh). Only `gh` gets it as GH_TOKEN, set inside a
# subshell for that one command (nab_gh below), so it is in no argument list, no file and
# no output.
#
# What the script does:
#   1. Stages the `paths` and builds ONE commit with `git commit-tree` on top of the base.
#      The base branch and the working tree are not moved. No difference from the base
#      means no push and no pull request.
#   2. Pushes that commit to the bot branch with `--force-with-lease=<ref>:<sha it saw>`.
#      The destination is always `refs/heads/<branch>`. The branch must not be the base,
#      the default branch of the remote, or a reserved name (main, master, release/*, ...),
#      and when it exists its tip must carry the marker line that this script writes. A
#      branch that someone else made is never overwritten.
#   3. Opens the pull request, or updates the title and the labels of the open one, with
#      `gh`. A second run finds the open pull request of the branch, it never opens another.
#   4. With auto-merge, runs `gh pr merge --auto`.
#
# What the workflow must do (see docs/testing.md): `actions/checkout` with
# `persist-credentials: false`, `permissions: contents: write` and `pull-requests: write`,
# the repository setting "Allow GitHub Actions to create and approve pull requests" (or a
# personal access token or a GitHub App token as `token`), and a `concurrency` group.
set -euo pipefail

# shellcheck source=git-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/git-lib.sh"

# Push attempts before the step gives up.
NAB_PUSH_ATTEMPTS=3
# The line that marks a commit as made by this script. It is how the script recognises its
# own branch before it overwrites it.
NAB_PR_MARKER="Generated-by: npm-auto-build"
# The default commit message of the action has [skip ci], and GitHub would skip the checks
# of the pull request for it. In mode pr that exact default is used without the marker.
NAB_DEFAULT_COMMIT_MESSAGE="chore: update build output [skip ci]"
NAB_PR_COMMIT_MESSAGE="chore: update build output"
NAB_DEFAULT_PR_TITLE="chore: update build output"
# The token, as a shell variable that is never exported. Only nab_gh uses it.
NAB_GH_TOKEN=""
# A directory for the stderr of gh, and the result of the last gh call.
NAB_WORK_DIR=""
NAB_GH_OUT=""
NAB_GH_ERR=""
# Set by nab_split_labels, nab_pr_sync.
NAB_LABELS=()
NAB_PR_URL=""
NAB_PR_NUMBER=""
# Set by nab_pr_inspect_remote.
NAB_REMOTE_SHA=""
# Set by nab_pr_push.
NAB_PUSHED=false

# gh with the token, for one command. The variables are exported in a subshell, so they
# last for this call only and are in no argument list.
nab_gh() {
    (
        export GH_TOKEN=$NAB_GH_TOKEN
        export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1
        gh "$@"
    )
}

# Run gh and keep its output apart: stdout in NAB_GH_OUT (the part the script parses) and
# stderr in NAB_GH_ERR. Returns the exit status of gh.
nab_gh_run() {
    local status=0
    NAB_GH_OUT=$(nab_gh "$@" 2>"$NAB_WORK_DIR/gh.err") || status=$?
    NAB_GH_ERR=$(cat "$NAB_WORK_DIR/gh.err")
    return "$status"
}

# Print what gh said, one prefixed line each, so a line of it never starts a workflow command.
nab_print_gh_output() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] || printf '[gh] %s\n' "$line"
    done <<<"$NAB_GH_OUT"$'\n'"$NAB_GH_ERR"
}

# A hint for the failures that people meet most often.
nab_gh_hint() {
    local text
    text=$(printf '%s\n%s' "$NAB_GH_OUT" "$NAB_GH_ERR")
    if printf '%s' "$text" | grep -Eqi 'not permitted to create or approve pull requests'; then
        printf ' Turn on "Allow GitHub Actions to create and approve pull requests" in the repository settings (Actions, General), or give the token input a personal access token or a GitHub App token.'
    elif printf '%s' "$text" | grep -Eqi 'resource not accessible by integration|http 403'; then
        printf ' Check that the job has permissions contents: write and pull-requests: write, and that the token input is valid.'
    elif printf '%s' "$text" | grep -Eqi 'auto.?merge is not allowed|enablePullRequestAutoMerge|protected branch rules not configured'; then
        printf ' Auto-merge needs "Allow auto-merge" in the repository settings and a branch protection rule or ruleset with required checks on the base branch.'
    elif printf '%s' "$text" | grep -Eqi 'label.*not found|could not add label'; then
        printf ' Create the label in the repository first, gh does not create labels.'
    fi
}

# Stop with a message and the output of the failed gh call.
nab_gh_fail() {
    local message=$1
    nab_print_gh_output
    die "$message$(nab_gh_hint)"
}

# Split the comma separated pr-labels into the array NAB_LABELS (no empty entry).
nab_split_labels() {
    NAB_LABELS=()
    local labels=${1:-} label
    [ -n "$labels" ] || return 0
    local -a parts=()
    IFS=, read -r -a parts <<<"$labels"
    for label in "${parts[@]}"; do
        [ -n "$label" ] || continue
        NAB_LABELS[${#NAB_LABELS[@]}]=$label
    done
}

# Look at the remote before anything is written. Sets NAB_REMOTE_SHA to the tip of the bot
# branch on the remote, empty when the branch does not exist. Fails when the branch is the
# default branch of the remote, or when it exists and was not made by this script. One
# ls-remote call gives both the default branch (the HEAD symref) and the tip of the branch.
nab_pr_inspect_remote() {
    local branch=$1 output line sha ref default="" tip=""
    if ! output=$(nab_git_remote ls-remote --symref origin HEAD "refs/heads/$branch" 2>&1); then
        nab_print_git_output "$output"
        die "git ls-remote failed, so the action cannot look at the branch '$branch' on the remote. Check that the 'token' input is valid and that actions/checkout ran first."
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "ref: refs/heads/"*$'\t'HEAD)
                default=${line#ref: refs/heads/}
                default=${default%$'\t'HEAD}
                ;;
            *$'\t'"refs/heads/$branch")
                sha=${line%%$'\t'*}
                ref=${line#*$'\t'}
                if [ "$ref" = "refs/heads/$branch" ] && [[ $sha =~ ^[0-9a-f]{40,64}$ ]]; then
                    tip=$sha
                fi
                ;;
        esac
    done <<<"$output"

    if [ -n "$default" ] && [ "$(nab_lower "$default")" = "$(nab_lower "$branch")" ]; then
        die "branch '$branch' is the default branch of the remote. Mode pr force-pushes its branch on every run and never writes to the default branch. Use another name, or leave 'branch' empty."
    fi

    NAB_REMOTE_SHA=""
    [ -n "$tip" ] || return 0

    # The branch exists. Read its tip commit, and refuse it unless this script made it.
    if ! output=$(nab_git_remote fetch --quiet --no-tags origin "refs/heads/$branch" 2>&1); then
        nab_print_git_output "$output"
        die "git fetch of '$branch' failed, so the action cannot check who made the branch."
    fi
    tip=$(git rev-parse --verify --quiet "FETCH_HEAD^{commit}") ||
        die "The remote branch '$branch' could not be read after the fetch."
    local message
    message=$(git log -1 --format=%B "$tip")
    if ! printf '%s\n' "$message" | grep -qxF "$NAB_PR_MARKER"; then
        die "The branch '$branch' exists on the remote and was not made by this action (its tip commit has no '$NAB_PR_MARKER' line). The action force-pushes this branch, so it will not overwrite it. Delete the branch, or set 'branch' to a name that is free."
    fi
    NAB_REMOTE_SHA=$tip
}

# Push the commit to the bot branch with a lease on the tip that nab_pr_inspect_remote saw.
# The lease makes git refuse the push when someone moved the branch in between. An empty
# lease value means the branch must not exist yet. Sets NAB_PUSHED to "true" when a push
# happened, "false" when the remote branch already holds this exact commit tree on this base.
nab_pr_push() {
    local branch=$1 commit=$2 base_sha=$3 tree=$4
    local attempt=1 output kind
    NAB_PUSHED=true
    while :; do
        nab_pr_inspect_remote "$branch"
        if [ -n "$NAB_REMOTE_SHA" ] &&
            [ "$(git rev-parse "$NAB_REMOTE_SHA^{tree}")" = "$tree" ] &&
            [ "$(git rev-parse --quiet --verify "$NAB_REMOTE_SHA^" || true)" = "$base_sha" ]; then
            log_info "The branch '$branch' already holds this build output on the current base, nothing to push."
            NAB_PUSHED=false
            return 0
        fi
        if output=$(nab_git_remote push --no-verify "--force-with-lease=refs/heads/$branch:$NAB_REMOTE_SHA" origin "$commit:refs/heads/$branch" 2>&1); then
            nab_print_git_output "$output"
            return 0
        fi
        kind=$(nab_classify_push_failure "$output")
        case "$kind" in
            protected)
                nab_print_git_output "$output"
                die "The push to '$branch' was rejected because the branch is protected. The branch of mode pr is rewritten on every run, so it cannot have a protection rule that blocks force-pushes. Exclude '$branch' from the branch protection rules and rulesets, or use another name in 'branch'."
                ;;
            behind)
                if [ "$attempt" -ge "$NAB_PUSH_ATTEMPTS" ]; then
                    nab_print_git_output "$output"
                    die "The push to '$branch' was still rejected after $NAB_PUSH_ATTEMPTS attempts, someone keeps pushing to it. Use a concurrency group so runs of this workflow go one at a time."
                fi
                log_info "The push was rejected because '$branch' moved (attempt $attempt of $NAB_PUSH_ATTEMPTS). Looking at it again."
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

# The text of the pull request when it is opened. The backticks are Markdown code marks.
nab_pr_body() {
    local base=$1 branch=$2 base_sha=$3 t='`'
    printf 'Build output of %s%s%s, made by npm-auto-build.\n\n' "$t" "$base" "$t"
    printf 'The branch %s%s%s belongs to the action. It is rebuilt and force-pushed on every run, so do not push your own commits to it.\n\n' "$t" "$branch" "$t"
    printf 'Built on top of %s%s%s.\n' "$t" "$base_sha" "$t"
}

# Open the pull request, or update the open one. Sets NAB_PR_URL and NAB_PR_NUMBER.
nab_pr_sync() {
    local repo=$1 base=$2 branch=$3 title=$4 labels=$5 base_sha=$6
    NAB_PR_URL=""
    NAB_PR_NUMBER=""
    command -v gh >/dev/null 2>&1 ||
        die "The GitHub CLI (gh) was not found on PATH. GitHub-hosted runners have it. On a self-hosted runner, install it first."
    [[ $repo =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] ||
        die "GITHUB_REPOSITORY is '$repo', expected owner/name. Mode pr runs in a GitHub Actions job."

    nab_split_labels "$labels"

    if ! nab_gh_run pr list "--repo=$repo" "--head=$branch" "--base=$base" --state=open --limit=1 \
        --json=number,url --jq='.[0] | select(. != null) | "\(.number) \(.url)"'; then
        nab_gh_fail "gh could not look for an open pull request from '$branch'."
    fi
    local found=$NAB_GH_OUT
    found=${found%%$'\n'*}

    if [ -n "$found" ]; then
        local number=${found%% *} url=${found#* }
        [[ $number =~ ^[0-9]+$ ]] || die "gh answered '$number' where a pull request number was expected."
        [[ $url == https://* || $url == http://* ]] || die "gh answered '$url' where a pull request URL was expected."
        log_info "Updating the open pull request #$number."
        local -a edit=(pr edit "$number" "--repo=$repo" "--title=$title")
        local label
        for label in ${NAB_LABELS[@]+"${NAB_LABELS[@]}"}; do
            edit[${#edit[@]}]="--add-label=$label"
        done
        nab_gh_run "${edit[@]}" || nab_gh_fail "gh could not update the pull request #$number."
        NAB_PR_NUMBER=$number
        NAB_PR_URL=$url
    else
        log_info "Opening a pull request from '$branch' to '$base'."
        local -a create=(pr create "--repo=$repo" "--base=$base" "--head=$branch" "--title=$title" "--body=$(nab_pr_body "$base" "$branch" "$base_sha")")
        local label
        for label in ${NAB_LABELS[@]+"${NAB_LABELS[@]}"}; do
            create[${#create[@]}]="--label=$label"
        done
        nab_gh_run "${create[@]}" || nab_gh_fail "gh could not open the pull request from '$branch' to '$base'."
        local url=${NAB_GH_OUT##*$'\n'}
        [[ $url =~ ^https?://.*/pull/([0-9]+)$ ]] ||
            die "gh did not print the URL of the new pull request."
        NAB_PR_NUMBER=${BASH_REMATCH[1]}
        NAB_PR_URL=$url
    fi
    log_info "Pull request #$NAB_PR_NUMBER: $NAB_PR_URL"
}

# Enable auto-merge on the pull request. gh asks for a merge method when it is not run in a
# terminal, so the script picks the first one that the repository allows.
nab_pr_auto_merge() {
    local repo=$1 number=$2 method
    nab_gh_run repo view "$repo" --json=squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed \
        --jq='if .squashMergeAllowed then "squash" elif .mergeCommitAllowed then "merge" elif .rebaseMergeAllowed then "rebase" else "" end' ||
        nab_gh_fail "gh could not read the merge settings of the repository."
    method=${NAB_GH_OUT%%$'\n'*}
    case "$method" in
        squash | merge | rebase) ;;
        *) die "The repository allows no merge method, so auto-merge cannot be enabled on the pull request #$number." ;;
    esac
    nab_gh_run pr merge "$number" "--repo=$repo" --auto "--$method" ||
        nab_gh_fail "gh could not enable auto-merge on the pull request #$number. The pull request is open."
    log_info "Auto-merge is enabled on the pull request #$number ($method)."
}

main() {
    [ "${NAB_MODE:-}" = "pr" ] || die "pr.sh runs only in mode pr, the mode is '${NAB_MODE:-}'."

    # Take the token out of the environment first. From here on only nab_git_remote and
    # nab_gh give a command a credential.
    local token=${NAB_TOKEN:-}
    unset NAB_TOKEN
    local paths=${NAB_PATHS:-}
    local message=${NAB_COMMIT_MESSAGE-}
    local name=${NAB_GIT_USER_NAME-}
    local email=${NAB_GIT_USER_EMAIL-}
    local title=${NAB_PR_TITLE:-$NAB_DEFAULT_PR_TITLE}
    local labels=${NAB_PR_LABELS:-}
    local auto_merge=${NAB_AUTO_MERGE:-false}
    local branch=${NAB_PR_BRANCH:-}
    [ -n "$paths" ] || die "NAB_PATHS is empty, run validate-inputs.sh first."
    [ -n "$message" ] || die "Input 'commit-message' is empty."
    [ -n "$name" ] || die "Input 'git-user-name' is empty."
    [ -n "$email" ] || die "Input 'git-user-email' is empty."
    case "$auto_merge" in
        true | false) ;;
        *) die "NAB_AUTO_MERGE is '$auto_merge', run validate-inputs.sh first." ;;
    esac

    # The commit author comes from the inputs only, never from the environment.
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE \
        GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE

    nab_enter_workdir
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "working-directory '${NAB_WORKDIR:-.}' is not inside a git repository. Run actions/checkout before this action."
    nab_check_git_version
    nab_current_branch
    local base=$NAB_BRANCH

    # The branch of the pull request. Every check that can stop the run comes before the
    # token is used and before anything is staged.
    case "$(nab_lower "$base")" in
        auto-build/*)
            die "The checked out branch '$base' looks like a branch of this action, so a pull request from a branch made from it would loop. Run the workflow on the branch that receives the pull request (on: push: branches: [main])."
            ;;
    esac
    [ -n "$branch" ] || branch="auto-build/$base"
    nab_check_pr_branch_name "$branch"
    if [ "$(nab_lower "$branch")" = "$(nab_lower "$base")" ]; then
        die "branch '$branch' is the base branch of the pull request. Mode pr force-pushes its branch on every run and never writes to the base branch. Leave 'branch' empty, or use another name."
    fi
    if [ "$message" = "$NAB_DEFAULT_COMMIT_MESSAGE" ]; then
        message=$NAB_PR_COMMIT_MESSAGE
    else
        case "$(nab_lower "$message")" in
            *"[skip ci]"* | *"[ci skip]"* | *"[no ci]"* | *"[skip actions]"* | *"[actions skip]"*)
                printf '::notice::%s\n' "$(nab_escape_command_data "The commit message has a skip marker. GitHub skips the workflows of a pull request whose head commit has one, so required checks would never run on it. Remove the marker from commit-message in mode pr.")"
                ;;
        esac
    fi

    nab_warn_persisted_credentials
    nab_build_auth_header "$token"
    NAB_GH_TOKEN=$token
    token=""

    NAB_HOOKS_DIR=$(mktemp -d)
    NAB_WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$NAB_HOOKS_DIR" "$NAB_WORK_DIR"' EXIT

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
        log_info "The build output is the same as on '$base', no branch to push and no pull request to open."
        return 0
    fi

    # The commit is made with plumbing, so the checked out branch and the working tree stay
    # where they are. The index goes back to HEAD, as it was before the step.
    local base_sha tree commit
    base_sha=$(git rev-parse HEAD)
    tree=$(git write-tree)
    commit=$(nab_git -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
        commit-tree "$tree" -p "$base_sha" -m "$message" -m "$NAB_PR_MARKER") ||
        die "git commit-tree failed."
    nab_git reset --quiet
    log_info "Made the build commit $commit on top of '$base' ($base_sha)."

    nab_pr_push "$branch" "$commit" "$base_sha" "$tree"
    if [ "$NAB_PUSHED" = "true" ]; then
        log_info "Pushed $commit to '$branch'."
    fi

    nab_pr_sync "${GITHUB_REPOSITORY:-}" "$base" "$branch" "$title" "$labels" "$base_sha"
    nab_write_output pull-request-url "$NAB_PR_URL"
    nab_write_output pull-request-number "$NAB_PR_NUMBER"

    if [ "$auto_merge" = "true" ]; then
        nab_pr_auto_merge "${GITHUB_REPOSITORY:-}" "$NAB_PR_NUMBER"
    fi
}

# Run only when executed, so the tests can source this file and call its functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main
fi
