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
    run grep -E '^\s+run:.*\$\{\{' "$ACTION"
    [ "$status" -eq 1 ]
}

@test "the token is only read by the default of its input, the alias flag and the commit and pr steps" {
    # Any other use of the token in action.yml would be a way to reach a step.
    local uses
    uses=$(grep -nE 'github\.token|inputs\.token|inputs\.github-token|secrets\.' "$ACTION" | grep -v '^[0-9]*:\s*#' || true)
    echo "$uses" >&2
    [ "$(printf '%s\n' "$uses" | grep -c .)" -eq 4 ]
    printf '%s\n' "$uses" | grep -q 'default: \${{ github.token }}'
    printf '%s\n' "$uses" | grep -q "INPUT_GITHUB_TOKEN_SET: \${{ inputs.github-token != '' && 'true' || 'false' }}"
    [ "$(printf '%s\n' "$uses" | grep -c "NAB_TOKEN: \${{ inputs.github-token != '' && inputs.github-token || inputs.token }}")" -eq 2 ]
}

# The line number of NAB_TOKEN must fall inside the named step: after its name and before the
# next step. Usage: token_line_in_step "Commit" (the Nth NAB_TOKEN line of the file is the one
# that belongs to the step).
token_line_in_step() {
    local step=$1 start end line found=""
    start=$(grep -n "^    - name: $step\$" "$ACTION" | cut -d: -f1)
    [ -n "$start" ]
    end=$(awk -v s="$start" 'NR > s && /^    - name:|^branding:/ {print NR; exit}' "$ACTION")
    for line in $(grep -n 'NAB_TOKEN:' "$ACTION" | cut -d: -f1); do
        if [ "$line" -gt "$start" ] && { [ -z "$end" ] || [ "$line" -lt "$end" ]; }; then
            found="$found $line"
        fi
    done
    [ "$(printf '%s\n' $found | grep -c .)" -eq 1 ]
}

@test "NAB_TOKEN is in the env of the commit step and the pr step, and of no other step" {
    token_line_in_step Commit
    token_line_in_step "Pull request"
    [ "$(grep -c 'NAB_TOKEN:' "$ACTION")" -eq 2 ]
}

@test "GH_TOKEN is never set in action.yml, only pr.sh gives it to gh for one command" {
    run grep -nE '^\s+(GH_TOKEN|GITHUB_TOKEN):' "$ACTION"
    [ "$status" -eq 1 ]
}

@test "the pr step runs only in mode pr, from the validate output" {
    grep -A3 '^    - name: Pull request$' "$ACTION" | grep -q "if: steps.validate.outputs.mode == 'pr'"
    grep -A3 '^    - name: Pull request$' "$ACTION" | grep -q '^      id: pr$'
}

@test "the pull request outputs come from the pr step" {
    grep -A3 '^  pull-request-url:$' "$ACTION" | grep -q 'steps.pr.outputs.pull-request-url'
    grep -A3 '^  pull-request-number:$' "$ACTION" | grep -q 'steps.pr.outputs.pull-request-number'
}

@test "no step or text of the action says that a mode is not available" {
    run grep -n -i 'not available\|issue #5' "$ACTION"
    [ "$status" -eq 1 ]
}

@test "the commit step runs only in mode commit, from the validate output" {
    grep -A3 '^    - name: Commit$' "$ACTION" | grep -q "if: steps.validate.outputs.mode == 'commit'"
}

@test "the outputs changed and commit-sha come from the commit step" {
    grep -A3 '^  changed:$' "$ACTION" | grep -q 'steps.commit.outputs.changed'
    grep -A3 '^  commit-sha:$' "$ACTION" | grep -q 'steps.commit.outputs.commit-sha'
}

@test "there is no env: at the top level of the action or the steps list" {
    run grep -E '^  env:|^env:' "$ACTION"
    [ "$status" -eq 1 ]
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
