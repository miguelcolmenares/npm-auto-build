#!/usr/bin/env bats
# v2 alias inputs: accepted, mapped to the v3 input, and a warning names the new input.

load helpers

setup() {
    reset_inputs
    default_inputs
    cd "$BATS_TEST_TMPDIR"
}

@test "build-only true maps to mode build and warns" {
    export INPUT_MODE=commit
    export INPUT_BUILD_ONLY=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Input 'build-only' is a v2 name. Use 'mode: build' instead."* ]]
    [ "$(env_value NAB_MODE)" = "build" ]
}

@test "build-only false only warns, the mode stays" {
    export INPUT_MODE=commit
    export INPUT_BUILD_ONLY=false
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::warning::Input 'build-only' is a v2 name"* ]]
    [[ "$output" == *"issue #3"* ]]
}

@test "build-only with an invalid value is rejected" {
    export INPUT_BUILD_ONLY=maybe
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'build-only' must be 'true' or 'false'"* ]]
}

@test "directory maps to working-directory and warns" {
    export INPUT_DIRECTORY="packages/app"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Input 'directory' is a v2 name. Use 'working-directory' instead."* ]]
    [ "$(env_value NAB_WORKDIR)" = "packages/app" ]
}

@test "the alias directory is validated like working-directory" {
    export INPUT_DIRECTORY="../up"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not contain '..'"* ]]
}

@test "working-directory wins over directory" {
    export INPUT_WORKING_DIRECTORY="new"
    export INPUT_DIRECTORY="old"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"'directory' is ignored because 'working-directory' is already set"* ]]
    [ "$(env_value NAB_WORKDIR)" = "new" ]
}

@test "build-dir maps to paths and warns" {
    export INPUT_BUILD_DIR="build"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Input 'build-dir' is a v2 name. Use 'paths' instead."* ]]
    [ "$(env_value NAB_PATHS)" = "build" ]
}

@test "the alias build-dir is validated like paths" {
    export INPUT_BUILD_DIR="-rf"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not start with '-'"* ]]
}

@test "paths wins over build-dir" {
    export INPUT_PATHS="lib"
    export INPUT_BUILD_DIR="build"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"'build-dir' is ignored because 'paths' is already set"* ]]
    [ "$(env_value NAB_PATHS)" = "lib" ]
}

@test "github-token warns and names token, without needing its value" {
    export INPUT_GITHUB_TOKEN_SET=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Input 'github-token' is a v2 name. Use 'token' instead."* ]]
}

@test "create-pr true maps to mode pr, which is not available yet" {
    export INPUT_MODE=commit
    export INPUT_CREATE_PR=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::warning::Input 'create-pr' is a v2 name. Use 'mode: pr' instead."* ]]
    [[ "$output" == *"mode 'pr' is implemented by issue #5"* ]]
}

@test "build-only wins over create-pr, like in v2" {
    export INPUT_MODE=commit
    export INPUT_BUILD_ONLY=true
    export INPUT_CREATE_PR=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"'create-pr' is ignored because 'mode' is already 'build'"* ]]
    [ "$(env_value NAB_MODE)" = "build" ]
}

@test "an explicit mode wins over build-only" {
    export INPUT_MODE=check
    export INPUT_BUILD_ONLY=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'build-only' is ignored because 'mode' is already 'check'"* ]]
    [[ "$output" == *"issue #4"* ]]
}

@test "a v2 style workflow still builds: build-only, directory and build-dir together" {
    export INPUT_MODE=commit
    export INPUT_BUILD_ONLY=true
    export INPUT_DIRECTORY=app
    export INPUT_BUILD_DIR=out
    export INPUT_GITHUB_TOKEN_SET=true
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^::warning::')" -eq 4 ]
    [ "$(env_value NAB_MODE)" = "build" ]
    [ "$(env_value NAB_WORKDIR)" = "app" ]
    [ "$(env_value NAB_PATHS)" = "out" ]
}
