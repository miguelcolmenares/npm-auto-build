#!/usr/bin/env bats
# Mode pr: the build output goes to a bot branch and one pull request is kept up to date.
# Every test uses a local bare repository as `origin` (a file:// URL) and a clone of it as the
# working repository, so there is no network. A fake `git` on PATH records the arguments and
# the credential variables of every call, and a fake `gh` records its arguments and the
# GH_TOKEN it gets and keeps the one pull request it "opened" in a state file.

load helpers

# In a bats test a command written as `! cmd` never fails the test, because bash ignores
# the exit status of a negated command. `not cmd` does fail it when cmd succeeds.
not() {
    if "$@"; then
        return 1
    fi
}

# Plain git for the test itself, never the spy.
g() {
    "$REAL_GIT" "$@"
}

BOT=auto-build/main

setup() {
    reset_inputs
    default_inputs
    export INPUT_MODE=pr

    # A git that ignores the machine configuration, so the tests do not depend on it.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_COUNT
    # On a GitHub runner these describe the workflow run, for example 18/merge, and they
    # would trigger the branch notice in tests that expect none.
    unset GITHUB_REF GITHUB_REF_NAME GITHUB_REF_TYPE GITHUB_HEAD_REF GITHUB_BASE_REF GITHUB_EVENT_NAME
    unset FAKE_GH_FAIL FAKE_GH_METHODS SPY_KEEP
    export GITHUB_REPOSITORY=octo/repo
    REAL_GIT="$(command -v git)"

    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    WORK="$BATS_TEST_TMPDIR/work"
    OTHER="$BATS_TEST_TMPDIR/other"
    g init -q --bare -b main "$ORIGIN"

    # Seed the remote with the fixture project. dist/ is ignored, like in most projects.
    local seed="$BATS_TEST_TMPDIR/seed"
    mkdir -p "$seed"
    cp "$FIXTURE/package.json" "$FIXTURE/package-lock.json" "$FIXTURE/build.js" "$seed/"
    printf 'dist/\n' >"$seed/.gitignore"
    printf 'readme\n' >"$seed/README.md"
    g -C "$seed" init -q -b main
    g -C "$seed" add -A
    g -C "$seed" -c user.name=Seed -c user.email=seed@example.com commit -q -m "seed"
    g -C "$seed" push -q "file://$ORIGIN" main
    g clone -q "file://$ORIGIN" "$WORK"

    SPY_LOG="$BATS_TEST_TMPDIR/spy.log"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    GH_STATE="$BATS_TEST_TMPDIR/gh-state"
    SPY_BEFORE_PUSH="$BATS_TEST_TMPDIR/before-push.sh"
    : >"$SPY_LOG"
    : >"$GH_LOG"
    mkdir -p "$GH_STATE" "$BATS_TEST_TMPDIR/spy-bin"

    # The fake git: record, run something once before a push when a test asks for it, run the
    # real git.
    cat >"$BATS_TEST_TMPDIR/spy-bin/git" <<'SPY'
#!/usr/bin/env bash
{
    printf 'CALL|%s|ENV|' "$*"
    env | grep -E '^(GIT_CONFIG_(COUNT|KEY|VALUE)|NAB_TOKEN|GH_TOKEN)' | tr '\n' ';' || true
    printf '\n'
} >>"$SPY_LOG"
case " $* " in
    *" push "*)
        if [ -x "$SPY_BEFORE_PUSH" ]; then
            "$SPY_BEFORE_PUSH"
            [ -n "${SPY_KEEP:-}" ] || rm -f "$SPY_BEFORE_PUSH"
        fi
        ;;
esac
exec "$REAL_GIT" "$@"
SPY
    # The fake gh. It answers `pr list` with the pull request that `pr create` made, and it
    # fails the command named in FAKE_GH_FAIL (list, create, edit, view or merge).
    cat >"$BATS_TEST_TMPDIR/spy-bin/gh" <<'GH'
#!/usr/bin/env bash
args=()
for a in "$@"; do
    args[${#args[@]}]=${a//$'\n'/\\n}
done
{
    printf 'CALL|%s|ENV|GH_TOKEN=%s;NAB_TOKEN=%s;\n' "${args[*]}" "${GH_TOKEN:-}" "${NAB_TOKEN:-}"
} >>"$GH_LOG"
sub="$1 $2"
if [ "${FAKE_GH_FAIL:-}" = "${2:-}" ]; then
    case "$FAKE_GH_FAIL" in
        create) echo "GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)" >&2 ;;
        merge) echo "GraphQL: Auto merge is not allowed for this repository (enablePullRequestAutoMerge)" >&2 ;;
        *) echo "::set-output name=x::y" >&2; echo "gh: HTTP 500" >&2 ;;
    esac
    exit 1
fi
case "$sub" in
    "pr list")
        [ ! -f "$GH_STATE/pr" ] || cat "$GH_STATE/pr"
        ;;
    "pr create")
        echo "Creating pull request for the branch" >&2
        echo "7 https://github.com/octo/repo/pull/7" >"$GH_STATE/pr"
        echo "https://github.com/octo/repo/pull/7"
        ;;
    "pr edit" | "pr merge") ;;
    "repo view")
        echo "${FAKE_GH_METHODS-squash}"
        ;;
    *)
        echo "unexpected gh call: $*" >&2
        exit 2
        ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/spy-bin/git" "$BATS_TEST_TMPDIR/spy-bin/gh"
    export SPY_LOG GH_LOG GH_STATE SPY_BEFORE_PUSH REAL_GIT
    export PATH="$BATS_TEST_TMPDIR/spy-bin:$PATH"

    cd "$WORK"
    pr_env
}

# The variables the pr step has when the composite action runs it: the ones that
# action.yml sets, and the normalized values that validate-inputs.sh passes on.
pr_env() {
    export NAB_MODE=pr
    export NAB_WORKDIR=.
    export NAB_PATHS=dist
    export NAB_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export NAB_GIT_USER_NAME="github-actions[bot]"
    export NAB_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    export NAB_TOKEN="$FAKE_TOKEN"
    export NAB_PR_BRANCH=""
    export NAB_PR_TITLE="chore: update build output"
    export NAB_PR_LABELS=""
    export NAB_AUTO_MERGE=false
}

# Build the fixture in the working repository.
build() {
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
}

# Build and run the pr step, and require success.
run_pr() {
    build
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
}

visible_output() {
    printf '%s\n' "$output" | grep -v '^::add-mask::' || true
}

remote_head() {
    g --git-dir="$ORIGIN" rev-parse "${1:-main}"
}

has_remote_branch() {
    g --git-dir="$ORIGIN" rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

push_calls() {
    grep -c '^CALL|.* push ' "$SPY_LOG" || true
}

gh_calls() {
    grep -c '^CALL|' "$GH_LOG" || true
}

# The lines of the gh log for one subcommand, for example "pr create".
gh_lines() {
    grep "^CALL|$1 " "$GH_LOG" || true
}

# Put a commit on the remote that the working clone does not have. $1 is the branch, $2 the
# message lines (marker or not).
remote_commit() {
    local branch=$1 marker=$2 tmp="$BATS_TEST_TMPDIR/racer"
    rm -rf "$tmp"
    g clone -q "file://$ORIGIN" "$tmp"
    if has_remote_branch "$branch"; then
        g -C "$tmp" checkout -q "$branch"
    else
        g -C "$tmp" checkout -q -b "$branch"
    fi
    printf 'racer\n' >"$tmp/racer.txt"
    g -C "$tmp" add racer.txt
    if [ "$marker" = "marker" ]; then
        g -C "$tmp" -c user.name=Racer -c user.email=racer@example.com commit -q -m "racer" -m "Generated-by: npm-auto-build"
    else
        g -C "$tmp" -c user.name=Racer -c user.email=racer@example.com commit -q -m "racer"
    fi
    g -C "$tmp" push -q origin "$branch"
}

# ---------------------------------------------------------------------------
# The happy path

@test "no branch and no pull request yet: both are made, and the outputs say which" {
    local before
    before=$(remote_head)
    run_pr
    # The bot branch is one commit on top of main with the ignored dist/ file in it.
    has_remote_branch "$BOT"
    [ "$(g --git-dir="$ORIGIN" rev-list --count "main..$BOT")" -eq 1 ]
    [ "$(g --git-dir="$ORIGIN" rev-parse "$BOT^")" = "$before" ]
    [ "$(g --git-dir="$ORIGIN" show "$BOT:dist/out.txt")" = "built by the fixture" ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= "$BOT")" = "dist/out.txt" ]
    # One pull request was asked for, against main, from the bot branch.
    [ "$(gh_lines "pr create" | wc -l | tr -d ' ')" -eq 1 ]
    gh_lines "pr create" | grep -qF -- "--repo=octo/repo --base=main --head=$BOT --title=chore: update build output --body="
    [ "$(output_value pull-request-url)" = "https://github.com/octo/repo/pull/7" ]
    [ "$(output_value pull-request-number)" = "7" ]
}

@test "the commit has the author, the message without [skip ci], and the marker line" {
    run_pr
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%an "$BOT")" = "github-actions[bot]" ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%ae "$BOT")" = "github-actions[bot]@users.noreply.github.com" ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s "$BOT")" = "chore: update build output" ]
    g --git-dir="$ORIGIN" log -1 --format=%B "$BOT" | grep -qxF "Generated-by: npm-auto-build"
}

@test "a custom message is kept, and a skip marker in it gets a notice about the checks" {
    export NAB_COMMIT_MESSAGE="build: refresh dist [skip ci]"
    run_pr
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s "$BOT")" = "build: refresh dist [skip ci]" ]
    [[ "$output" == *"::notice::The commit message has a skip marker"* ]] || return 1

    export NAB_COMMIT_MESSAGE="build: refresh dist"
    g --git-dir="$ORIGIN" update-ref -d "refs/heads/$BOT"
    rm -f "$GH_STATE/pr"
    run_pr
    [[ "$output" != *"::notice::The commit message has a skip marker"* ]] || return 1
}

@test "the base branch, the local branch and the working tree are left as they were" {
    local before
    before=$(remote_head)
    build
    local local_head
    local_head=$(g rev-parse HEAD)
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 0 ]
    [ "$(remote_head)" = "$before" ]
    [ "$(g rev-parse HEAD)" = "$local_head" ]
    [ "$(g symbolic-ref --short HEAD)" = "main" ]
    # The index is back to HEAD, and the build output is still on disk.
    g diff --cached --quiet
    [ "$(cat dist/out.txt)" = "built by the fixture" ]
}

@test "every push goes to the bot branch only, with a lease and never a plain force" {
    run_pr
    [ "$(push_calls)" -eq 1 ]
    local line
    line=$(grep ' push ' "$SPY_LOG" | cut -d'|' -f2)
    # A lease on a branch that does not exist yet: the expected value is empty.
    [[ "$line" == *" push --no-verify --force-with-lease=refs/heads/$BOT: origin "*":refs/heads/$BOT" ]] || {
        echo "$line" >&2
        return 1
    }
    grep ' push ' "$SPY_LOG" | cut -d'|' -f2 >"$BATS_TEST_TMPDIR/pushes.txt"
    not grep -qE -- '--force( |$)| -f | \+|refs/heads/main' "$BATS_TEST_TMPDIR/pushes.txt"
    # No call of any kind names a refspec that writes to main.
    cut -d'|' -f2 "$SPY_LOG" >"$BATS_TEST_TMPDIR/argv.txt"
    not grep -qE ':refs/heads/main|:main( |$)' "$BATS_TEST_TMPDIR/argv.txt"
}

# ---------------------------------------------------------------------------
# A second run

@test "a second run with the same build opens no second pull request and pushes nothing" {
    run_pr
    local first
    first=$(remote_head "$BOT")
    : >"$SPY_LOG"
    : >"$GH_LOG"
    : >"$GITHUB_OUTPUT"
    run_pr
    [ "$(remote_head "$BOT")" = "$first" ]
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_lines "pr create" | wc -l | tr -d ' ')" -eq 0 ]
    [ "$(gh_lines "pr edit" | wc -l | tr -d ' ')" -eq 1 ]
    gh_lines "pr edit" | grep -qF -- "pr edit 7 --repo=octo/repo --title=chore: update build output"
    [ "$(output_value pull-request-number)" = "7" ]
    [ "$(output_value pull-request-url)" = "https://github.com/octo/repo/pull/7" ]
    [[ "$output" == *"nothing to push"* ]] || return 1
}

@test "a changed build is force-pushed over the old one, with a lease on the old tip" {
    run_pr
    local first
    first=$(remote_head "$BOT")
    : >"$SPY_LOG"
    printf 'newer\n' >>dist/out.txt
    : >"$GITHUB_OUTPUT"
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(remote_head "$BOT")" != "$first" ]
    # Still one commit on top of main, so the branch does not pile up commits.
    [ "$(g --git-dir="$ORIGIN" rev-list --count "main..$BOT")" -eq 1 ]
    [ "$(g --git-dir="$ORIGIN" show "$BOT:dist/out.txt" | tail -n 1)" = "newer" ]
    grep ' push ' "$SPY_LOG" | grep -qF -- "--force-with-lease=refs/heads/$BOT:$first origin"
    [ "$(gh_lines "pr create" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(gh_lines "pr edit" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "when the base moved, the bot branch is rebuilt on the new base" {
    run_pr
    # Someone pushes to main and the next run starts from it.
    remote_commit main nomarker
    g pull -q --ff-only origin main
    : >"$SPY_LOG"
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" rev-parse "$BOT^")" = "$(remote_head main)" ]
    [ "$(push_calls)" -eq 1 ]
}

@test "when the bot branch moved between the look and the push, the lease refuses and the run tries again" {
    # A racing run makes the branch after this run looked and before it pushed.
    cat >"$SPY_BEFORE_PUSH" <<EOF
#!/usr/bin/env bash
set -e
tmp="$BATS_TEST_TMPDIR/racer2"
"$REAL_GIT" clone -q "file://$ORIGIN" "\$tmp"
"$REAL_GIT" -C "\$tmp" checkout -q -b $BOT
echo racer > "\$tmp/racer.txt"
"$REAL_GIT" -C "\$tmp" add racer.txt
"$REAL_GIT" -C "\$tmp" -c user.name=Racer -c user.email=r@example.com commit -q -m racer -m "Generated-by: npm-auto-build"
"$REAL_GIT" -C "\$tmp" push -q origin $BOT
EOF
    chmod +x "$SPY_BEFORE_PUSH"
    run_pr
    [ "$(push_calls)" -eq 2 ]
    [[ "$output" == *"The push was rejected because '$BOT' moved (attempt 1 of 3)"* ]] || return 1
    # The second push had a lease on the tip of the racing run, and won.
    local line
    line=$(grep ' push ' "$SPY_LOG" | tail -n 1)
    [[ "$line" == *"--force-with-lease=refs/heads/$BOT:"[0-9a-f]* ]] || return 1
    [[ "$line" != *"--force-with-lease=refs/heads/$BOT: "* ]] || return 1
    [ "$(output_value pull-request-number)" = "7" ]
}

@test "when a person made the branch between the look and the push, nothing is overwritten" {
    cat >"$SPY_BEFORE_PUSH" <<EOF
#!/usr/bin/env bash
set -e
tmp="$BATS_TEST_TMPDIR/racer3"
"$REAL_GIT" clone -q "file://$ORIGIN" "\$tmp"
"$REAL_GIT" -C "\$tmp" checkout -q -b $BOT
echo mine > "\$tmp/mine.txt"
"$REAL_GIT" -C "\$tmp" add mine.txt
"$REAL_GIT" -C "\$tmp" -c user.name=Person -c user.email=p@example.com commit -q -m "my work"
"$REAL_GIT" -C "\$tmp" push -q origin $BOT
EOF
    chmod +x "$SPY_BEFORE_PUSH"
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The branch '$BOT' exists on the remote and was not made by this action"* ]] || return 1
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s "$BOT")" = "my work" ]
    [ "$(push_calls)" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "the push is tried three times at most when the branch keeps moving" {
    # Every push finds a new racing commit made just before it (SPY_KEEP keeps the hook).
    cat >"$SPY_BEFORE_PUSH" <<EOF
#!/usr/bin/env bash
set -e
tmp="$BATS_TEST_TMPDIR/racer4"
rm -rf "\$tmp"
"$REAL_GIT" clone -q "file://$ORIGIN" "\$tmp"
if "$REAL_GIT" -C "\$tmp" rev-parse --verify --quiet origin/$BOT >/dev/null; then
    "$REAL_GIT" -C "\$tmp" checkout -q $BOT
else
    "$REAL_GIT" -C "\$tmp" checkout -q -b $BOT
fi
count=\$(cat "$BATS_TEST_TMPDIR/racer-count" 2>/dev/null || echo 0)
echo \$((count + 1)) > "$BATS_TEST_TMPDIR/racer-count"
echo "\$count" > "\$tmp/racer.txt"
"$REAL_GIT" -C "\$tmp" add racer.txt
"$REAL_GIT" -C "\$tmp" -c user.name=Racer -c user.email=r@example.com commit -q -m racer -m "Generated-by: npm-auto-build"
"$REAL_GIT" -C "\$tmp" push -q origin $BOT
EOF
    chmod +x "$SPY_BEFORE_PUSH"
    export SPY_KEEP=1
    build
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"still rejected after 3 attempts"* ]] || return 1
    [ "$(push_calls)" -eq 3 ]
    [ "$(gh_calls)" -eq 0 ]
}

# ---------------------------------------------------------------------------
# No difference

@test "when the base already holds the build output there is no branch and no pull request" {
    build
    g add -f dist
    g -c user.name=T -c user.email=t@example.com commit -q -m "commit dist"
    g push -q origin main
    : >"$SPY_LOG"
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"no branch to push and no pull request to open"* ]] || return 1
    not has_remote_branch "$BOT"
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    [ -z "$(output_value pull-request-url)" ]
    [ -z "$(output_value pull-request-number)" ]
}

# ---------------------------------------------------------------------------
# The branch name

@test "a branch input is used for the branch and the pull request" {
    export NAB_PR_BRANCH="bot/build-output"
    run_pr
    has_remote_branch "bot/build-output"
    not has_remote_branch "$BOT"
    gh_lines "pr create" | grep -qF -- "--head=bot/build-output"
}

@test "the default branch name has the checked out branch in it" {
    g checkout -q -b feature/x
    run_pr
    has_remote_branch "auto-build/feature/x"
    gh_lines "pr create" | grep -qF -- "--base=feature/x --head=auto-build/feature/x"
}

@test "a branch equal to the base branch is refused and nothing happens" {
    g checkout -q -b feature/x
    g push -q origin feature/x
    build
    export NAB_PR_BRANCH="feature/x"
    local before
    before=$(remote_head feature/x)
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::branch 'feature/x' is the base branch of the pull request"* ]] || return 1
    [ "$(remote_head feature/x)" = "$before" ]
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "the base branch is refused in any letter case" {
    g checkout -q -b Feature/X
    build
    export NAB_PR_BRANCH="feature/x"
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is the base branch"* ]] || return 1
    [ "$(push_calls)" -eq 0 ]
}

@test "a protected or shared branch name is refused, in any letter case, before anything runs" {
    build
    local name before
    before=$(remote_head)
    for name in main master Main trunk develop development dev stable production prod staging gh-pages HEAD release releases/2 release/1.x; do
        export NAB_PR_BRANCH="$name"
        run bash "$SCRIPTS/pr.sh"
        [ "$status" -eq 1 ] || {
            echo "'$name' was accepted" >&2
            return 1
        }
        [[ "$output" == *"is a protected or shared branch name"* ]] || {
            echo "'$name': $output" >&2
            return 1
        }
    done
    [ "$(remote_head)" = "$before" ]
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "the default branch of the remote is refused even when its name is not on the list" {
    g push -q origin main:site-live
    g --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/site-live
    build
    export NAB_PR_BRANCH="site-live"
    local before
    before=$(remote_head site-live)
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is the default branch of the remote"* ]] || return 1
    [ "$(remote_head site-live)" = "$before" ]
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "a branch that exists and was not made by the action is refused, never overwritten" {
    remote_commit "$BOT" nomarker
    build
    local before
    before=$(remote_head "$BOT")
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The branch '$BOT' exists on the remote and was not made by this action"* ]] || return 1
    [[ "$output" == *"Generated-by: npm-auto-build"* ]] || return 1
    [ "$(remote_head "$BOT")" = "$before" ]
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "a branch of the action that already exists is updated" {
    remote_commit "$BOT" marker
    run_pr
    [ "$(g --git-dir="$ORIGIN" rev-parse "$BOT^")" = "$(remote_head main)" ]
    [ "$(push_calls)" -eq 1 ]
}

@test "a checked out branch that looks like a bot branch is refused, it would loop" {
    g checkout -q -b auto-build/main
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"looks like a branch of this action"* ]] || return 1
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "a detached HEAD is refused with a message about the base branch" {
    build
    g checkout -q --detach
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::HEAD is detached, so there is no base branch for the pull request"* ]] || return 1
    [[ "$output" == *"pull_request"* ]] || return 1
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "a workflow ref that differs from the checked out branch is explained for the pull request" {
    build
    export GITHUB_REF_NAME=other-branch GITHUB_REF_TYPE=branch
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::notice::The workflow ran for 'other-branch' but the checked out branch is 'main'. The pull request is opened against 'main'."* ]] || return 1
}

# ---------------------------------------------------------------------------
# The pull request

@test "title and labels are passed as separate arguments, whatever they hold" {
    export NAB_PR_TITLE='-- build $(touch /tmp/pwned) "quoted" & more'
    export NAB_PR_LABELS='build,needs review,-odd'
    run_pr
    local line
    line=$(gh_lines "pr create")
    [[ "$line" == *'--title=-- build $(touch /tmp/pwned) "quoted" & more'* ]] || return 1
    [[ "$line" == *"--label=build --label=needs review --label=-odd"* ]] || return 1
    [ ! -e /tmp/pwned ]
}

@test "an open pull request gets the title and the labels again, labels are only added" {
    run_pr
    export NAB_PR_TITLE="build: new title"
    export NAB_PR_LABELS="build,ci"
    : >"$GH_LOG"
    printf 'more\n' >>dist/out.txt
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 0 ]
    gh_lines "pr edit" | grep -qF -- "pr edit 7 --repo=octo/repo --title=build: new title --add-label=build --add-label=ci"
    gh_lines "pr edit" >"$BATS_TEST_TMPDIR/edits.txt"
    not grep -q -- '--remove-label' "$BATS_TEST_TMPDIR/edits.txt"
}

@test "the lookup is for an open pull request of the bot branch against the base" {
    run_pr
    gh_lines "pr list" | grep -qF -- "--repo=octo/repo --head=$BOT --base=main --state=open"
}

@test "auto-merge off: gh is never asked to merge" {
    run_pr
    [ "$(gh_lines "pr merge" | wc -l | tr -d ' ')" -eq 0 ]
    [ "$(gh_lines "repo view" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "auto-merge on: gh pr merge --auto with the first merge method the repository allows" {
    export NAB_AUTO_MERGE=true
    run_pr
    gh_lines "pr merge" | grep -qF -- "pr merge 7 --repo=octo/repo --auto --squash"
    [[ "$output" == *"Auto-merge is enabled on the pull request #7 (squash)"* ]] || return 1
}

@test "auto-merge picks merge or rebase when squash is not allowed, and fails when none is" {
    export NAB_AUTO_MERGE=true
    FAKE_GH_METHODS=merge run_pr
    gh_lines "pr merge" | grep -qF -- "--auto --merge"

    : >"$GH_LOG"
    export FAKE_GH_METHODS=""
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The repository allows no merge method"* ]] || return 1
    [ "$(gh_lines "pr merge" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "a failed auto-merge fails the step after the outputs are written, and says what to set" {
    export NAB_AUTO_MERGE=true
    export FAKE_GH_FAIL=merge
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::gh could not enable auto-merge on the pull request #7. The pull request is open."* ]] || return 1
    [[ "$output" == *'"Allow auto-merge"'* ]] || return 1
    [ "$(output_value pull-request-number)" = "7" ]
}

@test "a refused pull request keeps the pushed branch and names the repository setting" {
    export FAKE_GH_FAIL=create
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::gh could not open the pull request from '$BOT' to 'main'."* ]] || return 1
    [[ "$output" == *"Allow GitHub Actions to create and approve pull requests"* ]] || return 1
    has_remote_branch "$BOT"
    [ -z "$(output_value pull-request-url)" ]
}

@test "a failing lookup stops before any pull request is made" {
    export FAKE_GH_FAIL=list
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh could not look for an open pull request from '$BOT'"* ]] || return 1
    [ "$(gh_lines "pr create" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "what gh prints can never start a workflow command" {
    export FAKE_GH_FAIL=list
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[gh] ::set-output name=x::y"* ]] || return 1
    printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/out.txt"
    not grep -q '^::set-output' "$BATS_TEST_TMPDIR/out.txt"
}

@test "without gh on PATH the step says so, after the branch is pushed" {
    rm "$BATS_TEST_TMPDIR/spy-bin/gh"
    build
    # A GitHub runner has gh in /usr/bin, so that directory cannot be on PATH as it is. Link
    # every tool of the system directories except gh into a directory of its own.
    local tools="$BATS_TEST_TMPDIR/tools-without-gh" dir tool
    mkdir -p "$tools"
    for dir in /usr/bin /bin; do
        for tool in "$dir"/*; do
            [ "${tool##*/}" = gh ] && continue
            # -f because /bin is a link to /usr/bin on most runners, and some links are broken.
            ln -sf "$tool" "$tools/${tool##*/}" 2>/dev/null || true
        done
    done
    [ ! -e "$tools/gh" ] || false
    run env PATH="$BATS_TEST_TMPDIR/spy-bin:$tools:$(dirname "$(command -v node)")" bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The GitHub CLI (gh) was not found on PATH"* ]] || return 1
}

@test "GITHUB_REPOSITORY must be owner/name" {
    build
    export GITHUB_REPOSITORY="not a repo"
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GITHUB_REPOSITORY is 'not a repo', expected owner/name"* ]] || return 1
    [ "$(gh_calls)" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Refusals shared with mode commit

@test "outside mode pr the script refuses to run" {
    export NAB_MODE=commit
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pr.sh runs only in mode pr"* ]] || return 1
}

@test "an empty token fails before anything is committed or pushed" {
    build
    export NAB_TOKEN=""
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The token is empty"* ]] || return 1
    [ "$(push_calls)" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "paths that are not a build folder are refused, and nothing is staged" {
    build
    local entry
    for entry in . .. ../x ../../x .git .git/hooks /abs 'C:\\x'; do
        export NAB_PATHS="$entry"
        run bash "$SCRIPTS/pr.sh"
        [ "$status" -eq 1 ] || {
            echo "'$entry' was accepted" >&2
            return 1
        }
        g diff --cached --quiet
    done
    [ "$(push_calls)" -eq 0 ]
}

@test "already staged changes are refused, they would end up in the build commit" {
    build
    printf 'x\n' >staged.txt
    g add staged.txt
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The index already has staged changes"* ]] || return 1
    [ "$(push_calls)" -eq 0 ]
}

@test "repository hooks do not run for the build commit" {
    mkdir -p .git/hooks
    printf '#!/bin/sh\necho hook ran >> "%s/hook.log"\nexit 1\n' "$BATS_TEST_TMPDIR" >.git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    run_pr
    [ ! -e "$BATS_TEST_TMPDIR/hook.log" ]
}

@test "a protected bot branch gives the way out and one push attempt" {
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "error: GH006: Protected branch update failed for refs/heads/auto-build/main. protected branch hook declined" >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The push to '$BOT' was rejected because the branch is protected"* ]] || return 1
    [[ "$output" == *"Exclude '$BOT' from the branch protection rules"* ]] || return 1
    [ "$(push_calls)" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
}

@test "a refused credential points to permissions and persist-credentials" {
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "remote: Permission to octo/repo.git denied to github-actions[bot]." >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"permissions: contents: write"* ]] || return 1
    [[ "$output" == *"persist-credentials: false"* ]] || return 1
}

# ---------------------------------------------------------------------------
# The token

@test "the token is in no file of .git, no git config, no output and no step file" {
    run_pr
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')
    not grep -rqF -- "$FAKE_TOKEN" .git
    not grep -rqF -- "$encoded" .git
    not grep -rqF -- "$FAKE_TOKEN" "$ORIGIN"
    run g config --list --show-origin
    [[ "$output" != *"$FAKE_TOKEN"* ]] || return 1
    [[ "$output" != *"$encoded"* ]] || return 1
    [[ "$output" != *"extraheader"* ]] || return 1
    run g config --list --global
    [[ "$output" != *"$FAKE_TOKEN"* ]] || return 1
    not grep -qF -- "$FAKE_TOKEN" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    not grep -qF -- "$encoded" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    # Not in the build output that was committed, nor in the files of the workspace.
    not grep -rqF -- "$FAKE_TOKEN" dist README.md package.json
    not g --git-dir="$ORIGIN" grep -qF -- "$FAKE_TOKEN" "$BOT"
}

@test "the step output never shows the token, only the masks do" {
    build
    run bash "$SCRIPTS/pr.sh"
    [ "$status" -eq 0 ]
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')
    [ "$(printf '%s\n' "$output" | grep -c '^::add-mask::')" -eq 2 ]
    printf '%s\n' "$output" | grep -qxF "::add-mask::$FAKE_TOKEN"
    printf '%s\n' "$output" | grep -qxF "::add-mask::$encoded"
    local visible
    visible=$(visible_output)
    [[ "$visible" != *"$FAKE_TOKEN"* ]] || return 1
    [[ "$visible" != *"$encoded"* ]] || return 1
}

@test "the token is in no git argument, and only ls-remote, fetch and push carry it, in the environment" {
    # A competing commit on the bot branch makes the run use ls-remote, fetch and push.
    remote_commit "$BOT" marker
    run_pr
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')

    cut -d'|' -f2 "$SPY_LOG" >"$BATS_TEST_TMPDIR/argv.txt"
    [ -s "$BATS_TEST_TMPDIR/argv.txt" ]
    not grep -qF -- "$FAKE_TOKEN" "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qF -- "$encoded" "$BATS_TEST_TMPDIR/argv.txt"
    not grep -q 'http\.extraheader' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qi 'authorization' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -q 'url\.' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qF 'x-access-token' "$BATS_TEST_TMPDIR/argv.txt"

    local line
    while IFS= read -r line; do
        case "$line" in
            *" push "* | *" fetch "* | *" ls-remote "*)
                [[ "$line" == *"GIT_CONFIG_KEY_0=http.extraheader;"* && "$line" == *"GIT_CONFIG_VALUE_0=AUTHORIZATION: basic $encoded;"* ]] || {
                    echo "no header on: $line" >&2
                    return 1
                }
                ;;
            *)
                [[ "$line" != *"GIT_CONFIG_"* && "$line" != *"NAB_TOKEN"* && "$line" != *"GH_TOKEN"* ]] || {
                    echo "credential on a local call: $line" >&2
                    return 1
                }
                ;;
        esac
    done <"$SPY_LOG"
    grep -q ' push ' "$SPY_LOG"
    grep -q ' fetch ' "$SPY_LOG"
    grep -q ' ls-remote ' "$SPY_LOG"
    not grep -q 'NAB_TOKEN' "$SPY_LOG"
    not grep -q 'GH_TOKEN' "$SPY_LOG"
}

@test "gh gets the token as GH_TOKEN in its environment and never in its arguments" {
    export NAB_AUTO_MERGE=true
    export NAB_PR_LABELS="build"
    run_pr
    local calls
    calls=$(gh_calls)
    [ "$calls" -ge 4 ]
    # Every call has the token in GH_TOKEN, and none has NAB_TOKEN.
    [ "$(grep -c "|ENV|GH_TOKEN=$FAKE_TOKEN;NAB_TOKEN=;" "$GH_LOG")" -eq "$calls" ]
    cut -d'|' -f2 "$GH_LOG" >"$BATS_TEST_TMPDIR/gh-argv.txt"
    not grep -qF -- "$FAKE_TOKEN" "$BATS_TEST_TMPDIR/gh-argv.txt"
    not grep -qi 'token' "$BATS_TEST_TMPDIR/gh-argv.txt"
    # And the shell that runs the script never exported it.
    not grep -q 'GH_TOKEN' "$SPY_LOG"
}

@test "a GH_TOKEN or GITHUB_TOKEN that the workflow exported is not given to git" {
    export GH_TOKEN="ambient-token-that-is-not-ours" GITHUB_TOKEN="ambient-github-token"
    run_pr
    # The spy greps GH_TOKEN in the environment of every git call: the ambient one passes
    # through (the action does not own it), but ours never replaces it.
    not grep -qF -- "$FAKE_TOKEN" "$SPY_LOG"
    # gh got ours, not the ambient one.
    [ "$(grep -c "GH_TOKEN=$FAKE_TOKEN;" "$GH_LOG")" -eq "$(gh_calls)" ]
}

@test "the build and install steps of the same job never see the token" {
    export GITHUB_TOKEN="$FAKE_TOKEN" GH_TOKEN="$FAKE_TOKEN" INPUT_TOKEN="$FAKE_TOKEN"
    export INPUT_GITHUB_TOKEN="$FAKE_TOKEN" ACTIONS_RUNTIME_TOKEN="$FAKE_TOKEN"
    cat >package.json <<'JSON'
{
  "name": "token-probe",
  "version": "1.0.0",
  "scripts": {
    "preinstall": "env > install-env.txt",
    "build": "mkdir -p dist && env > dist/build-env.txt"
  }
}
JSON
    rm -f package-lock.json
    local saved_token=$NAB_TOKEN
    unset NAB_TOKEN NAB_MODE NAB_WORKDIR NAB_PATHS
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    not grep -q "$FAKE_TOKEN" install-env.txt dist/build-env.txt
    not grep -q 'NAB_TOKEN' install-env.txt dist/build-env.txt

    # Now the pr step, with its own env.
    export NAB_TOKEN=$saved_token
    export NAB_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export NAB_GIT_USER_NAME="github-actions[bot]" NAB_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    export NAB_PR_BRANCH="" NAB_PR_TITLE="chore: update build output" NAB_PR_LABELS="" NAB_AUTO_MERGE=false
    run bash "$SCRIPTS/pr.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show "$BOT:dist/build-env.txt" | grep -c "$FAKE_TOKEN" || true)" -eq 0 ]
    [ "$(output_value pull-request-number)" = "7" ]
}

@test "persisted checkout credentials are reported by key name, never by value" {
    g config http.https://github.com/.extraheader "AUTHORIZATION: basic cGVyc2lzdGVkLXNlY3JldA=="
    build
    run bash "$SCRIPTS/pr.sh"
    [[ "$output" == *"::warning::"*"http.https://github.com/.extraheader"*"persist-credentials: false"* ]] || return 1
    [[ "$output" != *"cGVyc2lzdGVkLXNlY3JldA"* ]] || return 1
}

# ---------------------------------------------------------------------------
# The inputs, checked by validate-inputs.sh before the build

validate_pr() {
    export INPUT_MODE=pr
    run bash "$SCRIPTS/validate-inputs.sh"
}

@test "validate: mode pr writes the normalized pull request inputs" {
    validate_pr
    [ "$status" -eq 0 ]
    [ "$(output_value mode)" = "pr" ]
    [ "$(env_value NAB_PR_BRANCH)" = "" ]
    [ "$(env_value NAB_PR_TITLE)" = "chore: update build output" ]
    [ "$(env_value NAB_PR_LABELS)" = "" ]
    [ "$(env_value NAB_AUTO_MERGE)" = "false" ]
}

@test "validate: branch, title, labels and auto-merge are kept, trimmed and normalized" {
    export INPUT_BRANCH="  bot/build  "
    export INPUT_PR_TITLE="  build: refresh  "
    export INPUT_PR_LABELS=" build , ,needs review,"
    export INPUT_AUTO_MERGE=TRUE
    validate_pr
    [ "$status" -eq 0 ]
    [ "$(env_value NAB_PR_BRANCH)" = "bot/build" ]
    [ "$(env_value NAB_PR_TITLE)" = "build: refresh" ]
    [ "$(env_value NAB_PR_LABELS)" = "build,needs review" ]
    [ "$(env_value NAB_AUTO_MERGE)" = "true" ]
}

@test "validate: the token is not written anywhere" {
    export INPUT_GITHUB_TOKEN_SET=true
    validate_pr
    [ "$status" -eq 0 ]
    not grep -qF -- "$FAKE_TOKEN" "$GITHUB_ENV" "$GITHUB_OUTPUT"
}

@test "validate: invalid branch names are refused before the build" {
    local name
    for name in 'a b' '-x' 'a..b' 'a//b' '/a' 'a/' '.hidden' 'a/.b' 'a.lock' 'a.' 'a~1' 'a^b' 'a:b' 'a?b' 'a*b' 'a[b' 'a\b' 'a@{b' 'ä'; do
        export INPUT_BRANCH="$name"
        validate_pr
        [ "$status" -eq 1 ] || {
            echo "'$name' was accepted" >&2
            return 1
        }
        [[ "$output" == *"::error::branch '"* ]] || {
            echo "'$name': $output" >&2
            return 1
        }
    done
}

@test "validate: protected and shared branch names are refused before the build" {
    local name
    for name in main master MAIN develop release/1.0 gh-pages HEAD production; do
        export INPUT_BRANCH="$name"
        validate_pr
        [ "$status" -eq 1 ] || {
            echo "'$name' was accepted" >&2
            return 1
        }
        [[ "$output" == *"is a protected or shared branch name"* ]] || return 1
    done
}

@test "validate: the branch input is not checked outside mode pr" {
    export INPUT_MODE=commit
    export INPUT_BRANCH="main"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
}

@test "validate: a title that is too long, a label that is too long and too many labels are refused" {
    export INPUT_PR_TITLE=$(printf 'x%.0s' $(seq 1 257))
    validate_pr
    [ "$status" -eq 1 ]
    [[ "$output" == *"pr-title is too long"* ]] || return 1
    export INPUT_PR_TITLE=ok
    export INPUT_PR_LABELS=$(printf 'y%.0s' $(seq 1 51))
    validate_pr
    [ "$status" -eq 1 ]
    [[ "$output" == *"'pr-labels' entry is too long"* ]] || return 1
    export INPUT_PR_LABELS=$(seq -s, 1 21)
    validate_pr
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than 20 labels"* ]] || return 1
}

@test "validate: a line break in the title, the labels or the branch is refused" {
    local var
    for var in INPUT_PR_TITLE INPUT_PR_LABELS INPUT_BRANCH; do
        reset_inputs
        default_inputs
        export "$var=a"$'\n'"b"
        validate_pr
        [ "$status" -eq 1 ] || {
            echo "$var was accepted" >&2
            return 1
        }
        [[ "$output" == *"must be a single line"* ]] || return 1
    done
}

@test "validate: auto-merge must be true or false" {
    export INPUT_AUTO_MERGE=yes
    validate_pr
    [ "$status" -eq 1 ]
    [[ "$output" == *"Input 'auto-merge' must be 'true' or 'false'"* ]] || return 1
}

@test "validate: mode pr no longer fails the mode gate, and no mode is reported as unavailable" {
    local mode
    for mode in build check commit pr; do
        export INPUT_MODE=$mode
        run bash "$SCRIPTS/validate-inputs.sh"
        [ "$status" -eq 0 ]
        [[ "$output" != *"not available"* ]] || return 1
    done
    export INPUT_MODE=deploy
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Use one of: commit, check, pr, build."* ]] || return 1
}

@test "nab_check_pr_branch_name accepts a plain bot branch name" {
    local name
    for name in auto-build/main auto-build/feature/x bot/build-output npm-auto-build/build my.bot_branch-1; do
        run bash -c 'source "$1/lib.sh"; nab_check_pr_branch_name "$2"' _ "$SCRIPTS" "$name"
        [ "$status" -eq 0 ] || {
            echo "'$name' was refused: $output" >&2
            return 1
        }
    done
}
