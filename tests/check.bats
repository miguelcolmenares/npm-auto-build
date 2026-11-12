#!/usr/bin/env bats
# Mode check: scripts/check.sh compares the build output with HEAD. Every test builds
# a throwaway git repository, so nothing here needs the network or a GitHub runner.

load helpers

ACTION="$BATS_TEST_DIRNAME/../action.yml"

setup() {
    reset_inputs
    # A repository of its own, and no git configuration of the person who runs the
    # tests (a global core.autocrlf would change the line ending tests).
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner"
    mkdir -p "$RUNNER_TEMP"
    export NAB_PATHS=dist
    export NAB_COMMAND=build
    DIFF_DIR="$RUNNER_TEMP/nab-check"
    make_repo
}

# A repository with a committed, fresh dist/ and the current directory inside it.
make_repo() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/dist"
    cd "$REPO"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git config core.autocrlf false
    printf '{"name":"x","scripts":{"build":"true"}}\n' >package.json
    printf 'built by the fixture\n' >dist/out.txt
    printf 'console.log(1);\n' >dist/app.js
    git add -A
    git commit -q -m "initial build"
}

# The messages end with the list of files, so a test can look at the whole output.
run_check() {
    run bash "$SCRIPTS/check.sh"
}

@test "a fresh build gives stale=false and exit 0" {
    run_check
    [ "$status" -eq 0 ]
    [ "$(output_value stale)" = "false" ]
    [[ "$output" != *"::error::"* ]]
}

@test "a stale tracked file gives stale=true, exit 1, the file and the fix command" {
    printf 'a different build\n' >dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [ "$(output_value stale)" = "true" ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" == *"modified: dist/out.txt"* ]]
    # The fresh file is not named.
    [[ "$output" != *"dist/app.js"* ]]
    [[ "$output" == *"working directory '.'"* ]]
    [[ "$output" == *"run 'npm run build' in '.'"* ]]
    [[ "$output" == *"commit the changed paths (dist)"* ]]
}

@test "the error is one workflow command, the lines are escaped" {
    printf 'a different build\n' >dist/out.txt
    printf 'new\n' >dist/new.txt
    run_check
    [ "$(printf '%s\n' "$output" | grep -c '^::error::')" -eq 1 ]
    [[ "$output" == *"%0A"* ]]
}

@test "a new untracked output file is stale" {
    printf 'new chunk\n' >dist/chunk.js
    run_check
    [ "$status" -eq 1 ]
    [ "$(output_value stale)" = "true" ]
    [[ "$output" == *"untracked: dist/chunk.js"* ]]
}

@test "a deleted tracked file is stale" {
    rm dist/app.js
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"deleted: dist/app.js"* ]]
}

@test "a path that the build removed completely is stale, not an error about a missing path" {
    rm -r dist
    run_check
    [ "$status" -eq 1 ]
    [ "$(output_value stale)" = "true" ]
    [[ "$output" == *"deleted: dist/out.txt"* ]]
    [[ "$output" == *"deleted: dist/app.js"* ]]
}

@test "a change that is staged but not committed is stale, HEAD is what counts" {
    printf 'a different build\n' >dist/out.txt
    git add dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: dist/out.txt"* ]]
}

@test "an untracked output that .gitignore ignores is stale and the message says how to add it" {
    printf 'dist/*.map\n' >.gitignore
    git add .gitignore
    git commit -q -m "ignore maps"
    printf '{}\n' >dist/app.js.map
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"ignored: dist/app.js.map"* ]]
    [[ "$output" == *"git add --force"* ]]
}

@test "a build directory that is ignored and was never committed is stale" {
    # The common mistake: dist/ is in .gitignore, so the "committed build" is nothing.
    git rm -r -q --cached dist
    printf 'dist/\n' >.gitignore
    git add .gitignore
    git commit -q -m "stop tracking dist"
    run_check
    [ "$status" -eq 1 ]
    [ "$(output_value stale)" = "true" ]
    [[ "$output" == *"ignored: dist/out.txt"* ]]
    [[ "$output" == *"ignored: dist/app.js"* ]]
}

@test "a line ending difference alone is not stale, for every autocrlf setting" {
    local setting
    for setting in false input true; do
        git config core.autocrlf "$setting"
        printf 'built by the fixture\r\n' >dist/out.txt
        printf 'console.log(1);\r\n' >dist/app.js
        run bash "$SCRIPTS/check.sh"
        [ "$status" -eq 0 ] || {
            echo "autocrlf=$setting: $output" >&2
            return 1
        }
        [ "$(output_value stale | tail -n 1)" = "false" ]
    done
}

@test "a CRLF file that also has a real change is stale" {
    printf 'built by the fixture, changed\r\n' >dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: dist/out.txt"* ]]
}

@test "a change in trailing spaces is stale: only the carriage return is ignored" {
    printf 'built by the fixture  \n' >dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: dist/out.txt"* ]]
}

@test "more than 50 files are capped in the message, files.txt keeps all of them" {
    local i
    for i in $(seq 1 60); do
        printf 'chunk %s\n' "$i" >"dist/chunk-$i.js"
    done
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"60 file(s) differ"* ]]
    [[ "$output" == *"and 10 more"* ]]
    [ "$(printf '%s\n' "$output" | grep -o 'untracked: dist/chunk-' | wc -l | tr -d ' ')" -eq 50 ]
    [ "$(wc -l <"$DIFF_DIR/files.txt" | tr -d ' ')" -eq 60 ]
}

@test "exactly 50 files are listed without an and-more line" {
    local i
    for i in $(seq 1 50); do
        printf 'chunk %s\n' "$i" >"dist/chunk-$i.js"
    done
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" != *"more"* ]]
}

@test "the diff and the file list are written to RUNNER_TEMP/nab-check" {
    printf 'a different build\n' >dist/out.txt
    printf 'new chunk\n' >dist/chunk.js
    rm dist/app.js
    run_check
    [ "$status" -eq 1 ]
    [ "$(cat "$DIFF_DIR/files.txt")" = $'dist/app.js\ndist/chunk.js\ndist/out.txt' ]
    grep -q '^diff --git a/dist/out.txt b/dist/out.txt$' "$DIFF_DIR/diff.patch"
    grep -q '^+a different build$' "$DIFF_DIR/diff.patch"
    grep -q '^deleted file mode' "$DIFF_DIR/diff.patch"
    # A new file shows in the patch too, even though git does not track it.
    grep -q '^+new chunk$' "$DIFF_DIR/diff.patch"
}

@test "the diff of a CRLF-only file is not in the patch" {
    printf 'built by the fixture\r\n' >dist/out.txt
    printf 'a different build\n' >dist/app.js
    run_check
    [ "$status" -eq 1 ]
    ! grep -q 'dist/out.txt' "$DIFF_DIR/diff.patch"
    ! grep -q 'dist/out.txt' "$DIFF_DIR/files.txt"
}

@test "files from an earlier run are removed, a fresh run leaves the directory empty" {
    mkdir -p "$DIFF_DIR"
    printf 'old\n' >"$DIFF_DIR/files.txt"
    printf 'old\n' >"$DIFF_DIR/other.txt"
    run_check
    [ "$status" -eq 0 ]
    [ ! -e "$DIFF_DIR/files.txt" ]
    [ ! -e "$DIFF_DIR/other.txt" ]
}

@test "the check leaves the repository as it was" {
    printf 'a different build\n' >dist/out.txt
    printf 'new chunk\n' >dist/chunk.js
    git status --porcelain >"$BATS_TEST_TMPDIR/before"
    cp .git/index "$BATS_TEST_TMPDIR/index-before"
    run_check
    [ "$status" -eq 1 ]
    git status --porcelain >"$BATS_TEST_TMPDIR/after"
    diff "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/after"
    cmp .git/index "$BATS_TEST_TMPDIR/index-before"
    [ "$(git ls-files | wc -l | tr -d ' ')" -eq 3 ]
}

@test "several paths: one stale path makes the check stale, the message names the fix paths" {
    mkdir -p lib
    printf 'x\n' >lib/types.d.ts
    git add lib
    git commit -q -m "types"
    printf 'y\n' >lib/types.d.ts
    export NAB_PATHS=$'dist\nlib'
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: lib/types.d.ts"* ]]
    [[ "$output" != *"dist/out.txt"* ]]
    [[ "$output" == *"(dist, lib)"* ]]
}

@test "a single file path works as well as a directory" {
    export NAB_PATHS=dist/out.txt
    run_check
    [ "$status" -eq 0 ]
    printf 'x\n' >dist/out.txt
    printf 'y\n' >dist/app.js
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"dist/out.txt"* ]]
    [[ "$output" != *"dist/app.js"* ]]
}

@test "a working directory inside the repository: files are named from the repository root" {
    mkdir -p app/dist
    printf 'one\n' >app/dist/out.txt
    git add app
    git commit -q -m "app"
    printf 'two\n' >app/dist/out.txt
    export NAB_WORKDIR=app
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: app/dist/out.txt"* ]]
    [[ "$output" == *"working directory 'app'"* ]]
    [[ "$output" == *"run 'npm run build' in 'app'"* ]]
}

@test "the fix command follows the lockfile and the command name" {
    : >yarn.lock
    git add yarn.lock
    git commit -q -m "yarn"
    printf 'x\n' >dist/out.txt
    export NAB_COMMAND=compile
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"run 'yarn run compile'"* ]]
}

@test "a path that leaves the repository is refused" {
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
    export NAB_PATHS=../elsewhere
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" == *"outside the repository"* ]]
    [ -z "$(output_value stale)" ]
}

@test "a path that leaves the repository from a working directory is refused" {
    mkdir -p app
    export NAB_WORKDIR=app
    export NAB_PATHS=../../repo-sibling
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"outside the repository"* ]]
}

@test "a path that goes up and stays inside the repository is accepted" {
    mkdir -p app
    export NAB_WORKDIR=app
    export NAB_PATHS=../dist
    run_check
    [ "$status" -eq 0 ]
    [ "$(output_value stale)" = "false" ]
}

@test "a symbolic link that leads out of the repository is refused" {
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere/deep"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" linked
    export NAB_PATHS=linked
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"outside the repository"* ]]
    export NAB_PATHS=linked/deep
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"outside the repository"* ]]
}

@test "an absolute path and an option-like path are refused" {
    export NAB_PATHS=/etc
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"relative"* ]]
    export NAB_PATHS=--stat
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not start with '-'"* ]]
}

@test "a path that does not exist and is not in HEAD is an error, not stale" {
    export NAB_PATHS=build
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"path 'build' does not exist"* ]]
    [ -z "$(output_value stale)" ]
}

@test "a path with glob characters is a name, not a pattern" {
    printf 'x\n' >'dist/[a].js'
    export NAB_PATHS='dist/*'
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "outside a git work tree it fails with a clear message" {
    mkdir -p "$BATS_TEST_TMPDIR/plain/dist"
    cd "$BATS_TEST_TMPDIR/plain"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"not inside a git work tree"* ]]
}

@test "a repository without a commit fails with a clear message" {
    mkdir -p "$BATS_TEST_TMPDIR/empty/dist"
    cd "$BATS_TEST_TMPDIR/empty"
    git init -q .
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"no commit yet"* ]]
}

@test "no token variable is needed: the check passes and fails with none in the environment" {
    run env -i PATH="$PATH" HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        NAB_PATHS=dist RUNNER_TEMP="$RUNNER_TEMP" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPTS/check.sh"
    [ "$status" -eq 0 ]
    [ "$(output_value stale)" = "false" ]
    printf 'x\n' >dist/out.txt
    run env -i PATH="$PATH" HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        NAB_PATHS=dist RUNNER_TEMP="$RUNNER_TEMP" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPTS/check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: dist/out.txt"* ]]
}

@test "no token is read: a token in the environment never reaches the output or the files" {
    export GITHUB_TOKEN="$FAKE_TOKEN" GH_TOKEN="$FAKE_TOKEN" INPUT_TOKEN="$FAKE_TOKEN"
    export INPUT_GITHUB_TOKEN="$FAKE_TOKEN" ACTIONS_RUNTIME_TOKEN="$FAKE_TOKEN"
    printf 'x\n' >dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" != *"$FAKE_TOKEN"* ]]
    ! grep -rq "$FAKE_TOKEN" "$DIFF_DIR" "$GITHUB_OUTPUT"
}

@test "the script and the check steps of the action name no token" {
    run grep -nE 'GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|secrets\.' "$SCRIPTS/check.sh"
    [ "$status" -eq 1 ]
    local steps
    steps=$(awk '/- name: Check the build output/ {on=1} /^branding:/ {on=0} on' "$ACTION")
    # The awk range holds both check steps, so an empty range cannot pass.
    [[ "$steps" == *"scripts/check.sh"* ]]
    [[ "$steps" == *"upload-artifact"* ]]
    ! grep -Eq 'inputs\.(github-)?token|github\.token|secrets\.|GITHUB_TOKEN|GH_TOKEN' <<<"$steps"
}

@test "standalone: without GITHUB_OUTPUT and RUNNER_TEMP it prints the result" {
    unset GITHUB_OUTPUT RUNNER_TEMP
    run_check
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^stale=false$')" -eq 1 ]

    printf 'x\n' >dist/out.txt
    run_check
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^stale=true$')" -eq 1 ]
    # The diff went to a temporary directory outside the repository.
    local dir
    dir=$(printf '%s\n' "$output" | sed -n 's|^\[INFO\] The diff is in \(.*\)/diff.patch and.*|\1|p')
    [ -f "$dir/diff.patch" ]
    [[ "$dir" != "$REPO"* ]]
    rm -rf "$dir"
}

@test "on GitHub the output goes to GITHUB_OUTPUT and not to standard output" {
    run_check
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^stale=')" -eq 0 ]
    [ "$(output_value stale)" = "false" ]
}

@test "the check follows the build of the action: validate, build and check on the fixture" {
    # A real run of the scripts the action calls, in a repository with a committed dist.
    make_workspace
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git config core.autocrlf false
    node build.js
    git add -f dist package.json build.js
    git commit -q -m "fixture with a committed build"

    default_inputs
    export INPUT_MODE=check
    unset NAB_PATHS NAB_COMMAND
    validate_and_load
    [ "$(output_value mode)" = "check" ]
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/check.sh"
    [ "$status" -eq 0 ]
    [ "$(output_value stale | tail -n 1)" = "false" ]

    # The source changes and the build output is not committed again.
    sed -i.bak 's/built by the fixture/built by a new version/' build.js
    rm build.js.bak
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified: dist/out.txt"* ]]
    [[ "$output" == *"run 'npm run build'"* ]]
}

@test "action.yml: the check step runs only in mode check, after the build, and stale points to it" {
    grep -q "if: steps.validate.outputs.mode == 'check'" "$ACTION"
    grep -q 'run: bash "\$ACTION_PATH/scripts/check.sh"' "$ACTION"
    local build_line check_line
    build_line=$(grep -n 'scripts/build.sh' "$ACTION" | head -n 1 | cut -d: -f1)
    check_line=$(grep -n 'scripts/check.sh' "$ACTION" | head -n 1 | cut -d: -f1)
    [ "$check_line" -gt "$build_line" ]
    grep -A3 '^  stale:$' "$ACTION" | grep -q 'value: \${{ steps.check.outputs.stale }}'
}

@test "action.yml: the diff upload is pinned, runs after a failed check and keeps the diff 7 days" {
    local step
    step=$(awk '/- name: Upload the diff/ {on=1} /^branding:/ {on=0} on' "$ACTION")
    [[ "$step" == *"if: always() && steps.validate.outputs.mode == 'check' && inputs.upload-diff == 'true' && steps.check.outputs.stale == 'true'"* ]]
    [[ "$step" == *"uses: actions/upload-artifact@"* ]]
    grep -Eq 'uses: actions/upload-artifact@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$step"
    [[ "$step" == *"name: npm-auto-build-stale-diff"* ]]
    [[ "$step" == *"path: \${{ runner.temp }}/nab-check"* ]]
    [[ "$step" == *"if-no-files-found: ignore"* ]]
    [[ "$step" == *"retention-days: 7"* ]]
}
