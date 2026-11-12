# Helpers for the package manager and registry tests. Load after helpers:
#   load helpers
#   load pm_helpers
#
# The package managers are fake binaries. Each one appends its argument list to
# $STUB_LOG and a snapshot of the registry and token variables to $STUB_ENV_LOG. The
# scripts run with a small PATH (the stubs and symlinks to the few tools the scripts
# need), so a manager installed on the machine that runs the tests is never used.

# Symlink the tools the scripts and the stubs need into one directory.
make_tools_dir() {
    TOOLS_BIN="$BATS_TEST_TMPDIR/tools-bin"
    mkdir -p "$TOOLS_BIN"
    local tool path
    for tool in bash env node tr dirname basename grep sort cat awk cp mkdir chmod rm sed head cut touch; do
        path=$(command -v "$tool") || continue
        ln -sf "$path" "$TOOLS_BIN/$tool"
    done
}

# Write one stub into a directory. The name of the stub is the name of the file.
write_stub() {
    local dir=$1 name=$2
    cat >"$dir/$name" <<'STUB'
#!/usr/bin/env bash
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >>"$STUB_LOG"
{
    printf '[%s %s]\n' "$name" "$*"
    env | grep -E '^(NODE_AUTH_TOKEN|NPM_CONFIG_|YARN_|PNPM_|GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN)' | sort || true
} >>"$STUB_ENV_LOG"

if [ "${1:-}" = "--version" ]; then
    if [ "${STUB_BROKEN:-}" = "$name" ]; then
        echo "$name is broken" >&2
        exit 1
    fi
    case "$name" in
        yarn) echo "${STUB_VERSION_YARN:-1.22.22}" ;;
        pnpm) echo "${STUB_VERSION_PNPM:-9.15.0}" ;;
        npm) echo "${STUB_VERSION_NPM:-10.9.0}" ;;
        corepack) echo "0.30.0" ;;
    esac
    exit 0
fi

if [ "$name" = "corepack" ]; then
    if [ "${1:-}" = "enable" ]; then
        [ "${STUB_COREPACK_FAILS:-}" != "true" ] || exit 1
        # Corepack puts the shims of pnpm and yarn on PATH.
        cp "$SHIM_BIN"/* "$STUB_BIN"/ 2>/dev/null || true
    fi
    exit 0
fi

# Show how an .npmrc in the project resolves ${NODE_AUTH_TOKEN}, the way npm does.
if [ -f .npmrc ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s\n' "${line//\$\{NODE_AUTH_TOKEN\}/${NODE_AUTH_TOKEN-}}"
    done <.npmrc >>"$STUB_NPMRC_LOG"
fi

# "<manager> run build" writes the build output.
if [ "${1:-}" = "run" ]; then
    mkdir -p dist
    echo "built by the stub" >dist/out.txt
fi
exit 0
STUB
    chmod +x "$dir/$name"
}

# Fresh inputs, an empty project directory, an empty HOME, and the stub directories.
# Nothing is installed yet: use stub_on_path and stub_as_shim to choose what exists.
pm_setup() {
    reset_inputs
    default_inputs
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
    export SHIM_BIN="$BATS_TEST_TMPDIR/shim-bin"
    export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    export STUB_ENV_LOG="$BATS_TEST_TMPDIR/stub-env.log"
    export STUB_NPMRC_LOG="$BATS_TEST_TMPDIR/stub-npmrc.log"
    mkdir -p "$STUB_BIN" "$SHIM_BIN"
    : >"$STUB_LOG"
    : >"$STUB_ENV_LOG"
    : >"$STUB_NPMRC_LOG"
    make_tools_dir
    PM_PATH="$STUB_BIN:$TOOLS_BIN"

    WORKSPACE="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORKSPACE"
    cd "$WORKSPACE"
    write_project ""
}

# Installed before the action runs.
stub_on_path() {
    local name
    for name in "$@"; do
        write_stub "$STUB_BIN" "$name"
    done
}

# Not installed until "corepack enable" runs, the way corepack shims appear.
stub_as_shim() {
    local name
    for name in "$@"; do
        write_stub "$SHIM_BIN" "$name"
    done
}

# package.json with a build script, and optionally a packageManager field.
write_project() {
    local field=${1:-}
    {
        printf '{\n  "name": "pm-test",\n  "version": "1.0.0",\n'
        if [ -n "$field" ]; then
            printf '  "packageManager": "%s",\n' "$field"
        fi
        printf '  "scripts": { "build": "node build.js" }\n}\n'
    } >package.json
}

# Run a script with the small PATH. The environment variables the test exported stay.
run_script() {
    run env PATH="$PM_PATH" "$BASH" "$SCRIPTS/$1"
}

run_install() {
    validate_and_load
    run_script install.sh
}

run_build() {
    validate_and_load
    run_script build.sh
}

# The calls of the stubs, without the "--version" checks.
calls() {
    grep -v -e ' --version$' "$STUB_LOG" || true
}

# The environment snapshot of one call, for example: env_of "yarn install --immutable".
env_of() {
    awk -v header="[$1]" '
        /^\[/ { active = ($0 == header); next }
        active { print }
    ' "$STUB_ENV_LOG"
}
