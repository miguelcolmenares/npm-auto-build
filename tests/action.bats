#!/usr/bin/env bats
# Rules about the shape of action.yml, checked as text so that no YAML tool is needed.

load helpers

ACTION="$BATS_TEST_DIRNAME/../action.yml"

@test "the action is composite" {
    grep -q '^  using: "composite"$' "$ACTION"
}

@test "every run step sets shell: bash" {
    local runs shells
    runs=$(grep -c '^      run:' "$ACTION")
    shells=$(grep -c '^      shell: bash$' "$ACTION")
    [ "$runs" -ge 1 ]
    [ "$runs" -eq "$shells" ]
}

@test "no run line interpolates an expression" {
    ! grep -E '^\s+run:.*\$\{\{' "$ACTION"
}

@test "the token is only read by the default of its input and the alias flag" {
    # Any other use of the token in action.yml would be a way to reach a step.
    local uses
    uses=$(grep -nE 'github\.token|inputs\.token|inputs\.github-token|secrets\.' "$ACTION" | grep -v '^[0-9]*:\s*#' || true)
    echo "$uses" >&2
    [ "$(printf '%s\n' "$uses" | grep -c .)" -eq 2 ]
    printf '%s\n' "$uses" | grep -q 'default: \${{ github.token }}'
    printf '%s\n' "$uses" | grep -q "INPUT_GITHUB_TOKEN_SET: \${{ inputs.github-token != '' && 'true' || 'false' }}"
}

@test "there is no env: at the top level of the action or the steps list" {
    ! grep -E '^  env:|^env:' "$ACTION"
}

@test "setup-node is pinned by a full commit SHA with a version comment" {
    grep -Eq 'uses: actions/setup-node@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' "$ACTION"
}

@test "every v3 input and output is declared" {
    local name
    for name in mode working-directory command install-command package-manager node-version \
        node-version-file paths token commit-message git-user-name git-user-email branch \
        pr-title pr-labels auto-merge ignore-scripts upload-diff \
        github-token directory build-dir build-only create-pr; do
        grep -q "^  $name:$" "$ACTION" || {
            echo "missing input $name" >&2
            return 1
        }
    done
    for name in changed stale commit-sha pull-request-url pull-request-number; do
        grep -q "^  $name:$" "$ACTION" || {
            echo "missing output $name" >&2
            return 1
        }
    done
}

@test "the contract defaults are the ones from issue 10" {
    grep -A3 '^  mode:$' "$ACTION" | grep -q 'default: "commit"'
    grep -A3 '^  node-version:$' "$ACTION" | grep -q 'default: "24"'
    grep -A3 '^  paths:$' "$ACTION" | grep -q 'default: "dist"'
    grep -A3 '^  commit-message:$' "$ACTION" | grep -q 'default: "chore: update build output \[skip ci\]"'
}

@test "every script starts with the shebang and set -euo pipefail" {
    local file
    for file in "$SCRIPTS"/*.sh; do
        [ "$(sed -n 1p "$file")" = "#!/usr/bin/env bash" ] || {
            echo "$file: shebang" >&2
            return 1
        }
        grep -q '^set -euo pipefail$' "$file" || {
            echo "$file: set -euo pipefail" >&2
            return 1
        }
    done
}
