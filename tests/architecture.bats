#!/usr/bin/env bats
# Architecture rules. Each test reads the scripts as text and fails when a rule is broken,
# so a change that crosses the line between the steps without the token (install and
# build) and the steps with the token (commit and pr) is caught before it is merged.
# docs/architecture.md describes the rules in words.
#
# What these tests cover: they look for names, for example GITHUB_TOKEN or `git push`. They
# cannot see an indirect read such as ${!name} or a command built from pieces. Behavior is
# tested in token.bats, commit.bats and check.bats. The tests also run on bash 3.2 (macOS),
# where a bare [[ ]] or `! cmd` in a test body does not fail it, so every check below is a
# function that returns 1, or a [ ] test.
#
# Rules already checked in action.bats are not repeated here: every script starts with
# the shebang and `set -euo pipefail`, no single line `run:` holds an expression, and the
# token is read in one step only. shellcheck runs in CI and in `npm test`.

load helpers

# The scripts that hold the token and may talk to the remote. Only these may run `git push`
# or `git fetch`. git-lib.sh is the helper that builds the credential header and runs the
# git commands with it, shared by commit.sh and pr.sh. To let a new script hold the token,
# add its name here and say why in docs/architecture.md.
TOKEN_SCRIPTS="commit.sh pr.sh git-lib.sh"
OPTIONAL_TOKEN_SCRIPTS=""

# Maintainer tools: scripts for the person who releases, not part of the action. action.yml never
# runs them (a test below checks that). They may read the remote with `git ls-remote` and call `gh`,
# and nothing else beyond what every script may do. They hold no token: they name no token variable
# (the token rule above covers them), and a person or the release workflow gives `gh` its credentials.
# A test below fails when one of them can write: no git push, commit, tag or fetch, no gh release, pr
# or issue command, no gh api with a method or a field. To add one, add its name here and say why in
# docs/architecture.md.
MAINTAINER_SCRIPTS="release-check.sh"

# The names of the variables that carry a token. NODE_AUTH_TOKEN is not here on purpose:
# it is the registry token that the workflow author sets for the install.
TOKEN_NAMES="GITHUB_TOKEN|GH_TOKEN|INPUT_TOKEN|INPUT_GITHUB_TOKEN|NAB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN|ACTIONS_ID_TOKEN_REQUEST_URL"
TOKEN_RE="(^|[^A-Za-z0-9_])(${TOKEN_NAMES})([^A-Za-z0-9_]|\$)|secrets\\."

# The words that start a command in front of which a network tool can stand.
COMMAND_START="(^|[|;&(\`]|\\\$\\(|[[:space:]](then|do|exec|sudo|xargs|command|env|run_without_token)[[:space:]])[[:space:]]*"
NETWORK_TOOLS="curl|wget|nc|ncat|netcat|socat|ssh|scp|sftp|ftp|telnet|gh|npx"
NETWORK_RE="${COMMAND_START}(${NETWORK_TOOLS})([[:space:]]|\$)|/dev/(tcp|udp)/"
# The token scripts may run gh: pr.sh talks to the GitHub API with it, and that is its job.
NETWORK_TOOLS_TOKEN_SCRIPTS="curl|wget|nc|ncat|netcat|socat|ssh|scp|sftp|ftp|telnet|npx"
NETWORK_RE_TOKEN_SCRIPTS="${COMMAND_START}(${NETWORK_TOOLS_TOKEN_SCRIPTS})([[:space:]]|\$)|/dev/(tcp|udp)/"

# The maintainer tools may call gh, like the token scripts, and may run `git ls-remote` to read.
GIT_REMOTE_RE_MAINTAINER="(^|[^A-Za-z0-9_-])git([[:space:]]+[^|;&]*)?[[:space:]]+(push|fetch|pull|clone)([[:space:]]|\$)|(^|[^A-Za-z0-9_])nab_git_remote([^A-Za-z0-9_]|\$)"

# What a maintainer tool must never do: a git command that changes the repository or a tag, a gh command
# that creates or edits something, a gh api call that is not a plain GET.
MAINTAINER_WRITE_RE="(^|[^A-Za-z0-9_-])git([[:space:]]+[^|;&]*)?[[:space:]]+(push|fetch|pull|clone|commit|add|rm|mv|tag|branch|checkout|switch|reset|merge|rebase|stash|cherry-pick|revert|apply|am|config|update-ref|worktree)([[:space:]]|\$)|(^|[^A-Za-z0-9_-])gh[[:space:]]+(release|pr|issue|repo|workflow|run|label|secret|variable|ruleset|auth)([[:space:]]|\$)|(^|[^A-Za-z0-9_-])gh[[:space:]]+api[[:space:]][^|;&]*([[:space:]]-X|[[:space:]]--method|[[:space:]]-[fF][[:space:]]|[[:space:]]--(field|raw-field|input))"

# git commands that talk to a remote, and the wrapper that gives them the token.
GIT_REMOTE_RE="(^|[^A-Za-z0-9_-])git([[:space:]]+[^|;&]*)?[[:space:]]+(push|fetch|pull|clone|ls-remote)([[:space:]]|\$)|(^|[^A-Za-z0-9_])nab_git_remote([^A-Za-z0-9_]|\$)"

# Every script in scripts/, as a base name per line.
script_names() {
    local file
    for file in "$SCRIPTS"/*.sh; do
        basename "$file"
    done
}

in_list() {
    local item=$1 list=$2 word
    for word in $list; do
        [ "$word" = "$item" ] && return 0
    done
    return 1
}

# Print "file:line: text" for every line of FILE that matches the extended regex RE and is
# not a comment line. A third argument is a regex for lines to skip. The regexes go in
# through the environment, so awk keeps their escapes.
code_hits() {
    RE="$2" EX="${3:-}" awk -v name="$(basename "$1")" '
        $0 !~ /^[[:space:]]*#/ && $0 ~ ENVIRON["RE"] && (ENVIRON["EX"] == "" || $0 !~ ENVIRON["EX"]) {
            print name ":" NR ": " $0
        }
    ' "$1"
}

# Fail, and print the lines, when FILE has a code line that matches RE (and not the
# optional third argument).
assert_no_hits() {
    local hits
    hits=$(code_hits "$1" "$2" "${3:-}")
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" >&2
        return 1
    fi
    return 0
}

# Print the lines of an action file that put a ${{ }} expression into a run: command,
# for the one line form and for a block (run: | or run: >). Comments are not skipped.
run_expressions() {
    awk '
        {
            match($0, /^ */); cur = RLENGTH
            if (inrun) {
                if ($0 ~ /^ *$/) next
                if (cur > ind) { if (index($0, "${{")) print NR ": " $0; next }
                inrun = 0
            }
            if ($0 ~ /^ *(- )?run:/) {
                ind = cur
                if ($0 ~ /run: *[|>]/) inrun = 1
                else if (index($0, "${{")) print NR ": " $0
            }
        }
    ' "$1"
}

# The comment block that follows the shebang, as one line of text.
header_of() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); printf "%s ", $0; next } { exit }' "$1"
}

# ---------------------------------------------------------------------------
# The token

@test "install.sh and build.sh never read a token variable" {
    assert_no_hits "$SCRIPTS/install.sh" "$TOKEN_RE"
    assert_no_hits "$SCRIPTS/build.sh" "$TOKEN_RE"
}

@test "only the scripts on the token allowlist read a token variable, and lib.sh only removes them" {
    local name
    for name in $(script_names); do
        in_list "$name" "$TOKEN_SCRIPTS" && continue
        case "$name" in
            install.sh | build.sh) continue ;; # named in the test above
            lib.sh)
                # run_without_token lists the names to remove with `env -u`. Any other
                # line in lib.sh that names one is a read.
                assert_no_hits "$SCRIPTS/lib.sh" "$TOKEN_RE" '-u '
                ;;
            *) assert_no_hits "$SCRIPTS/$name" "$TOKEN_RE" ;;
        esac
    done
}

@test "the maintainer tools exist, are not run by action.yml and cannot write" {
    local name
    for name in $MAINTAINER_SCRIPTS; do
        [ -f "$SCRIPTS/$name" ] || {
            echo "the maintainer list names $name, but scripts/$name does not exist" >&2
            return 1
        }
        # The action must not run a release tool, and a release tool must not hold the token scripts' role.
        if grep -q "$name" "$REPO_ROOT/action.yml"; then
            echo "action.yml names $name, a maintainer tool" >&2
            return 1
        fi
        in_list "$name" "$TOKEN_SCRIPTS" && {
            echo "$name is on both the token list and the maintainer list" >&2
            return 1
        }
        assert_no_hits "$SCRIPTS/$name" "$MAINTAINER_WRITE_RE"
    done
}

@test "control: the maintainer write rule sees a git push, a tag, a gh release and a gh api POST" {
    # Proves that the test above can fail. The rule runs on a file that breaks it, line by line.
    local file="$BATS_TEST_TMPDIR/bad.sh" line
    for line in 'git push origin main' 'git tag -a v1 -m x' 'git -C dir commit -m x' 'gh release create v1' \
        'gh pr merge 1' 'gh api repos/x/y -X POST' 'gh api repos/x/y -f a=b' 'gh api repos/x/y --method PATCH'; do
        printf '%s\n' "$line" >"$file"
        run code_hits "$file" "$MAINTAINER_WRITE_RE"
        [ -n "$output" ] || {
            echo "the rule did not see: $line" >&2
            return 1
        }
    done
    for line in 'git rev-parse HEAD' 'git ls-remote origin' 'git status --porcelain' 'gh api repos/x/y --jq .a'; do
        printf '%s\n' "$line" >"$file"
        run code_hits "$file" "$MAINTAINER_WRITE_RE"
        [ -z "$output" ] || {
            echo "the rule flagged a read: $line" >&2
            return 1
        }
    done
}

@test "the allowlist names only scripts that exist" {
    local name
    for name in $TOKEN_SCRIPTS; do
        if in_list "$name" "$OPTIONAL_TOKEN_SCRIPTS"; then
            continue
        fi
        [ -f "$SCRIPTS/$name" ] || {
            echo "the allowlist names $name, but scripts/$name does not exist" >&2
            return 1
        }
    done
}

@test "install.sh and build.sh start the project's code only through run_without_token" {
    # A line that starts with a package manager, a shell or an eval would run the code
    # with the whole environment. The first word of a code line must not be one of them.
    local file
    for file in install.sh build.sh; do
        assert_no_hits "$SCRIPTS/$file" '^[[:space:]]*("?\$\{?pm\}?"?|"?\$\{?command\}?"?|npm|npx|pnpm|yarn|corepack|bash|sh|eval|exec)[[:space:]]'
    done
}

@test "install.sh and build.sh do not run git" {
    assert_no_hits "$SCRIPTS/install.sh" '(^|[^A-Za-z0-9_-])git[[:space:]]'
    assert_no_hits "$SCRIPTS/build.sh" '(^|[^A-Za-z0-9_-])git[[:space:]]'
}

# ---------------------------------------------------------------------------
# The network

@test "only the token scripts push to or fetch from a remote, the maintainer tools only read it" {
    local name
    for name in $(script_names); do
        in_list "$name" "$TOKEN_SCRIPTS" && continue
        if in_list "$name" "$MAINTAINER_SCRIPTS"; then
            assert_no_hits "$SCRIPTS/$name" "$GIT_REMOTE_RE_MAINTAINER"
        else
            assert_no_hits "$SCRIPTS/$name" "$GIT_REMOTE_RE"
        fi
    done
}

@test "no script calls a network tool, the package manager is the only way out" {
    local name
    for name in $(script_names); do
        if in_list "$name" "$TOKEN_SCRIPTS" || in_list "$name" "$MAINTAINER_SCRIPTS"; then
            assert_no_hits "$SCRIPTS/$name" "$NETWORK_RE_TOKEN_SCRIPTS"
        else
            assert_no_hits "$SCRIPTS/$name" "$NETWORK_RE"
        fi
    done
}

@test "no script installs a tool for the whole machine or touches a system or home path" {
    local name
    for name in $(script_names); do
        assert_no_hits "$SCRIPTS/$name" '(npm|yarn|pnpm)[[:space:]]+(install|i|add)[[:space:]]+(-g|--global)|git[[:space:]]+config[[:space:]]+--(global|system)|(^|[^A-Za-z0-9_])(HOME)([^A-Za-z0-9_]|$)|~/|(^|[[:space:]"=])/(etc|usr|var|opt|root)/'
    done
}

# ---------------------------------------------------------------------------
# The shape of a script

@test "no script turns off errexit, nounset or pipefail" {
    local name
    for name in $(script_names); do
        assert_no_hits "$SCRIPTS/$name" '^[[:space:]]*set[[:space:]]+\+[A-Za-z]*[euo]|^[[:space:]]*set[[:space:]]+\+o[[:space:]]+(errexit|nounset|pipefail)'
    done
}

@test "every script has a header that says what it may do and may not do, or says it is a library" {
    local name header
    for name in $(script_names); do
        header=$(header_of "$SCRIPTS/$name")
        [ -n "$header" ] || {
            echo "$name has no header comment after the shebang" >&2
            return 1
        }
        case "$header" in
            *"May do:"*"May not:"*) ;;
            *"Sourced, never run on its own"*) ;;
            *)
                echo "$name: the header needs 'May do:' and 'May not:', or 'Sourced, never run on its own'" >&2
                return 1
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# action.yml

@test "no run: block of action.yml holds a \${{ }} expression, inputs travel through env:" {
    local hits
    hits=$(run_expressions "$REPO_ROOT/action.yml")
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" >&2
        return 1
    fi
}

@test "control: the run: expression finder sees a block form and a one line form" {
    # Proves that the test above can fail. The finder runs on a file that breaks the rule.
    local file="$BATS_TEST_TMPDIR/bad.yml"
    cat >"$file" <<'YAML'
runs:
  steps:
    - name: block
      run: |
        echo "ok"
        echo "${{ inputs.command }}"
    - name: line
      run: echo "${{ inputs.command }}"
    - name: clean
      env:
        X: ${{ inputs.command }}
      run: bash "$X"
YAML
    run run_expressions "$file"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
    [[ "$output" == *"6: "* ]] || false
    [[ "$output" == *"8: "* ]] || false
}

# ---------------------------------------------------------------------------
# The documentation

@test "every script is named in .github/copilot-instructions.md or docs/README.md" {
    local name
    for name in $(script_names); do
        grep -qF "scripts/$name" "$REPO_ROOT/.github/copilot-instructions.md" "$REPO_ROOT/docs/README.md" || {
            echo "scripts/$name is in neither .github/copilot-instructions.md nor docs/README.md" >&2
            return 1
        }
    done
}

@test "every script has a row in the table of docs/architecture.md" {
    local name
    for name in $(script_names); do
        grep -qE "^\| \`scripts/$name\` \|" "$REPO_ROOT/docs/architecture.md" || {
            echo "docs/architecture.md has no table row for scripts/$name" >&2
            return 1
        }
    done
}

@test "every script path in the docs points to a script that exists" {
    local doc ref
    for doc in README.md docs/README.md docs/architecture.md docs/testing.md \
        docs/recipes.md docs/migration-v2-to-v3.md examples/README.md .github/copilot-instructions.md; do
        for ref in $(grep -oE 'scripts/[A-Za-z0-9_.-]+\.sh' "$REPO_ROOT/$doc" | sort -u); do
            [ -f "$REPO_ROOT/$ref" ] || {
                echo "$doc names $ref, which does not exist" >&2
                return 1
            }
        done
    done
}
