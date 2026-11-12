#!/usr/bin/env bats
# Install step: which package manager and which command, per lockfile. The package
# managers are fake binaries on PATH that record how they were called.

load helpers

setup() {
    reset_inputs
    default_inputs
    make_workspace
    rm -f package-lock.json
    make_stub npm yarn pnpm
}

install_log() {
    cat "$STUB_LOG"
}

@test "package-lock.json runs npm ci" {
    touch package-lock.json
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "npm ci" ]
}

@test "yarn.lock runs yarn install --frozen-lockfile" {
    touch yarn.lock
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "yarn install --frozen-lockfile" ]
}

@test "pnpm-lock.yaml runs pnpm install --frozen-lockfile" {
    touch pnpm-lock.yaml
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "pnpm install --frozen-lockfile" ]
}

@test "no lockfile runs npm install" {
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "npm install" ]
}

@test "package-lock.json wins when several lockfiles exist" {
    touch package-lock.json yarn.lock pnpm-lock.yaml
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "npm ci" ]
}

@test "ignore-scripts adds --ignore-scripts to each package manager" {
    export INPUT_IGNORE_SCRIPTS=true
    local lock expected
    for lock in package-lock.json:"npm ci --ignore-scripts" \
        yarn.lock:"yarn install --frozen-lockfile --ignore-scripts" \
        pnpm-lock.yaml:"pnpm install --frozen-lockfile --ignore-scripts"; do
        rm -f package-lock.json yarn.lock pnpm-lock.yaml
        : >"$STUB_LOG"
        touch "${lock%%:*}"
        expected=${lock#*:}
        validate_and_load
        run bash "$SCRIPTS/install.sh"
        [ "$status" -eq 0 ]
        [ "$(install_log)" = "$expected" ]
    done
    rm -f package-lock.json yarn.lock pnpm-lock.yaml
    : >"$STUB_LOG"
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$(install_log)" = "npm install --ignore-scripts" ]
}

@test "an explicit package-manager overrides the lockfile" {
    touch package-lock.json
    export INPUT_PACKAGE_MANAGER=pnpm
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "pnpm install --frozen-lockfile" ]
}

@test "install-command overrides detection and runs once" {
    touch package-lock.json
    export INPUT_INSTALL_COMMAND='echo custom-install > custom.txt'
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(cat custom.txt)" = "custom-install" ]
    [ ! -s "$STUB_LOG" ]
}

@test "ignore-scripts with install-command only warns" {
    export INPUT_INSTALL_COMMAND='true'
    export INPUT_IGNORE_SCRIPTS=true
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::ignore-scripts has no effect"* ]] || false
}

@test "a failing install fails the step" {
    export INPUT_INSTALL_COMMAND='exit 7'
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 7 ]
}

@test "the install runs in working-directory" {
    mkdir app
    mv package.json app/
    touch app/yarn.lock
    export INPUT_WORKING_DIRECTORY=app
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 0 ]
    [ "$(install_log)" = "yarn install --frozen-lockfile" ]
}

@test "a missing working-directory is a clear error" {
    export INPUT_WORKING_DIRECTORY=missing
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::working-directory 'missing' does not exist."* ]] || false
}

@test "a missing package.json is a clear error" {
    rm package.json
    validate_and_load
    run bash "$SCRIPTS/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"package.json not found"* ]] || false
}
