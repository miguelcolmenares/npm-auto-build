#!/usr/bin/env bats
# Private registries. The contract this file pins down:
#   - the install and the build inherit NODE_AUTH_TOKEN and the NPM_CONFIG_*, YARN_* and
#     PNPM_* variables that the workflow sets in the env: of the job
#   - a project .npmrc that reads ${NODE_AUTH_TOKEN} works, because the variable reaches
#     the install
#   - the GitHub token variables never reach the install or the build, also when
#     NODE_AUTH_TOKEN holds the same value
#   - the scripts never write an .npmrc or any credential file
# The last tests use the real npm and a local registry that needs a bearer token.

load helpers
load pm_helpers

setup() {
    pm_setup
    export REGISTRY_TOKEN="registry-token-for-private-packages"
}

teardown() {
    if [ -n "${SERVER_PID:-}" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}

# Run the install, then the build, with a manager that is a stub.
install_and_build() {
    validate_and_load
    run_script install.sh
    [ "$status" -eq 0 ]
    run_script build.sh
    [ "$status" -eq 0 ]
}

# ---- the environment of the job reaches install and build -------------------------------

@test "NODE_AUTH_TOKEN and the registry variables reach install and build, for each manager" {
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    export NPM_CONFIG_REGISTRY="https://registry.example.test/"
    export YARN_NPM_REGISTRY_SERVER="https://registry.example.test/"
    export PNPM_HOME="$BATS_TEST_TMPDIR/pnpm-home"
    stub_on_path npm pnpm yarn
    local row lock install_call build_call call
    for row in "package-lock.json|npm ci|npm run build" \
        "yarn.lock|yarn install --frozen-lockfile|yarn run build" \
        "pnpm-lock.yaml|pnpm install --frozen-lockfile|pnpm run build"; do
        lock=${row%%|*}
        install_call=${row#*|}
        build_call=${install_call#*|}
        install_call=${install_call%%|*}
        rm -f package-lock.json yarn.lock pnpm-lock.yaml
        touch "$lock"
        : >"$STUB_LOG"
        : >"$STUB_ENV_LOG"
        install_and_build
        for call in "$install_call" "$build_call"; do
            env_of "$call" | grep -qx "NODE_AUTH_TOKEN=$REGISTRY_TOKEN"
            env_of "$call" | grep -qx "NPM_CONFIG_REGISTRY=https://registry.example.test/"
            env_of "$call" | grep -qx "YARN_NPM_REGISTRY_SERVER=https://registry.example.test/"
            env_of "$call" | grep -qx "PNPM_HOME=$BATS_TEST_TMPDIR/pnpm-home"
        done
    done
}

@test "NODE_AUTH_TOKEN reaches yarn berry too, with ignore-scripts on" {
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    export INPUT_IGNORE_SCRIPTS=true
    touch yarn.lock .yarnrc.yml
    stub_on_path yarn
    install_and_build
    env_of "yarn install --immutable" | grep -qx "NODE_AUTH_TOKEN=$REGISTRY_TOKEN"
    env_of "yarn run build" | grep -qx "NODE_AUTH_TOKEN=$REGISTRY_TOKEN"
}

@test "NODE_AUTH_TOKEN reaches the install-command" {
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    export NPM_CONFIG_USERCONFIG="$BATS_TEST_TMPDIR/setup-node.npmrc"
    export INPUT_INSTALL_COMMAND='printf "%s %s\n" "$NODE_AUTH_TOKEN" "$NPM_CONFIG_USERCONFIG" > seen.txt'
    touch package-lock.json
    stub_on_path npm
    validate_and_load
    run_script install.sh
    [ "$status" -eq 0 ]
    [ "$(cat seen.txt)" = "$REGISTRY_TOKEN $BATS_TEST_TMPDIR/setup-node.npmrc" ]
}

# ---- a project .npmrc that reads ${NODE_AUTH_TOKEN} ---------------------------------------

@test "a project .npmrc with \${NODE_AUTH_TOKEN} resolves because the variable reaches the install" {
    # The stub resolves the placeholder the way npm does and records the result.
    printf '%s\n' '//registry.example.test/:_authToken=${NODE_AUTH_TOKEN}' >.npmrc
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    touch package-lock.json
    stub_on_path npm
    validate_and_load
    run_script install.sh
    [ "$status" -eq 0 ]
    grep -qx "//registry.example.test/:_authToken=$REGISTRY_TOKEN" "$STUB_NPMRC_LOG"
}

@test "control: without NODE_AUTH_TOKEN the same .npmrc resolves to an empty token" {
    printf '%s\n' '//registry.example.test/:_authToken=${NODE_AUTH_TOKEN}' >.npmrc
    touch package-lock.json
    stub_on_path npm
    validate_and_load
    run_script install.sh
    [ "$status" -eq 0 ]
    grep -qx '//registry.example.test/:_authToken=' "$STUB_NPMRC_LOG"
}

# ---- the GitHub token never reaches them ---------------------------------------------------

export_github_tokens() {
    export GITHUB_TOKEN="$FAKE_TOKEN"
    export GH_TOKEN="$FAKE_TOKEN"
    export INPUT_TOKEN="$FAKE_TOKEN"
    export INPUT_GITHUB_TOKEN="$FAKE_TOKEN"
    export ACTIONS_RUNTIME_TOKEN="$FAKE_TOKEN"
    export ACTIONS_ID_TOKEN_REQUEST_TOKEN="$FAKE_TOKEN"
}

@test "control: the stub records a GitHub token variable when nothing removes it" {
    stub_on_path npm
    GITHUB_TOKEN="$FAKE_TOKEN" run env PATH="$PM_PATH" npm ci
    [ "$status" -eq 0 ]
    env_of "npm ci" | grep -qx "GITHUB_TOKEN=$FAKE_TOKEN"
}

@test "the GitHub token variables do not reach install or build, for each manager" {
    export_github_tokens
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    stub_on_path npm pnpm yarn
    local lock
    for lock in package-lock.json yarn.lock pnpm-lock.yaml; do
        rm -f package-lock.json yarn.lock pnpm-lock.yaml
        touch "$lock"
        : >"$STUB_ENV_LOG"
        install_and_build
        # Every call was recorded, and the registry token is in each of them.
        grep -q '^NODE_AUTH_TOKEN=' "$STUB_ENV_LOG"
        run grep -Eq '^(GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN)=' "$STUB_ENV_LOG"
        [ "$status" -eq 1 ]
        run grep -q "$FAKE_TOKEN" "$STUB_ENV_LOG"
        [ "$status" -eq 1 ]
    done
}

@test "the GitHub token variables are gone from corepack and the version check too" {
    export_github_tokens
    touch pnpm-lock.yaml
    stub_on_path corepack
    stub_as_shim pnpm
    validate_and_load
    run_script install.sh
    [ "$status" -eq 0 ]
    grep -q '^\[corepack enable\]$' "$STUB_ENV_LOG"
    grep -q '^\[pnpm --version\]$' "$STUB_ENV_LOG"
    run grep -q "$FAKE_TOKEN" "$STUB_ENV_LOG"
    [ "$status" -eq 1 ]
}

@test "with NODE_AUTH_TOKEN equal to the GitHub token, only NODE_AUTH_TOKEN carries it" {
    # The risk the README documents: the value is in the environment under the name that
    # the workflow chose. Lifecycle scripts of dependencies can read it, so use a token
    # made for the registry. The action cannot hide a variable that the workflow set on purpose.
    export_github_tokens
    export NODE_AUTH_TOKEN="$FAKE_TOKEN"
    touch package-lock.json
    stub_on_path npm
    install_and_build
    env_of "npm ci" | grep -qx "NODE_AUTH_TOKEN=$FAKE_TOKEN"
    env_of "npm run build" | grep -qx "NODE_AUTH_TOKEN=$FAKE_TOKEN"
    [ "$(grep -c "$FAKE_TOKEN" "$STUB_ENV_LOG")" -eq "$(grep -c '^NODE_AUTH_TOKEN=' "$STUB_ENV_LOG")" ]
    run grep -Eq '^(GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN)=' "$STUB_ENV_LOG"
    [ "$status" -eq 1 ]
}

@test "the scripts print no token, also when NODE_AUTH_TOKEN is set" {
    export_github_tokens
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    touch package-lock.json
    stub_on_path npm
    validate_and_load
    run_script install.sh
    [[ "$output" != *"$FAKE_TOKEN"* ]] || false
    [[ "$output" != *"$REGISTRY_TOKEN"* ]] || false
    run_script build.sh
    [[ "$output" != *"$FAKE_TOKEN"* ]] || false
    [[ "$output" != *"$REGISTRY_TOKEN"* ]] || false
    run grep -q "$REGISTRY_TOKEN" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    [ "$status" -eq 1 ]
}

# ---- no credential is written to a file -----------------------------------------------------

@test "the scripts never write an .npmrc, in the project or in HOME" {
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    stub_on_path npm pnpm yarn corepack
    stub_as_shim pnpm
    local lock
    for lock in package-lock.json yarn.lock pnpm-lock.yaml; do
        rm -f package-lock.json yarn.lock pnpm-lock.yaml
        touch "$lock"
        install_and_build
    done
    [ ! -e "$WORKSPACE/.npmrc" ]
    [ ! -e "$WORKSPACE/.yarnrc" ]
    [ ! -e "$WORKSPACE/.yarnrc.yml" ]
    [ -z "$(find "$HOME" -type f)" ]
    run grep -rq "$REGISTRY_TOKEN" "$WORKSPACE" "$HOME" "$GITHUB_ENV" "$GITHUB_OUTPUT"
    [ "$status" -eq 1 ]
}

@test "no script redirects output into an .npmrc, .yarnrc or an auth token setting" {
    # Reading a file such as .yarnrc.yml to detect berry is fine, writing one is not.
    run bash -c "grep -hvE '^[[:space:]]*#' \"$SCRIPTS\"/*.sh | grep -nE '(>|tee)[^|]*(npmrc|yarnrc|authToken)'"
    [ "$status" -eq 1 ]
}

# ---- registry-url and scope ------------------------------------------------------------------

@test "registry-url and scope are optional inputs with an empty default, passed to setup-node" {
    local action="$REPO_ROOT/action.yml"
    grep -A3 '^  registry-url:$' "$action" | grep -q 'default: ""'
    grep -A3 '^  scope:$' "$action" | grep -q 'default: ""'
    grep -q 'registry-url: \${{ inputs.registry-url }}' "$action"
    grep -q 'scope: \${{ inputs.scope }}' "$action"
    grep -q 'INPUT_REGISTRY_URL: \${{ inputs.registry-url }}' "$action"
    grep -q 'INPUT_SCOPE: \${{ inputs.scope }}' "$action"
}

@test "registry-url and scope: the usual values are accepted" {
    export INPUT_REGISTRY_URL=https://npm.pkg.github.com
    export INPUT_SCOPE=@my-org
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
    export INPUT_REGISTRY_URL=https://registry.example.test:8443/npm/@team/
    export INPUT_SCOPE=my-org
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
}

@test "registry-url and scope: empty values are accepted" {
    export INPUT_REGISTRY_URL=
    export INPUT_SCOPE=
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ]
}

@test "registry-url must be http or https" {
    export INPUT_REGISTRY_URL=ftp://registry.example.test/
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must start with http:// or https://"* ]] || false
    export INPUT_REGISTRY_URL='registry.example.test'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
}

@test "registry-url must not carry credentials and the message does not repeat them" {
    export INPUT_REGISTRY_URL="https://user:${REGISTRY_TOKEN}@registry.example.test/"
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not contain credentials"* ]] || false
    [[ "$output" != *"$REGISTRY_TOKEN"* ]] || false
}

@test "registry-url and scope must be a single line, and scope must look like a scope" {
    export INPUT_REGISTRY_URL=$'https://registry.example.test/\nmore'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    export INPUT_REGISTRY_URL=
    export INPUT_SCOPE='@my org'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    export INPUT_SCOPE='$(touch pwned)'
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 1 ]
    [ ! -e pwned ]
}

# ---- end to end: the real npm against a registry that needs a token ---------------------------

# Start the local registry. Sets REGISTRY_PORT and SERVER_PID, and prepares the project in
# the workspace with the .npmrc that setup-node would write (a placeholder, not a token).
start_registry() {
    command -v npm >/dev/null 2>&1 || skip "npm is not installed"
    local fixtures="$REPO_ROOT/tests/fixtures/registry"
    local packed="$BATS_TEST_TMPDIR/packed"
    mkdir -p "$packed"
    (cd "$fixtures/package" && npm pack --pack-destination "$packed" --silent >/dev/null)
    REQUEST_LOG="$BATS_TEST_TMPDIR/registry-requests.log"
    : >"$REQUEST_LOG"
    node "$fixtures/server.js" "$packed/nab-test-private-pkg-1.0.0.tgz" "$REGISTRY_TOKEN" \
        "$BATS_TEST_TMPDIR/port" "$REQUEST_LOG" >"$BATS_TEST_TMPDIR/server.out" 2>&1 3>&- &
    SERVER_PID=$!
    disown "$SERVER_PID"
    local tries=0
    while [ ! -s "$BATS_TEST_TMPDIR/port" ]; do
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || {
            cat "$BATS_TEST_TMPDIR/server.out" >&2
            return 1
        }
        sleep 0.1
    done
    REGISTRY_PORT=$(cat "$BATS_TEST_TMPDIR/port")

    cp "$fixtures/project/package.json" "$WORKSPACE/package.json"
    {
        printf '@nab-test:registry=http://127.0.0.1:%s/\n' "$REGISTRY_PORT"
        printf '%s\n' '//127.0.0.1:'"$REGISTRY_PORT"'/:_authToken=${NODE_AUTH_TOKEN}'
    } >"$WORKSPACE/.npmrc"

    export npm_config_cache="$BATS_TEST_TMPDIR/npm-cache"
    export npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
    export npm_config_loglevel=error
}

# Run the real scripts with the real PATH.
run_real() {
    validate_and_load
    run bash "$SCRIPTS/$1"
}

@test "real npm: with NODE_AUTH_TOKEN the private package is installed and built" {
    start_registry
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    run_real install.sh
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ -f node_modules/@nab-test/private-pkg/index.js ]
    grep -q ' authorized$' "$REQUEST_LOG"
    run grep -q ' denied$' "$REQUEST_LOG"
    [ "$status" -eq 1 ]
    run_real build.sh
    [ "$status" -eq 0 ]
    [ "$(cat dist/out.txt)" = "private package installed" ]
}

@test "real npm: it works with the GitHub token set too, which is not what the registry wants" {
    start_registry
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    export GITHUB_TOKEN="$FAKE_TOKEN"
    export GH_TOKEN="$FAKE_TOKEN"
    run_real install.sh
    [ "$status" -eq 0 ]
    [ -f node_modules/@nab-test/private-pkg/index.js ]
}

@test "real npm control: without NODE_AUTH_TOKEN the install fails" {
    start_registry
    run_real install.sh
    [ "$status" -ne 0 ]
    [ ! -e node_modules/@nab-test/private-pkg ]
}

@test "real npm control: a GitHub token is not a registry token, the install fails" {
    start_registry
    export GITHUB_TOKEN="$REGISTRY_TOKEN"
    run_real install.sh
    [ "$status" -ne 0 ]
    [ ! -e node_modules/@nab-test/private-pkg ]
}

@test "real npm control: a wrong NODE_AUTH_TOKEN is denied by the registry" {
    start_registry
    export NODE_AUTH_TOKEN="not-the-token"
    run_real install.sh
    [ "$status" -ne 0 ]
    grep -q ' denied$' "$REQUEST_LOG"
}

@test "real npm: the install never writes an .npmrc of its own" {
    start_registry
    export NODE_AUTH_TOKEN="$REGISTRY_TOKEN"
    local before
    before=$(cat .npmrc)
    run_real install.sh
    [ "$status" -eq 0 ]
    [ "$(cat .npmrc)" = "$before" ]
    [ ! -e "$HOME/.npmrc" ]
}
