#!/usr/bin/env bats
# Input validation: what is accepted, what is rejected, and that no value is ever
# interpreted by a shell.

load helpers

setup() {
    reset_inputs
    default_inputs
    cd "$BATS_TEST_TMPDIR"
}

@test "defaults with mode build are accepted and normalized" {
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ "$(env_value NAB_MODE)" = "build" ]
    [ "$(env_value NAB_WORKDIR)" = "." ]
    [ "$(env_value NAB_COMMAND)" = "build" ]
    [ "$(env_value NAB_PACKAGE_MANAGER)" = "auto" ]
    [ "$(env_value NAB_PATHS)" = "dist" ]
    [ "$(env_value NAB_IGNORE_SCRIPTS)" = "false" ]
    [ "$(output_value node-version)" = "24" ]
}

@test "mode commit fails at once and names issue 3" {
    export INPUT_MODE=commit
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" == *"issue #3"* ]]
    [[ "$output" == *"not available yet"* ]]
    [ ! -s "$GITHUB_ENV" ]
}

@test "mode check fails at once and names issue 4" {
    export INPUT_MODE=check
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" == *"issue #4"* ]]
}

@test "mode pr fails at once and names issue 5" {
    export INPUT_MODE=pr
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" == *"issue #5"* ]]
}

@test "the default mode, commit, is not available yet" {
    unset INPUT_MODE
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue #3"* ]]
}

@test "an unknown mode is rejected" {
    export INPUT_MODE=deploy
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown mode 'deploy'"* ]]
}

@test "paths: several entries, CRLF, indentation and a trailing blank line are normalized" {
    export INPUT_PATHS=$'  dist  \r\nlib/types\r\n\n'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ "$(env_value NAB_PATHS)" = $'dist\nlib/types' ]
}

@test "paths: an entry that starts with a dash is rejected" {
    export INPUT_PATHS=$'dist\n-rf'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not start with '-'"* ]]
}

@test "paths: an entry with .. is rejected" {
    export INPUT_PATHS="dist/../secrets"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not contain '..'"* ]]
}

@test "paths: absolute entries are rejected (unix, backslash and drive letter)" {
    local value
    for value in "/etc/passwd" '\windows\system32' 'C:\temp' 'c:/temp'; do
        export INPUT_PATHS="$value"
        run bash "$SCRIPTS/validate-inputs.sh"
        [ "$status" -eq 1 ]
        [[ "$output" == *"must be a relative path"* ]]
    done
}

@test "paths: an empty value is rejected" {
    export INPUT_PATHS=""
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'paths' is empty"* ]]
}

@test "paths: a blank line between entries is rejected" {
    export INPUT_PATHS=$'dist\n\nbuild'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty entry"* ]]
}

@test "paths: a very long entry is rejected" {
    export INPUT_PATHS="$(head -c 2000 /dev/zero | tr '\0' 'a')"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"too long"* ]]
}

@test "paths: more than 50 entries are rejected" {
    local value="" i
    for i in $(seq 1 51); do
        value+="dir$i"$'\n'
    done
    export INPUT_PATHS="$value"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than 50 entries"* ]]
}

@test "working-directory: .. is rejected" {
    export INPUT_WORKING_DIRECTORY="../other"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"working-directory"* ]]
    [[ "$output" == *"'..'"* ]]
}

@test "working-directory: an absolute path is rejected" {
    export INPUT_WORKING_DIRECTORY="/tmp"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"relative path"* ]]
}

@test "working-directory: an empty value means the workspace root" {
    export INPUT_WORKING_DIRECTORY=""
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ "$(env_value NAB_WORKDIR)" = "." ]
}

@test "values with spaces, quotes, \$() and backticks are kept as literal text" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    export INPUT_COMMAND="build:ci \"x\" 'y' \$(touch $marker) \`touch $marker\` ; touch $marker"
    export INPUT_PATHS="my dist/\$(touch $marker)"$'\n'"it's \"here\""
    export INPUT_COMMIT_MESSAGE="fix: \$(touch $marker) \`touch $marker\`"
    export INPUT_INSTALL_COMMAND="npm ci && echo \"\$(touch $marker)\""
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
    [ "$(env_value NAB_COMMAND)" = "$INPUT_COMMAND" ]
    [ "$(env_value NAB_PATHS)" = "$INPUT_PATHS" ]
    [ "$(env_value NAB_INSTALL_COMMAND)" = "$INPUT_INSTALL_COMMAND" ]
}

@test "a value cannot forge a second GITHUB_ENV entry" {
    export INPUT_COMMAND="build"
    export INPUT_INSTALL_COMMAND="npm ci"$'\n'"NAB_MODE=evil"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"single line"* ]]
    [ ! -s "$GITHUB_ENV" ]
}

@test "a newline in a single line input is rejected, for each input" {
    local name
    for name in INPUT_COMMAND INPUT_INSTALL_COMMAND INPUT_WORKING_DIRECTORY INPUT_PACKAGE_MANAGER \
        INPUT_NODE_VERSION INPUT_NODE_VERSION_FILE INPUT_GIT_USER_NAME INPUT_GIT_USER_EMAIL \
        INPUT_BRANCH INPUT_PR_TITLE INPUT_PR_LABELS INPUT_COMMIT_MESSAGE; do
        reset_inputs
        default_inputs
        export "$name=first"$'\n'"second"
        run bash "$SCRIPTS/validate-inputs.sh"
        [ "$status" -eq 1 ] || {
            echo "$name accepted a newline" >&2
            return 1
        }
        [[ "$output" == *"single line"* ]]
    done
}

@test "a carriage return in a single line input is rejected" {
    export INPUT_COMMAND=$'build\rx'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"single line"* ]]
}

@test "a very long value is rejected" {
    export INPUT_COMMAND="$(head -c 5000 /dev/zero | tr '\0' 'a')"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"too long"* ]]
}

@test "a command that starts with a dash is rejected" {
    export INPUT_COMMAND="--version"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not start with '-'"* ]]
}

@test "an error message cannot carry a workflow command from a value" {
    export INPUT_MODE=$'build\n::set-output name=x::y'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    # The only line that starts with :: is our own, and the value sits on that line.
    [ "$(printf '%s\n' "$output" | grep -c '^::')" -eq 1 ]
    [[ "$output" == *"%0A"* ]]
}

@test "booleans must be true or false, in any case" {
    export INPUT_IGNORE_SCRIPTS=TRUE
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ "$(env_value NAB_IGNORE_SCRIPTS)" = "true" ]

    export INPUT_IGNORE_SCRIPTS=yes
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'ignore-scripts' must be 'true' or 'false'"* ]]
}

@test "an unsupported package manager is rejected" {
    export INPUT_PACKAGE_MANAGER=bun
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not supported"* ]]
}

@test "node-version-file wins over node-version" {
    export INPUT_NODE_VERSION_FILE=".nvmrc"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    grep -q "^node-version=$" "$GITHUB_OUTPUT"
}

@test "node-version-file must stay inside the workspace" {
    export INPUT_NODE_VERSION_FILE="../.nvmrc"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"node-version-file"* ]]
}

@test "node-version accepts the usual specs and rejects shell characters" {
    local ok
    for ok in 24 22.x v20.11.1 'lts/*' '>=20' '^22.1'; do
        export INPUT_NODE_VERSION="$ok"
        run bash "$SCRIPTS/validate-inputs.sh"
        [ "$status" -eq 0 ] || {
            echo "rejected $ok" >&2
            return 1
        }
    done
    export INPUT_NODE_VERSION='24; touch x'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not allowed in a version"* ]]
}

@test "an empty command is rejected" {
    export INPUT_COMMAND=""
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'command' is empty"* ]]
}
