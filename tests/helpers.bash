# Shared helpers for the bats tests. Loaded with: load helpers

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPTS="$REPO_ROOT/scripts"
FIXTURE="$REPO_ROOT/tests/fixture"

# A distinct string that stands in for a real token. No test output may contain it
# when it should not.
FAKE_TOKEN="ghs_FAKE_token_value_for_tests_0123456789"

# Start from a clean set of inputs and fresh GITHUB_ENV and GITHUB_OUTPUT files, the
# way a composite action step starts. Every INPUT_* variable is removed first.
reset_inputs() {
    local name
    for name in $(compgen -e | grep -E '^(INPUT_|NAB_)' || true); do
        unset "$name"
    done
    export GITHUB_ENV="$BATS_TEST_TMPDIR/github_env"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
    : >"$GITHUB_ENV"
    : >"$GITHUB_OUTPUT"
}

# The defaults a composite action passes when the user sets only mode: build.
default_inputs() {
    export INPUT_MODE=build
    export INPUT_WORKING_DIRECTORY=.
    export INPUT_COMMAND=build
    export INPUT_INSTALL_COMMAND=
    export INPUT_PACKAGE_MANAGER=auto
    export INPUT_NODE_VERSION=24
    export INPUT_NODE_VERSION_FILE=
    export INPUT_PATHS=dist
    export INPUT_COMMIT_MESSAGE="chore: update build output [skip ci]"
    export INPUT_GIT_USER_NAME="github-actions[bot]"
    export INPUT_GIT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
    export INPUT_BRANCH=
    export INPUT_PR_TITLE=
    export INPUT_PR_LABELS=
    export INPUT_AUTO_MERGE=false
    export INPUT_IGNORE_SCRIPTS=false
    export INPUT_UPLOAD_DIFF=true
    export INPUT_DIRECTORY=
    export INPUT_BUILD_DIR=
    export INPUT_BUILD_ONLY=
    export INPUT_CREATE_PR=
    export INPUT_GITHUB_TOKEN_SET=false
}

# Print the value of KEY from the GITHUB_ENV file (heredoc format, may be multi-line).
env_value() {
    awk -v key="$1" '
        !inblock && index($0, key "<<") == 1 {
            delim = substr($0, length(key) + 3); inblock = 1; first = 1; next
        }
        inblock && $0 == delim { exit }
        inblock { if (!first) printf "\n"; printf "%s", $0; first = 0 }
    ' "$GITHUB_ENV"
}

# Print the value of KEY from the GITHUB_OUTPUT file (single line).
output_value() {
    grep -E "^$1=" "$GITHUB_OUTPUT" | head -n 1 | cut -d= -f2-
}

# Export the NAB_* variables that validate-inputs.sh wrote, for the next scripts.
load_env_file() {
    local key
    for key in NAB_MODE NAB_WORKDIR NAB_COMMAND NAB_INSTALL_COMMAND NAB_PACKAGE_MANAGER \
        NAB_PATHS NAB_IGNORE_SCRIPTS; do
        export "$key=$(env_value "$key")"
    done
}

# Copy the fixture project into a fresh workspace and make it the current directory.
# Takes an optional sub directory, for the working-directory tests.
make_workspace() {
    local sub=${1:-.}
    WORKSPACE="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORKSPACE/$sub"
    cp "$FIXTURE/package.json" "$FIXTURE/package-lock.json" "$FIXTURE/build.js" "$WORKSPACE/$sub/"
    cd "$WORKSPACE"
}

# A fake package manager that records how it was called. Usage: make_stub npm yarn pnpm
make_stub() {
    STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
    STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    mkdir -p "$STUB_BIN"
    : >"$STUB_LOG"
    local name
    for name in "$@"; do
        printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "$STUB_LOG"\n' "$name" >"$STUB_BIN/$name"
        chmod +x "$STUB_BIN/$name"
    done
    export STUB_LOG
    export PATH="$STUB_BIN:$PATH"
}

# Validate the current INPUT_* variables and load the result for the next scripts.
validate_and_load() {
    run bash "$SCRIPTS/validate-inputs.sh"
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
    load_env_file
}
