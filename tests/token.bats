#!/usr/bin/env bats
# The write token must never reach install or build code. The token is set only in
# the outer shell here, the way a workflow could export it, and the install and build
# scripts print their own environment.

load helpers

setup() {
    reset_inputs
    default_inputs
    make_workspace
    export GITHUB_TOKEN="$FAKE_TOKEN"
    export GH_TOKEN="$FAKE_TOKEN"
    export INPUT_TOKEN="$FAKE_TOKEN"
    export INPUT_GITHUB_TOKEN="$FAKE_TOKEN"
    export ACTIONS_RUNTIME_TOKEN="$FAKE_TOKEN"
}

@test "control: the token is visible when nothing removes it" {
    # Proves the next tests can fail: a plain env sees every variable above.
    run env
    [[ "$output" == *"$FAKE_TOKEN"* ]]
}

@test "the install lifecycle script and the build script cannot see the token" {
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
    # No lockfile, so the step runs npm install and its root lifecycle scripts.
    rm -f package-lock.json
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS/build.sh"
    [ "$status" -eq 0 ]

    # Both files exist and hold a real environment, so an empty file cannot pass.
    grep -q '^NAB_COMMAND=build$' install-env.txt
    grep -q '^NAB_COMMAND=build$' dist/build-env.txt
    ! grep -q "$FAKE_TOKEN" install-env.txt
    ! grep -q "$FAKE_TOKEN" dist/build-env.txt
    ! grep -Eq '^(GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN)=' install-env.txt
    ! grep -Eq '^(GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN)=' dist/build-env.txt
}

@test "an install-command cannot see the token either" {
    export INPUT_INSTALL_COMMAND='env > install-env.txt'
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    grep -q '^NAB_COMMAND=build$' install-env.txt
    ! grep -q "$FAKE_TOKEN" install-env.txt
}

@test "a registry token that the workflow sets on purpose is left alone" {
    export NODE_AUTH_TOKEN="registry-token-for-private-packages"
    export INPUT_INSTALL_COMMAND='env > install-env.txt'
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    grep -q '^NODE_AUTH_TOKEN=registry-token-for-private-packages$' install-env.txt
}

@test "the scripts never print the token" {
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [[ "$output" != *"$FAKE_TOKEN"* ]]
    run bash "$SCRIPTS/build.sh"
    [[ "$output" != *"$FAKE_TOKEN"* ]]
    ! grep -q "$FAKE_TOKEN" "$GITHUB_ENV" "$GITHUB_OUTPUT"
}

@test "the validate step does not write the token to GITHUB_ENV" {
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    ! grep -q "$FAKE_TOKEN" "$GITHUB_ENV"
    [[ "$output" != *"$FAKE_TOKEN"* ]]
}
