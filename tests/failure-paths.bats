#!/usr/bin/env bats
# Gaps found in the review for issue 11. The input and failure cases that validate-inputs,
# commit, check, build and install bats files already hold are not repeated here. Every
# test here was seen failing against a script that breaks its rule.
#
# Git runs against a local bare repository used as `origin` (a file:// URL), so nothing
# here needs the network or a GitHub runner.

load helpers

ACTION="$BATS_TEST_DIRNAME/../action.yml"

# In a bats test a bare `! cmd` never fails the test on bash 3.2. `not` does.
not() {
    if "$@"; then
        return 1
    fi
}

g() {
    "$REAL_GIT" "$@"
}

setup() {
    reset_inputs
    default_inputs

    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_COUNT
    unset GITHUB_REF GITHUB_REF_NAME GITHUB_REF_TYPE GITHUB_HEAD_REF GITHUB_BASE_REF GITHUB_EVENT_NAME
    REAL_GIT="$(command -v git)"

    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    g init -q --bare -b main "$ORIGIN"
    # A pre-receive hook that records every push that reaches the remote, so a test can
    # prove that no push was tried.
    PUSH_LOG="$BATS_TEST_TMPDIR/pushes.log"
    : >"$PUSH_LOG"
    cat >"$ORIGIN/hooks/pre-receive" <<HOOK
#!/bin/sh
cat >> "$PUSH_LOG"
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"

    local seed="$BATS_TEST_TMPDIR/seed"
    mkdir -p "$seed"
    printf 'readme\n' >"$seed/README.md"
    printf '{"name":"x","scripts":{"build":"true"}}\n' >"$seed/package.json"
    g -C "$seed" init -q -b main
    g -C "$seed" add -A
    g -C "$seed" -c user.name=Seed -c user.email=seed@example.com commit -q -m "seed"
    g -C "$seed" push -q "file://$ORIGIN" main
    : >"$PUSH_LOG"
}

# A clone of origin in a directory of its own.
clone_to() {
    g clone -q "file://$ORIGIN" "$1"
}

# The variables the commit step has when the composite action runs it.
commit_env() {
    export NAB_MODE=commit
    export NAB_WORKDIR=.
    export NAB_PATHS=${1:-dist}
    export NAB_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export NAB_GIT_USER_NAME="github-actions[bot]"
    export NAB_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    export NAB_TOKEN="$FAKE_TOKEN"
}

remote_head() {
    g --git-dir="$ORIGIN" rev-parse main
}

# ---------------------------------------------------------------------------
# Input validation

@test "a very long value is rejected for every single line input, not only for command" {
    local name
    for name in INPUT_INSTALL_COMMAND INPUT_WORKING_DIRECTORY INPUT_NODE_VERSION \
        INPUT_NODE_VERSION_FILE INPUT_GIT_USER_NAME INPUT_GIT_USER_EMAIL INPUT_BRANCH \
        INPUT_PR_TITLE INPUT_PR_LABELS INPUT_COMMIT_MESSAGE INPUT_PACKAGE_MANAGER; do
        reset_inputs
        default_inputs
        export "$name=$(head -c 5000 /dev/zero | tr '\0' 'a')"
        run bash "$SCRIPTS/validate-inputs.sh"
        [ "$status" -eq 1 ] || {
            echo "$name accepted 5000 characters" >&2
            return 1
        }
        [[ "$output" == *"too long"* ]] || {
            echo "$name was refused for another reason: $output" >&2
            return 1
        }
    done
}

@test "the length limit is 1024 characters: 1024 is accepted and 1025 is refused" {
    export INPUT_COMMIT_MESSAGE="$(head -c 1024 /dev/zero | tr '\0' 'a')"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    export INPUT_COMMIT_MESSAGE="$(head -c 1025 /dev/zero | tr '\0' 'a')"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"too long"* ]] || false
}

@test "a working-directory that starts with a dash is a folder name, not an option" {
    mkdir -p "$BATS_TEST_TMPDIR/ws/-app"
    cp "$FIXTURE/package.json" "$FIXTURE/package-lock.json" "$FIXTURE/build.js" "$BATS_TEST_TMPDIR/ws/-app/"
    cd "$BATS_TEST_TMPDIR/ws"
    export INPUT_WORKING_DIRECTORY=-app
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/build.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ -f "-app/dist/out.txt" ]
}

@test "a commit message and a git user name that start with a dash are text, not git options" {
    clone_to "$BATS_TEST_TMPDIR/work"
    cd "$BATS_TEST_TMPDIR/work"
    mkdir dist
    printf 'one\n' >dist/out.txt
    commit_env
    export NAB_COMMIT_MESSAGE="--amend -n [skip ci]"
    export NAB_GIT_USER_NAME="--help"
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%s main)" = "--amend -n [skip ci]" ]
    [ "$(g --git-dir="$ORIGIN" log -1 --format=%an main)" = "--help" ]
    [ "$(g --git-dir="$ORIGIN" rev-list --count main)" -eq 2 ]
}

# ---------------------------------------------------------------------------
# A fork pull request

@test "a fork pull request in mode commit is refused before any push" {
    # The runner checks out refs/pull/N/merge, a detached merge commit, and a fork gets
    # a read-only token. The step must stop on the detached HEAD, before it tries the push.
    clone_to "$BATS_TEST_TMPDIR/work"
    cd "$BATS_TEST_TMPDIR/work"
    g checkout -q --detach
    g -c user.name=Fork -c user.email=fork@example.com commit -q --allow-empty -m "merge of the pull request"
    mkdir dist
    printf 'one\n' >dist/out.txt
    commit_env
    export GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge GITHUB_REF_TYPE=branch
    run bash "$SCRIPTS/commit.sh"
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"HEAD is detached"* ]] || false
    [ ! -s "$PUSH_LOG" ]
    [ -z "$(output_value changed)" ]
    [[ "$output" != *"$FAKE_TOKEN"* ]] || false
}

@test "a fork pull request in mode check needs no token and pushes nothing" {
    clone_to "$BATS_TEST_TMPDIR/work"
    cd "$BATS_TEST_TMPDIR/work"
    mkdir dist
    printf 'built\n' >dist/out.txt
    g add -A
    g add -f dist
    g -c user.name=Fork -c user.email=fork@example.com commit -q -m "fork commit with its build"
    g checkout -q --detach
    export GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge GITHUB_REF_TYPE=branch
    export NAB_PATHS=dist NAB_COMMAND=build
    run bash "$SCRIPTS/check.sh"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ "$(output_value stale)" = "false" ]
    printf 'changed\n' >dist/out.txt
    run bash "$SCRIPTS/check.sh"
    [ "$status" -eq 1 ]
    [ ! -s "$PUSH_LOG" ]
}

# ---------------------------------------------------------------------------
# Failure paths

@test "no step on the build path has always(), failure() or cancelled(), so a failed build never reaches the Commit step" {
    # A failed install or build must stop the job before the token is used. A condition
    # with always() would run the commit step anyway. Only the diff upload may use it.
    local step cond
    for step in Validate Install Build "Check the build output" Commit; do
        cond=$(awk -v name="    - name: $step" '
            $0 ~ /^    - name:/ { inside = ($0 == name); next }
            inside && /^      if:/ { print }
        ' "$ACTION")
        case "$cond" in
            *always\(\)* | *failure\(\)* | *cancelled\(\)*)
                echo "the step '$step' has a condition that runs it after a failure: $cond" >&2
                return 1
                ;;
        esac
    done
}

@test "two runs at the same time on one branch both succeed and both commits reach the remote" {
    # Two clones of the same branch, each with its own build output. The runs start at the
    # same moment. One push wins, the other is rejected, rebases and pushes again.
    clone_to "$BATS_TEST_TMPDIR/run-a"
    clone_to "$BATS_TEST_TMPDIR/run-b"
    mkdir "$BATS_TEST_TMPDIR/run-a/dist-a" "$BATS_TEST_TMPDIR/run-b/dist-b"
    printf 'a\n' >"$BATS_TEST_TMPDIR/run-a/dist-a/out.txt"
    printf 'b\n' >"$BATS_TEST_TMPDIR/run-b/dist-b/out.txt"
    commit_env
    (
        cd "$BATS_TEST_TMPDIR/run-a"
        export NAB_PATHS=dist-a GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out-a"
        bash "$SCRIPTS/commit.sh" >"$BATS_TEST_TMPDIR/log-a" 2>&1
    ) &
    local pid_a=$!
    (
        cd "$BATS_TEST_TMPDIR/run-b"
        export NAB_PATHS=dist-b GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out-b"
        bash "$SCRIPTS/commit.sh" >"$BATS_TEST_TMPDIR/log-b" 2>&1
    ) &
    local pid_b=$!
    local status_a=0 status_b=0
    wait "$pid_a" || status_a=$?
    wait "$pid_b" || status_b=$?
    cat "$BATS_TEST_TMPDIR/log-a" "$BATS_TEST_TMPDIR/log-b" >&2
    [ "$status_a" -eq 0 ]
    [ "$status_b" -eq 0 ]
    [ "$(g --git-dir="$ORIGIN" show main:dist-a/out.txt)" = "a" ]
    [ "$(g --git-dir="$ORIGIN" show main:dist-b/out.txt)" = "b" ]
    # A straight line of history, the seed and one commit per run, no merge and no force.
    [ "$(g --git-dir="$ORIGIN" rev-list --count main)" -eq 3 ]
    [ "$(g --git-dir="$ORIGIN" rev-list --merges --count main)" -eq 0 ]
}
