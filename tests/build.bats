#!/usr/bin/env bats
# Build step, with the real npm and the fixture project.

load helpers

setup() {
    reset_inputs
    default_inputs
    make_workspace
}

@test "the fixture builds and writes dist/out.txt" {
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    [ "$(cat dist/out.txt)" = "built by the fixture" ]
    [[ "$output" == *"Build finished, every path exists"* ]]
}

@test "the build runs in working-directory" {
    rm -rf "$WORKSPACE"
    make_workspace packages/app
    export INPUT_WORKING_DIRECTORY=packages/app
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
    [ -f packages/app/dist/out.txt ]
    [ ! -e dist ]
}

@test "a path missing after the build is an error that lists it" {
    export INPUT_PATHS=$'dist\nbuild\nlib/types'
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::The build finished but these paths do not exist"* ]]
    [[ "$output" == *"'build', 'lib/types'. Fix 'paths'"* ]]
    # dist exists, so it must not be listed as missing.
    [[ "$output" != *"'dist'"* ]]
}

@test "there is no directory guessing: a build in another directory does not count" {
    # The build writes to build/, but paths asks for dist.
    printf '%s\n' '{"name":"x","version":"1.0.0","scripts":{"build":"node -e \"require(\\\"fs\\\").mkdirSync(\\\"build\\\");\""}}' >package.json
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [ -d build ]
    [[ "$output" == *"do not exist"*"'dist'"* ]]
}

@test "an unknown script lists the scripts that exist" {
    export INPUT_COMMAND=compile
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::Script 'compile' is not defined in package.json"* ]]
    [[ "$output" == *"  build"* ]]
}

@test "a command with shell syntax is never executed" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    export INPUT_COMMAND="build; touch $marker \$(touch $marker)"
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [ ! -e "$marker" ]
    [[ "$output" == *"is not defined in package.json"* ]]
}

@test "a path with shell syntax is only checked as a name" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    export INPUT_PATHS=$'dist\n$(touch '"$marker"$')'
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [ ! -e "$marker" ]
}

@test "a path with a space works" {
    printf '%s\n' '{"name":"x","version":"1.0.0","scripts":{"build":"node -e \"require(\\\"fs\\\").mkdirSync(\\\"my dist\\\");\""}}' >package.json
    export INPUT_PATHS="my dist"
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]
}

@test "a failing build script fails the step and skips the path check" {
    printf '%s\n' '{"name":"x","version":"1.0.0","scripts":{"build":"node -e \"process.exit(3)\""}}' >package.json
    validate_and_load
    run bash "$SCRIPTS/build.sh"
    [ "$status" -ne 0 ]
    [[ "$output" != *"these paths do not exist"* ]]
}

@test "build.sh refuses to run without validated paths" {
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"run validate-inputs.sh first"* ]]
}
