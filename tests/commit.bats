#!/usr/bin/env bats
# Mode commit: build output is committed and pushed. Every test uses a local bare
# repository as `origin` (a file:// URL) and a clone of it as the working repository, so
# there is no network. A fake `git` on PATH records the arguments and the credential
# variables of every call, to show where the token goes and where it does not.

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

setup() {
    reset_inputs
    default_inputs
    export INPUT_MODE=commit

    # A git that ignores the machine configuration, so the tests do not depend on it.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_COUNT
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

    # The spy goes first on PATH from here on.
    SPY_LOG="$BATS_TEST_TMPDIR/spy.log"
    : >"$SPY_LOG"
    mkdir -p "$BATS_TEST_TMPDIR/spy-bin"
    cat >"$BATS_TEST_TMPDIR/spy-bin/git" <<'SPY'
#!/usr/bin/env bash
{
    printf 'CALL|%s|ENV|' "$*"
    env | grep -E '^(GIT_CONFIG_(COUNT|KEY|VALUE)|NAB_TOKEN)' | tr '\n' ';' || true
    printf '\n'
} >>"$SPY_LOG"
exec "$REAL_GIT" "$@"
SPY
    chmod +x "$BATS_TEST_TMPDIR/spy-bin/git"
    export SPY_LOG REAL_GIT
    export PATH="$BATS_TEST_TMPDIR/spy-bin:$PATH"

    cd "$WORK"
    commit_env
}

# The variables the commit step has when the composite action runs it.
commit_env() {
    export NAB_MODE=commit
    export NAB_WORKDIR=.
    export NAB_PATHS=dist
    export NAB_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export NAB_GIT_USER_NAME="github-actions[bot]"
    export NAB_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    export NAB_TOKEN="$FAKE_TOKEN"
}

# Build the fixture in the working repository.
build() {
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
}

# The output without the lines that ask the runner to mask a value. Those lines carry the
# secret on purpose and the runner removes them from the log.
visible_output() {
    printf '%s\n' "$output" | grep -v '^::add-mask::' || true
}

remote_head() {
    g --git-dir="$ORIGIN" rev-parse "${1:-main}"
}

# Put a commit on the remote that the working clone does not have.
competing_commit() {
    local file=$1 content=$2
    if [ ! -d "$OTHER" ]; then
        g clone -q "file://$ORIGIN" "$OTHER"
    fi
    mkdir -p "$(dirname "$OTHER/$file")"
    printf '%s\n' "$content" >"$OTHER/$file"
    g -C "$OTHER" add -f -- "$file"
    g -C "$OTHER" -c user.name=Other -c user.email=other@example.com commit -q -m "competing commit"
    g -C "$OTHER" push -q origin main
}

# Succeed when a recorded git push call matches the extended regex. Used to prove that no
# push is ever forced. The fetch refspec has a leading "+" on purpose, it is not a push.
push_lines_match() {
    shift
    grep ' push ' "$SPY_LOG" | cut -d'|' -f2 | grep -qE -- "$1"
}

push_calls() {
    grep -c '^CALL|.* push ' "$SPY_LOG" || true
}

# ---------------------------------------------------------------------------
# The happy path and the no-op

@test "a changed build is committed and pushed to the remote branch" {
    build
    local before
    before=$(remote_head)
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(output_value changed)" = "true" ]
    [ "$(remote_head)" != "$before" ]
    [ "$(output_value commit-sha)" = "$(remote_head)" ]
    # One commit on top of the seed, with the ignored dist/ file in it.
    [ "$(g --git-dir="$ORIGIN" rev-list --count "$before..main")" -eq 1 ]
    [ "$(g --git-dir="$ORIGIN" show main:dist/out.txt)" = "built by the fixture" ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main)" = "dist/out.txt" ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s main)" = "chore: update build output [skip ci]" ]
}

@test "the local branch and the remote branch are the same after the push" {
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(g rev-parse HEAD)" = "$(remote_head)" ]
}

@test "a second run makes no commit and reports changed=false" {
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    local first
    first=$(remote_head)

    : >"$GITHUB_OUTPUT"
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(output_value changed)" = "false" ]
    [ -z "$(output_value commit-sha)" ]
    [ "$(remote_head)" = "$first" ]
    [ "$(g rev-list --count HEAD)" -eq 2 ]
}

@test "no change means no push and no credential use" {
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    : >"$SPY_LOG"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(push_calls)" -eq 0 ]
}

@test "several paths, one per line, are all committed" {
    mkdir -p lib/types
    mkdir -p dist
    printf 'b\n' >dist/b.txt
    printf 'c\n' >lib/types/c.d.ts
    export NAB_PATHS=$'dist\nlib/types'
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main | sort)" = $'dist/b.txt\nlib/types/c.d.ts' ]
}

@test "files outside the paths are not committed" {
    build
    printf 'changed\n' >>README.md
    printf 'new\n' >untracked.txt
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main)" = "dist/out.txt" ]
    # The working tree is left as it was.
    [ -f untracked.txt ]
    grep -q '^changed$' README.md
}

@test "a working-directory below the repository root commits that folder only" {
    mkdir -p app
    cp "$FIXTURE/package.json" "$FIXTURE/build.js" app/
    export NAB_WORKDIR=app
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main)" = "app/dist/out.txt" ]
}

@test "the checked out branch is the branch that is pushed" {
    g checkout -q -b feature/build
    build
    local main_before
    main_before=$(remote_head main)
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(remote_head main)" = "$main_before" ]
    [ "$(remote_head feature/build)" = "$(output_value commit-sha)" ]
}

@test "a workflow ref that differs from the checked out branch is explained" {
    build
    export GITHUB_REF_NAME=other-branch GITHUB_REF_TYPE=branch
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::notice::The workflow ran for 'other-branch' but the checked out branch is 'main'"* ]] || return 1
}

# ---------------------------------------------------------------------------
# Refusals

@test "a detached HEAD fails with a message that says what to do" {
    build
    g checkout -q --detach
    local before
    before=$(remote_head)
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::HEAD is detached"* ]] || return 1
    [[ "$output" == *"tag push"* ]] || return 1
    [[ "$output" == *"pull_request"* ]] || return 1
    [[ "$output" == *"mode: check"* ]] || return 1
    [[ "$output" == *"mode: pr"* ]] || return 1
    [ "$(remote_head)" = "$before" ]
    [ "$(push_calls)" -eq 0 ]
    [ -z "$(output_value changed)" ]
}

@test "a tag checkout is refused like a detached HEAD" {
    build
    g tag v1.0.0
    g checkout -q v1.0.0
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"HEAD is detached"* ]] || return 1
}

@test "paths entries that are not a build folder are refused, and nothing is staged" {
    build
    local entry
    for entry in "." "./" ".git" ".git/config" "dist/../.git" "dist/.." "../x" "dist/../../x" ".GIT/hooks"; do
        export NAB_PATHS=$'dist\n'"$entry"
        run bash "$SCRIPTS/commit.sh"
        [ "$status" -eq 1 ] || {
            echo "entry '$entry' was accepted: $output" >&2
            return 1
        }
        [[ "$output" == *"::error::paths entry"* ]] || {
            echo "entry '$entry' gave: $output" >&2
            return 1
        }
        # The good entry before it was not staged either.
        g diff --cached --quiet
    done
    [ "$(g rev-list --count HEAD)" -eq 1 ]
}

@test "paths: an empty entry and an absolute entry are refused" {
    build
    export NAB_PATHS=$'dist\n\nlib'
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"paths entry is empty"* || "$output" == *"A 'paths' entry is empty"* ]] || return 1
    export NAB_PATHS="/etc"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be relative"* ]] || return 1
}

@test "paths: the working directory and the repository root are named in the message" {
    mkdir -p app
    cp "$FIXTURE/package.json" app/
    export NAB_WORKDIR=app
    export NAB_PATHS="."
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the working directory itself"* ]] || return 1
    export NAB_PATHS=".."
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the repository root"* ]] || return 1
    # A sibling folder inside the repository is fine to resolve.
    export NAB_PATHS="../dist"
    mkdir -p dist
    printf 'x\n' >dist/x.txt
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main)" = "dist/x.txt" ]
}

@test "a path with glob characters is taken literally" {
    printf 'star\n' >'star*'
    printf 'fish\n' >starfish
    export NAB_PATHS='star*'
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    # A glob would have added starfish too.
    [ "$(g --git-dir="$ORIGIN" show --name-only --format= main)" = "star*" ]
}

@test "a path that does not exist fails with a message" {
    export NAB_PATHS="missing-folder"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"git add failed for 'missing-folder'"* ]] || return 1
}

@test "already staged changes are refused, they would end up in the build commit" {
    build
    printf 'secret\n' >staged.txt
    g add staged.txt
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already has staged changes"* ]] || return 1
    [ "$(g rev-list --count HEAD)" -eq 1 ]
}

@test "outside mode commit the script refuses to run" {
    build
    export NAB_MODE=build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runs only in mode commit"* ]] || return 1
}

@test "outside a git repository the script says to run actions/checkout" {
    local plain="$BATS_TEST_TMPDIR/plain"
    mkdir -p "$plain"
    cp "$FIXTURE/package.json" "$plain/"
    cd "$plain"
    export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not inside a git repository"* ]] || return 1
}

@test "an empty token fails before anything is committed" {
    build
    export NAB_TOKEN=""
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The token is empty"* ]] || return 1
    [ "$(g rev-list --count HEAD)" -eq 1 ]
}

@test "empty commit message, user name and user email are refused" {
    build
    NAB_COMMIT_MESSAGE="" run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'commit-message' is empty"* ]] || return 1
    NAB_GIT_USER_NAME="" run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'git-user-name' is empty"* ]] || return 1
    NAB_GIT_USER_EMAIL="" run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'git-user-email' is empty"* ]] || return 1
}

# ---------------------------------------------------------------------------
# Author, message and hooks

@test "the commit has the configured author and message, and nothing is written to the config" {
    build
    export NAB_GIT_USER_NAME="Build Robot"
    export NAB_GIT_USER_EMAIL="robot@example.com"
    export NAB_COMMIT_MESSAGE="build: refresh dist [skip ci]"
    export GIT_AUTHOR_NAME="Someone Else" GIT_COMMITTER_EMAIL="else@example.com"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format='%an|%ae|%cn|%ce|%s' main)" = "Build Robot|robot@example.com|Build Robot|robot@example.com|build: refresh dist [skip ci]" ]
    not g config --local --get user.name
    not g config --local --get user.email
    not g config --get user.name
}

@test "the repository hooks do not run, a commitlint style hook cannot block the build commit" {
    build
    mkdir -p .git/hooks
    local hook
    for hook in pre-commit commit-msg pre-push post-commit pre-rebase; do
        printf '#!/bin/sh\ntouch "%s/hook-ran-%s"\nexit 1\n' "$BATS_TEST_TMPDIR" "$hook" >".git/hooks/$hook"
        chmod +x ".git/hooks/$hook"
    done
    # A hooks path that a package like husky sets in the local config.
    mkdir -p .husky
    printf '#!/bin/sh\ntouch "%s/hook-ran-husky"\nexit 1\n' "$BATS_TEST_TMPDIR" >.husky/pre-commit
    chmod +x .husky/pre-commit
    g config core.hooksPath .husky
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(output_value commit-sha)" = "$(remote_head)" ]
    not ls "$BATS_TEST_TMPDIR"/hook-ran-* 2>/dev/null
}

@test "a message without [skip ci] is kept as it is and a notice explains the loop risk" {
    build
    export NAB_COMMIT_MESSAGE="chore: update build output"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::notice::The commit message has no [skip ci]"* ]] || return 1
    [[ "$output" == *"personal access token"* ]] || return 1
    [[ "$output" == *"loop"* ]] || return 1
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s main)" = "chore: update build output" ]
}

@test "the default message has [skip ci] and prints no notice" {
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"::notice::"* ]] || return 1
}

@test "the skip marker is found in any case and in the other spellings" {
    local message
    for message in "chore: dist [Skip CI]" "chore: dist [ci skip]" "chore: dist [no ci]" "chore: dist [skip actions]"; do
        run bash -c 'source "$1"; nab_notice_skip_ci "$2"' _ "$SCRIPTS/commit.sh" "$message"
        [ "$status" -eq 0 ]
        [ -z "$output" ] || {
            echo "notice for '$message': $output" >&2
            return 1
        }
    done
    run bash -c 'source "$1"; nab_notice_skip_ci "$2"' _ "$SCRIPTS/commit.sh" "chore: dist"
    [[ "$output" == "::notice::"* ]] || return 1
}

# ---------------------------------------------------------------------------
# Rebase and retry

@test "a push rejected as non-fast-forward is solved by a rebase and a new push" {
    build
    competing_commit "other.txt" "another change"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rebasing onto it and trying again"* ]] || return 1
    [ "$(output_value changed)" = "true" ]
    [ "$(output_value commit-sha)" = "$(remote_head)" ]
    # The competing commit stays, our commit is on top of it. No merge, no force.
    [ "$(g --git-dir="$ORIGIN" log --format=%s main | head -n 3 | paste -sd'|' -)" = "chore: update build output [skip ci]|competing commit|seed" ]
    [ "$(g --git-dir="$ORIGIN" show main:other.txt)" = "another change" ]
    [ "$(g --git-dir="$ORIGIN" show main:dist/out.txt)" = "built by the fixture" ]
    [ "$(push_calls)" -eq 2 ]
    not push_lines_match -- '--force|--force-with-lease| -f | \+' 
}

@test "the rebase keeps unstaged changes of the working tree" {
    build
    printf 'local edit\n' >>README.md
    competing_commit "other.txt" "another change"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(output_value commit-sha)" = "$(remote_head)" ]
    grep -q '^local edit$' README.md
}

@test "a rebase that conflicts is aborted and the step fails clearly" {
    build
    competing_commit "dist/out.txt" "a different build"
    local competing
    competing=$(remote_head)
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The branch 'main' changed while the build ran"* ]] || return 1
    [[ "$output" == *"rebase was aborted"* ]] || return 1
    [[ "$output" == *"concurrency"* ]] || return 1
    # Nothing was pushed, and no rebase is left half done.
    [ "$(remote_head)" = "$competing" ]
    [ ! -d .git/rebase-merge ]
    [ ! -d .git/rebase-apply ]
    [ "$(g symbolic-ref --short HEAD)" = "main" ]
    [ -z "$(output_value changed)" ]
}

@test "a competing run that pushed the same output leaves nothing to push" {
    build
    competing_commit "dist/out.txt" "built by the fixture"
    local competing
    competing=$(remote_head)
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"already holds the same build output"* ]] || return 1
    [ "$(output_value changed)" = "false" ]
    [ -z "$(output_value commit-sha)" ]
    [ "$(remote_head)" = "$competing" ]
}

@test "the push is tried three times at most, then the step fails" {
    build
    # A remote that always says the branch moved.
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "! [remote rejected] main -> main (non-fast-forward)" >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"still rejected after 3 attempts"* ]] || return 1
    [ "$(push_calls)" -eq 3 ]
    not push_lines_match -- '--force|--force-with-lease| -f | \+'
}

@test "a protected branch gives the two options that work and one push attempt" {
    build
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "error: GH006: Protected branch update failed for refs/heads/main. protected branch hook declined" >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The push to 'main' was rejected because the branch is protected"* ]] || return 1
    [[ "$output" == *"personal access token or a GitHub App token"* ]] || return 1
    [[ "$output" == *"mode: pr"* ]] || return 1
    [[ "$output" == *"never force-pushes"* ]] || return 1
    [ "$(push_calls)" -eq 1 ]
    # The push output is printed once.
    [ "$(printf '%s\n' "$output" | grep -c '^\[git\] .*GH006')" -eq 1 ]
}

@test "a refused credential points to permissions and persist-credentials" {
    build
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "remote: Permission to owner/repo.git denied to github-actions[bot]." >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"permissions: contents: write"* ]] || return 1
    [[ "$output" == *"persist-credentials: false"* ]] || return 1
}

@test "git output cannot start a workflow command" {
    build
    cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "::set-output name=x::y" >&2
exit 1
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^::set-output')" -eq 0 ]
    [[ "$output" == *"[git] "* ]] || return 1
}

# ---------------------------------------------------------------------------
# The token

# Where the token may and may not be, after a real run.
@test "the token is in no file of .git, no git config, no output and no step file" {
    build
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]

    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')

    # No file under .git, in the working repository or in the remote.
    not grep -rqF -- "$FAKE_TOKEN" .git
    not grep -rqF -- "$encoded" .git
    not grep -rqF -- "$FAKE_TOKEN" "$ORIGIN"
    # Not in the configuration, local, global or system.
    run g config --list --show-origin
    [[ "$output" != *"$FAKE_TOKEN"* ]] || return 1
    [[ "$output" != *"$encoded"* ]] || return 1
    [[ "$output" != *"extraheader"* ]] || return 1
    run g config --list --global
    [[ "$output" != *"$FAKE_TOKEN"* ]] || return 1
    [[ "$output" != *"extraheader"* ]] || return 1
    # Not in the files that carry values between steps.
    not grep -qF -- "$FAKE_TOKEN" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    not grep -qF -- "$encoded" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    # Not left in the committed build output.
    [ "$(g --git-dir="$ORIGIN" show main:dist/out.txt)" = "built by the fixture" ]
}

@test "the step output never shows the token, only the masks do" {
    build
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')
    # The runner turns these two lines into masks and drops them from the log.
    [ "$(printf '%s\n' "$output" | grep -c '^::add-mask::')" -eq 2 ]
    printf '%s\n' "$output" | grep -qxF "::add-mask::$FAKE_TOKEN"
    printf '%s\n' "$output" | grep -qxF "::add-mask::$encoded"
    # Every other line is clean.
    local visible
    visible=$(visible_output)
    [[ "$visible" != *"$FAKE_TOKEN"* ]] || return 1
    [[ "$visible" != *"$encoded"* ]] || return 1
}

@test "the token is in no git argument, and only fetch and push carry it, in the environment" {
    build
    competing_commit "other.txt" "another change"
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')

    # The argument part of every call (what `ps` would show).
    cut -d'|' -f2 "$SPY_LOG" >"$BATS_TEST_TMPDIR/argv.txt"
    [ -s "$BATS_TEST_TMPDIR/argv.txt" ]
    not grep -qF -- "$FAKE_TOKEN" "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qF -- "$encoded" "$BATS_TEST_TMPDIR/argv.txt"
    not grep -q 'http\.extraheader' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qi 'authorization' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -q 'url\.' "$BATS_TEST_TMPDIR/argv.txt"
    not grep -qF 'x-access-token' "$BATS_TEST_TMPDIR/argv.txt"

    # fetch and push (and only they) get the header, through GIT_CONFIG_*.
    local line
    while IFS= read -r line; do
        case "$line" in
            *"| push "* | *"| fetch "* | *" push "* | *" fetch "*)
                [[ "$line" == *"GIT_CONFIG_KEY_0=http.extraheader;"* && "$line" == *"GIT_CONFIG_VALUE_0=AUTHORIZATION: basic $encoded;"* ]] || {
                    echo "no header on: $line" >&2
                    return 1
                }
                ;;
            *)
                [[ "$line" != *"GIT_CONFIG_"* && "$line" != *"NAB_TOKEN"* ]] || {
                    echo "credential on a local call: $line" >&2
                    return 1
                }
                ;;
        esac
    done <"$SPY_LOG"
    grep -q ' push ' "$SPY_LOG"
    grep -q ' fetch ' "$SPY_LOG"
    # NAB_TOKEN itself reached no git process.
    not grep -q 'NAB_TOKEN' "$SPY_LOG"
}

@test "the build and install steps of the same job never see the token" {
    # The whole job: validate, install, build, then the commit step. The token is in the
    # outer shell the way a workflow could export it, and only the commit step gets NAB_TOKEN.
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
    grep -q '^NAB_COMMAND=build$' install-env.txt
    grep -q '^NAB_COMMAND=build$' dist/build-env.txt
    not grep -q "$FAKE_TOKEN" install-env.txt dist/build-env.txt
    not grep -q 'NAB_TOKEN' install-env.txt dist/build-env.txt

    # Now the commit step, with its own env.
    export NAB_TOKEN=$saved_token
    export NAB_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export NAB_GIT_USER_NAME="github-actions[bot]"
    export NAB_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    # The env dump of the build was committed, and holds no token.
    [ "$(g --git-dir="$ORIGIN" show main:dist/build-env.txt | grep -c "$FAKE_TOKEN" || true)" -eq 0 ]
    [ "$(output_value commit-sha)" = "$(remote_head)" ]
}

@test "nab_build_auth_header masks the token and its base64 form and prints nothing else" {
    local out_file="$BATS_TEST_TMPDIR/header.txt"
    run bash -c 'source "$1"; nab_build_auth_header "$2"; printf "%s" "$NAB_AUTH_HEADER" > "$3"' _ "$SCRIPTS/commit.sh" "$FAKE_TOKEN" "$out_file"
    [ "$status" -eq 0 ]
    local encoded
    encoded=$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')
    [ "$(cat "$out_file")" = "AUTHORIZATION: basic $encoded" ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
    [ "$(printf '%s\n' "$output" | sed -n 1p)" = "::add-mask::$FAKE_TOKEN" ]
    [ "$(printf '%s\n' "$output" | sed -n 2p)" = "::add-mask::$encoded" ]
    [[ "$(visible_output)" == "" ]] || return 1
}

@test "nab_build_auth_header refuses an empty token and a token with a line break" {
    run bash -c 'source "$1"; nab_build_auth_header ""' _ "$SCRIPTS/commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The token is empty"* ]] || return 1
    run bash -c 'source "$1"; nab_build_auth_header "$2"' _ "$SCRIPTS/commit.sh" $'abc\ndef'
    [ "$status" -eq 1 ]
    [[ "$output" == *"line break"* ]] || return 1
    [[ "$output" != *"abc"* ]] || return 1
}

@test "nab_git_remote gives git the header for one command only and keeps other git config variables" {
    local header="AUTHORIZATION: basic Zm9v"
    run bash -c '
        source "$1"
        NAB_HOOKS_DIR=$(mktemp -d)
        NAB_AUTH_HEADER=$2
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=test.kept GIT_CONFIG_VALUE_0=yes
        # Both the old entry and the header are visible to the one command.
        printf "kept=%s\n" "$(nab_git_remote config --get test.kept)"
        printf "header=%s\n" "$(nab_git_remote config --get http.extraheader)"
        # Afterwards the shell has the old environment again.
        printf "count=%s\n" "$GIT_CONFIG_COUNT"
        printf "value0=%s\n" "$GIT_CONFIG_VALUE_0"
        printf "plain=%s\n" "$(git config --get http.extraheader || echo none)"
    ' _ "$SCRIPTS/commit.sh" "$header"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept=yes"* ]] || return 1
    [[ "$output" == *"header=$header"* ]] || return 1
    [[ "$output" == *"count=1"* ]] || return 1
    [[ "$output" == *"value0=yes"* ]] || return 1
    [[ "$output" == *"plain=none"* ]] || return 1
}

@test "persisted checkout credentials are reported by key name, never by value" {
    build
    g config http.https://github.com/.extraheader "AUTHORIZATION: basic cGVyc2lzdGVkLXNlY3JldA=="
    run bash "$SCRIPTS/commit.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::"*"http.https://github.com/.extraheader"*"persist-credentials: false"* ]] || return 1
    [[ "$output" != *"cGVyc2lzdGVkLXNlY3JldA"* ]] || return 1
}

@test "an old git is refused with a clear message" {
    mkdir -p "$BATS_TEST_TMPDIR/old-git"
    printf '#!/bin/sh\necho "git version 2.30.2"\n' >"$BATS_TEST_TMPDIR/old-git/git"
    chmod +x "$BATS_TEST_TMPDIR/old-git/git"
    run bash -c 'PATH="$2:$PATH"; source "$1"; nab_check_git_version' _ "$SCRIPTS/commit.sh" "$BATS_TEST_TMPDIR/old-git"
    [ "$status" -eq 1 ]
    [[ "$output" == *"git 2.30 is too old"* ]] || return 1
}
