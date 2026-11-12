#!/usr/bin/env bats
# Package manager detection, yarn classic and berry, corepack, ignore-scripts and the
# build command. The managers are fake binaries that record how they were called.

load helpers
load pm_helpers

setup() {
    pm_setup
}

# ---- detection by the packageManager field --------------------------------------------

@test "packageManager npm with a lockfile runs npm ci" {
    write_project "npm@10.2.0"
    touch package-lock.json
    stub_on_path npm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm ci" ]
}

@test "packageManager pnpm runs pnpm install --frozen-lockfile" {
    write_project "pnpm@9.1.0"
    touch pnpm-lock.yaml
    stub_on_path corepack
    stub_as_shim pnpm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = $'corepack enable\npnpm install --frozen-lockfile' ]
}

@test "packageManager with a hash after the version is read" {
    write_project "pnpm@9.1.0+sha512.0123abcd"
    touch pnpm-lock.yaml
    stub_on_path corepack
    stub_as_shim pnpm
    run_install
    [ "$status" -eq 0 ]
    [[ "$(calls)" == *"pnpm install --frozen-lockfile" ]] || false
}

@test "packageManager wins over a lockfile" {
    write_project "pnpm@9.1.0"
    touch package-lock.json
    stub_on_path corepack
    stub_as_shim pnpm
    run_install
    [ "$status" -eq 0 ]
    # No pnpm lockfile, so the install is not frozen. The manager is still pnpm.
    [ "$(calls)" = $'corepack enable\npnpm install --no-frozen-lockfile' ]
}

@test "packageManager settles two lockfiles" {
    write_project "yarn@1.22.22"
    touch package-lock.json yarn.lock
    stub_on_path corepack
    stub_as_shim yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = $'corepack enable\nyarn install --frozen-lockfile' ]
}

@test "bun in the packageManager field fails and lists the supported managers" {
    write_project "bun@1.1.0"
    touch package-lock.json
    stub_on_path npm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"*"'bun' is not supported"* ]] || false
    [[ "$output" == *"npm, pnpm and yarn"* ]] || false
    [ -z "$(calls)" ]
}

@test "an unknown packageManager name fails too" {
    write_project "deno@2.0.0"
    stub_on_path npm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"'deno' is not supported"* ]] || false
}

@test "a packageManager that is not a string fails with a clear message" {
    printf '%s\n' '{"name":"x","version":"1.0.0","packageManager":{"name":"pnpm"}}' >package.json
    stub_on_path npm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"packageManager is not a string"* ]] || false
}

# ---- detection by the lockfile ---------------------------------------------------------

@test "package-lock.json is npm ci and needs no corepack" {
    touch package-lock.json
    stub_on_path npm corepack
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm ci" ]
}

@test "npm-shrinkwrap.json is npm ci" {
    touch npm-shrinkwrap.json
    stub_on_path npm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm ci" ]
}

@test "package-lock.json together with npm-shrinkwrap.json is one manager, not a conflict" {
    touch package-lock.json npm-shrinkwrap.json
    stub_on_path npm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm ci" ]
}

@test "pnpm-lock.yaml is pnpm, set up with corepack when it is missing" {
    touch pnpm-lock.yaml
    stub_on_path corepack
    stub_as_shim pnpm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = $'corepack enable\npnpm install --frozen-lockfile' ]
}

@test "yarn.lock is yarn classic when nothing says berry" {
    touch yarn.lock
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --frozen-lockfile" ]
}

@test "no lockfile runs npm install with a warning" {
    stub_on_path npm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm install" ]
    [[ "$output" == *"::warning::No package-lock.json found"* ]] || false
}

@test "a lockfile does not produce the missing lockfile warning" {
    touch package-lock.json
    stub_on_path npm
    run_install
    [[ "$output" != *"::warning::"* ]] || false
}

@test "two lockfiles fail and name both" {
    touch package-lock.json yarn.lock
    stub_on_path npm yarn
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"*"yarn.lock, package-lock.json"* ]] || false
    [[ "$output" == *"packageManager"* ]] || false
    [[ "$output" == *"package-manager input"* ]] || false
    [ -z "$(calls)" ]
}

@test "three lockfiles fail and name all three" {
    touch pnpm-lock.yaml yarn.lock package-lock.json
    stub_on_path npm yarn pnpm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"pnpm-lock.yaml, yarn.lock, package-lock.json"* ]] || false
}

@test "a bun lockfile alone fails, a bun lockfile next to another one does not" {
    touch bun.lockb
    stub_on_path npm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"bun is not supported"* ]] || false
    touch package-lock.json
    run_script install.sh
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm ci" ]
}

@test "the build step fails on two lockfiles too" {
    touch package-lock.json pnpm-lock.yaml
    stub_on_path npm pnpm
    run_build
    [ "$status" -eq 1 ]
    [[ "$output" == *"pnpm-lock.yaml, package-lock.json"* ]] || false
}

# ---- explicit input -------------------------------------------------------------------

@test "an explicit package-manager wins over the lockfile and the field" {
    write_project "pnpm@9.1.0"
    touch pnpm-lock.yaml yarn.lock
    export INPUT_PACKAGE_MANAGER=npm
    stub_on_path npm corepack
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm install" ]
    # The field names another manager, so the action says that the input won.
    [[ "$output" == *"::warning::The package-manager input is 'npm'"* ]] || false
}

@test "an explicit package-manager skips the two lockfile error" {
    touch package-lock.json yarn.lock
    export INPUT_PACKAGE_MANAGER=yarn
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --frozen-lockfile" ]
}

@test "an explicit package-manager still checks the tool: missing after corepack" {
    export INPUT_PACKAGE_MANAGER=pnpm
    stub_on_path corepack
    # corepack enable runs but provides nothing.
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::pnpm was not found on PATH"* ]] || false
}

@test "an explicit package-manager still checks the tool: --version fails" {
    export INPUT_PACKAGE_MANAGER=npm
    export STUB_BROKEN=npm
    stub_on_path npm
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::'npm --version' failed"* ]] || false
    [ -z "$(calls)" ]
}

@test "an explicit package-manager overrides an unsupported packageManager field" {
    write_project "bun@1.1.0"
    export INPUT_PACKAGE_MANAGER=npm
    stub_on_path npm
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "npm install" ]
}

@test "install-command overrides everything: no corepack, no version check" {
    write_project "pnpm@9.1.0"
    touch pnpm-lock.yaml
    export INPUT_INSTALL_COMMAND='echo custom > custom.txt'
    stub_on_path corepack pnpm
    run_install
    [ "$status" -eq 0 ]
    [ "$(cat custom.txt)" = "custom" ]
    [ ! -s "$STUB_LOG" ]
}

@test "install-command still fails early when the build could not pick a manager" {
    touch package-lock.json yarn.lock
    export INPUT_INSTALL_COMMAND='echo custom > custom.txt'
    run_install
    [ "$status" -eq 1 ]
    [ ! -e custom.txt ]
    [[ "$output" == *"yarn.lock, package-lock.json"* ]] || false
}

# ---- yarn classic and berry -----------------------------------------------------------

@test "yarn: the field decides between classic and berry" {
    touch yarn.lock
    stub_on_path yarn corepack
    stub_as_shim yarn
    local field expected
    for field in "yarn@1.22.22:yarn install --frozen-lockfile" \
        "yarn@2.4.3:yarn install --immutable" \
        "yarn@3.8.0:yarn install --immutable" \
        "yarn@4.1.0+sha512.abcd:yarn install --immutable"; do
        : >"$STUB_LOG"
        write_project "${field%%:*}"
        expected=${field#*:}
        run_install
        [ "$status" -eq 0 ]
        [ "$(calls)" = $'corepack enable\n'"$expected" ]
    done
}

@test "yarn: .yarnrc.yml means berry" {
    touch yarn.lock .yarnrc.yml
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --immutable" ]
}

@test "yarn: a berry lockfile means berry" {
    printf '%s\n' '__metadata:' '  version: 8' >yarn.lock
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --immutable" ]
}

@test "yarn: yarn --version on PATH decides when nothing else does" {
    touch yarn.lock
    stub_on_path yarn
    export STUB_VERSION_YARN=4.2.0
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --immutable" ]
    # The version is read before the install command is chosen.
    [ "$(head -n 1 "$STUB_LOG")" = "yarn --version" ]
    export STUB_VERSION_YARN=1.22.22
    : >"$STUB_LOG"
    run_script install.sh
    [ "$(calls)" = "yarn install --frozen-lockfile" ]
}

@test "yarn: the field wins over .yarnrc.yml and over the version on PATH" {
    write_project "yarn@1.22.22"
    touch yarn.lock .yarnrc.yml
    export STUB_VERSION_YARN=4.2.0
    stub_on_path yarn corepack
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = $'corepack enable\nyarn install --frozen-lockfile' ]
}

@test "yarn: a missing yarn comes from corepack and its version is read after that" {
    touch yarn.lock
    stub_on_path corepack
    stub_as_shim yarn
    export STUB_VERSION_YARN=3.6.0
    run_install
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = $'corepack enable\nyarn --version\nyarn install --immutable' ]
}

@test "yarn without a lockfile installs without the frozen flags and warns" {
    export INPUT_PACKAGE_MANAGER=yarn
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install" ]
    [[ "$output" == *"::warning::No yarn.lock found"* ]] || false
    : >"$STUB_LOG"
    touch .yarnrc.yml
    run_script install.sh
    [ "$(calls)" = "yarn install --no-immutable" ]
}

# ---- pnpm ------------------------------------------------------------------------------

@test "pnpm on PATH needs no corepack when the field is absent" {
    touch pnpm-lock.yaml
    stub_on_path pnpm corepack
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "pnpm install --frozen-lockfile" ]
}

# ---- ignore-scripts ---------------------------------------------------------------------

@test "ignore-scripts: --ignore-scripts for npm, pnpm and yarn classic" {
    export INPUT_IGNORE_SCRIPTS=true
    stub_on_path npm pnpm yarn
    local lock expected
    for lock in package-lock.json:"npm ci --ignore-scripts" \
        pnpm-lock.yaml:"pnpm install --frozen-lockfile --ignore-scripts" \
        yarn.lock:"yarn install --frozen-lockfile --ignore-scripts"; do
        rm -f package-lock.json pnpm-lock.yaml yarn.lock
        touch "${lock%%:*}"
        : >"$STUB_LOG"
        run_install
        [ "$status" -eq 0 ]
        [ "$(calls)" = "${lock#*:}" ]
    done
}

@test "ignore-scripts: yarn berry has no flag, YARN_ENABLE_SCRIPTS=false is set for that command only" {
    export INPUT_IGNORE_SCRIPTS=true
    touch yarn.lock .yarnrc.yml
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    [ "$(calls)" = "yarn install --immutable" ]
    env_of "yarn install --immutable" | grep -qx 'YARN_ENABLE_SCRIPTS=false'
    # The version check ran before, with the environment of the job.
    run env_of "yarn --version"
    [[ "$output" != *"YARN_ENABLE_SCRIPTS"* ]] || false
}

@test "ignore-scripts off: yarn berry does not get YARN_ENABLE_SCRIPTS" {
    touch yarn.lock .yarnrc.yml
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    run env_of "yarn install --immutable"
    [[ "$output" != *"YARN_ENABLE_SCRIPTS"* ]] || false
}

@test "ignore-scripts: the berry variable is set for the berry install even when the job sets another value" {
    export YARN_ENABLE_SCRIPTS=true
    export INPUT_IGNORE_SCRIPTS=true
    touch yarn.lock .yarnrc.yml
    stub_on_path yarn
    run_install
    [ "$status" -eq 0 ]
    env_of "yarn install --immutable" | grep -qx 'YARN_ENABLE_SCRIPTS=false'
}

# ---- corepack ----------------------------------------------------------------------------

@test "corepack enable is not called for npm, for a manager on PATH, or for a field npm" {
    stub_on_path corepack npm pnpm yarn
    touch package-lock.json
    run_install
    [ "$status" -eq 0 ]
    rm package-lock.json
    touch pnpm-lock.yaml
    run_script install.sh
    [ "$status" -eq 0 ]
    rm pnpm-lock.yaml
    touch yarn.lock
    run_script install.sh
    [ "$status" -eq 0 ]
    write_project "npm@10.2.0"
    rm yarn.lock
    touch package-lock.json
    run_script install.sh
    [ "$status" -eq 0 ]
    run grep -q '^corepack' "$STUB_LOG"
    [ "$status" -eq 1 ]
}

@test "corepack enable is called when the field names pnpm or yarn, even if the binary exists" {
    stub_on_path corepack pnpm
    write_project "pnpm@9.1.0"
    touch pnpm-lock.yaml
    run_install
    [ "$status" -eq 0 ]
    [ "$(head -n 1 "$STUB_LOG")" = "corepack enable" ]
}

@test "corepack enable is called once for a missing pnpm and the log says why" {
    touch pnpm-lock.yaml
    stub_on_path corepack
    stub_as_shim pnpm
    run_install
    [ "$status" -eq 0 ]
    [ "$(grep -c '^corepack enable$' "$STUB_LOG")" -eq 1 ]
    [[ "$output" == *"Enabling corepack: pnpm is not installed"* ]] || false
    [[ "$output" == *"Using pnpm 9.15.0"* ]] || false
}

@test "without corepack a missing pnpm fails and says how to install it" {
    touch pnpm-lock.yaml
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::Corepack is not available"* ]] || false
    [[ "$output" == *"Install pnpm in a step before this action"* ]] || false
    [[ "$output" == *"install-command"* ]] || false
}

@test "without corepack a packageManager field of yarn fails the same way" {
    write_project "yarn@4.1.0"
    touch yarn.lock
    stub_on_path yarn
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::Corepack is not available"* ]] || false
    [[ "$output" == *"packageManager field"* ]] || false
}

@test "a failing corepack enable is a clear error" {
    touch yarn.lock
    export STUB_COREPACK_FAILS=true
    stub_on_path corepack
    stub_as_shim yarn
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"'corepack enable' failed"* ]] || false
    [ "$(calls)" = "corepack enable" ]
}

@test "the scripts download nothing themselves: no curl, wget or npm install -g" {
    # Comments are left out, they may say what the scripts never do.
    run bash -c "grep -hvE '^[[:space:]]*#' \"$SCRIPTS\"/*.sh | grep -nE '\\b(curl|wget)\\b|install +(-g|--global)|\\bnpx\\b'"
    [ "$status" -eq 1 ]
}

# ---- the build step ---------------------------------------------------------------------

@test "build: npm run build" {
    touch package-lock.json
    stub_on_path npm
    run_build
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "npm run build" ]
}

@test "build: pnpm run build, with no corepack and no version check" {
    touch pnpm-lock.yaml
    stub_on_path pnpm corepack
    run_build
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "pnpm run build" ]
}

@test "build: yarn run build for classic and for berry" {
    stub_on_path yarn
    touch yarn.lock
    run_build
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "yarn run build" ]
    : >"$STUB_LOG"
    touch .yarnrc.yml
    rm -rf dist
    run_script build.sh
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "yarn run build" ]
    : >"$STUB_LOG"
    write_project "yarn@4.1.0"
    rm -rf dist
    run_script build.sh
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "yarn run build" ]
}

@test "build: the same manager as the install, chosen by the field" {
    write_project "pnpm@9.1.0"
    touch package-lock.json
    stub_on_path npm pnpm
    run_build
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "pnpm run build" ]
}

@test "build: an explicit package-manager is used" {
    export INPUT_PACKAGE_MANAGER=yarn
    touch package-lock.json
    stub_on_path npm yarn
    run_build
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_LOG")" = "yarn run build" ]
}
