#!/usr/bin/env bats
# The YAML examples of the docs must keep matching action.yml. tests/docs-examples.py reads
# the snippets of the README, the examples, the recipes and the migration guide, and checks
# them offline. It does not run the action: the self-test jobs of ci.yml do that, with the
# fixture projects.
#
# A check that never failed proves nothing, so most tests below break a copy of a doc on
# purpose (a made up input, an old reference, a missing permission) and expect the check to
# fail with a message that names the problem.
#
# These tests also run on bash 3.2 (macOS), where a bare [[ ]] or `! cmd` in a test body does
# not fail the test. Every check is a function that returns 1, or a [ ] test.

load helpers

VALIDATOR="$REPO_ROOT/tests/docs-examples.py"

setup() {
    # PyYAML is the only dependency. CI installs it (python3-yaml), a developer machine may not.
    if ! python3 -c 'import yaml' 2>/dev/null; then
        if [ -n "${CI:-}" ]; then
            echo "PyYAML is missing in CI: install python3-yaml" >&2
            return 1
        fi
        skip "PyYAML is not installed (python3 -m pip install pyyaml)"
    fi
    WORK="$BATS_TEST_TMPDIR/docs"
    mkdir -p "$WORK/examples"
    cp "$REPO_ROOT/README.md" "$WORK/README.md"
    cp "$REPO_ROOT"/examples/*.yml "$WORK/examples/"
    mkdir -p "$WORK/site" "$WORK/docs"
    cp "$REPO_ROOT"/docs/*.md "$WORK/docs/"
    cp "$REPO_ROOT/site/sitekit.config.json" "$WORK/site/"
}

# Run the validator the way CI does, on the files in $WORK.
validate_readme() {
    run python3 "$VALIDATOR" --tables "$WORK/README.md" --require-modes "$WORK/README.md"
}

validate_file() {
    run python3 "$VALIDATOR" "$1"
}

assert_contains() {
    case "$output" in
        *"$1"*) return 0 ;;
    esac
    echo "expected the output to contain: $1"
    echo "$output"
    return 1
}

# Add a line to the first `with:` that directly follows a use of this action. The new line
# has the indent of the keys under `with:`.
add_input_to_first_action_step() {
    local file=$1 line=$2 tmp="$1.tmp"
    awk -v ins="$line" '
        after_uses && !done && /^ *with:/ {
            print
            match($0, /^ */)
            printf "%*s%s\n", RLENGTH + 2, "", ins
            done = 1
            after_uses = 0
            next
        }
        { after_uses = ($0 ~ /npm-auto-build@/) ? 1 : 0; print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    # The edit must have changed something, or the test would prove nothing.
    grep -qF -- "$line" "$file"
}

# Replace the first line that contains $2 with $3, as plain text.
replace_first_line() {
    local file=$1 needle=$2 replacement=$3 tmp="$1.tmp"
    NEEDLE="$needle" REPLACEMENT="$replacement" awk '
        !done && index($0, ENVIRON["NEEDLE"]) { print ENVIRON["REPLACEMENT"]; done = 1; next }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    grep -qF -- "$replacement" "$file"
}

# Delete the first line that contains $2, and check that one line is gone.
delete_first_line() {
    local file=$1 needle=$2 tmp="$1.tmp" before after
    before=$(wc -l <"$file")
    NEEDLE="$needle" awk '
        !done && index($0, ENVIRON["NEEDLE"]) { done = 1; next }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    after=$(wc -l <"$file")
    [ "$after" -lt "$before" ]
}

# --- the docs as they are -------------------------------------------------------------

@test "the README examples and its tables match action.yml" {
    validate_readme
    [ "$status" -eq 0 ]
    assert_contains "0 errors" || return 1
    assert_contains "0 skipped" || return 1
}

@test "the README shows every mode" {
    # Fails when one mode has no example. The check is part of the run above, and this
    # test names it so that a failure reads clearly.
    run python3 "$VALIDATOR" --require-modes "$REPO_ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "the examples directory passes" {
    run python3 "$VALIDATOR" "$REPO_ROOT"/examples/*.yml
    [ "$status" -eq 0 ]
    assert_contains "0 errors" || return 1
}

@test "the recipes, the migration guide, the docs index and the Marketplace text pass" {
    run python3 "$VALIDATOR" "$REPO_ROOT/docs/recipes.md" "$REPO_ROOT/docs/migration-v2-to-v3.md" \
        "$REPO_ROOT/docs/README.md" "$REPO_ROOT/.github/ACTION_DESCRIPTION.md"
    [ "$status" -eq 0 ]
    assert_contains "0 errors" || return 1
}

@test "only the v2 before blocks of the migration guide are skipped" {
    run python3 "$VALIDATOR" "$REPO_ROOT/docs/migration-v2-to-v3.md"
    [ "$status" -eq 0 ]
    assert_contains "2 skipped" || return 1
}

# --- mutation proofs: break a copy, the check must fail --------------------------------

@test "mutation: a made up input in the README fails the check" {
    add_input_to_first_action_step "$WORK/README.md" "bogus-input: true"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "input 'bogus-input' does not exist in action.yml" || return 1
}

@test "mutation: a made up input in an example fails the check" {
    add_input_to_first_action_step "$WORK/examples/complete-workflow.yml" "bogus-input: true"
    validate_file "$WORK/examples/complete-workflow.yml"
    [ "$status" -ne 0 ]
    assert_contains "input 'bogus-input' does not exist in action.yml" || return 1
}

@test "mutation: a v2 input name in the README fails the check" {
    add_input_to_first_action_step "$WORK/README.md" "build-dir: dist"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "input 'build-dir' is a v2 name, use paths" || return 1
}

@test "mutation: the action at @v2 fails the check" {
    replace_first_line "$WORK/README.md" "miguelcolmenares/npm-auto-build@v3" "      - uses: miguelcolmenares/npm-auto-build@v2"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "must end in @v3, @main or a 40 character commit SHA" || return 1
}

@test "mutation: an unknown mode fails the check" {
    replace_first_line "$WORK/README.md" "mode: check" "          mode: deploy"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "mode 'deploy' is not one of" || return 1
}

@test "mutation: no persist-credentials false on the checkout fails the check" {
    delete_first_line "$WORK/README.md" "persist-credentials: false"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "persist-credentials: false" || return 1
}

@test "mutation: a missing contents write permission fails the check" {
    replace_first_line "$WORK/README.md" "contents: write" "  contents: read"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "needs 'permissions: contents: write'" || return 1
}

@test "mutation: an old checkout and an old Node.js fail the check" {
    replace_first_line "$WORK/README.md" "actions/checkout@v7" "      - uses: actions/checkout@v5"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "older than actions/checkout@v7" || return 1

    cp "$REPO_ROOT/README.md" "$WORK/README.md"
    add_input_to_first_action_step "$WORK/README.md" "node-version: 18"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "node-version '18' is older than 22" || return 1
}

@test "mutation: a changed default in the inputs table fails the check" {
    replace_first_line "$WORK/README.md" '| `node-version` |' '| `node-version` | `20` | Node.js version. |'
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "input 'node-version' shows default '20', action.yml has '24'" || return 1
}

@test "mutation: an input missing from the inputs table fails the check" {
    delete_first_line "$WORK/README.md" '| `artifact-name` |'
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "the inputs table has no row for 'artifact-name'" || return 1
}

@test "mutation: an output missing from the outputs table fails the check" {
    delete_first_line "$WORK/README.md" '| `commit-sha` |'
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "the outputs table has no row for 'commit-sha'" || return 1
}

@test "mutation: a mode without an example fails the check" {
    # Turn the only use of mode: build into mode: check.
    replace_first_line "$WORK/README.md" "mode: build" "          mode: check"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "no example uses mode 'build'" || return 1
}

@test "mutation: invalid YAML fails the check" {
    replace_first_line "$WORK/README.md" "      - uses: miguelcolmenares/npm-auto-build@v3" "      - uses: [miguelcolmenares/npm-auto-build@v3"
    validate_readme
    [ "$status" -ne 0 ]
    assert_contains "not valid YAML" || return 1
}

# --- what the check accepts -------------------------------------------------------------

@test "the references @v3, @main and a 40 character SHA are accepted, others are not" {
    local ref sha="0123456789abcdef0123456789abcdef01234567"
    for ref in v3 main "$sha"; do
        sed "s#npm-auto-build@v3#npm-auto-build@$ref#" "$REPO_ROOT/examples/monorepo.yml" >"$WORK/ref.yml"
        validate_file "$WORK/ref.yml"
        [ "$status" -eq 0 ] || { echo "@$ref should pass"; echo "$output"; return 1; }
    done
    for ref in v2 v3.0.0 v4 master "${sha}0" "${sha%?}"; do
        sed "s#npm-auto-build@v3#npm-auto-build@$ref#" "$REPO_ROOT/examples/monorepo.yml" >"$WORK/ref.yml"
        validate_file "$WORK/ref.yml"
        [ "$status" -ne 0 ] || { echo "@$ref should fail"; echo "$output"; return 1; }
    done
}

@test "a block with the skip marker is not checked, and is counted" {
    cat >"$WORK/skip.md" <<'EOF'
<!-- docs-examples: skip -->
```yaml
- uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: x
```

```yaml
- uses: miguelcolmenares/npm-auto-build@v3
  with:
    bogus-input: x
```
EOF
    validate_file "$WORK/skip.md"
    [ "$status" -ne 0 ]
    assert_contains "1 skipped" || return 1
    assert_contains "bogus-input" || return 1
    # The skipped block is the v2 one, so its v2 name is not among the errors.
    case "$output" in
        *"github-token"*) echo "$output"; return 1 ;;
    esac
}

@test "a file without a YAML snippet fails, so a moved example is noticed" {
    printf '# Title\n\nNo example here.\n' >"$WORK/none.md"
    validate_file "$WORK/none.md"
    [ "$status" -ne 0 ]
    assert_contains "no YAML snippet found" || return 1
}

@test "mode pr needs pull-requests write with the default token, and not with an own token" {
    cat >"$WORK/pr.yml" <<'EOF'
on: push
permissions:
  contents: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: pr
EOF
    validate_file "$WORK/pr.yml"
    [ "$status" -ne 0 ]
    assert_contains "permissions: pull-requests: write" || return 1

    sed 's#mode: pr#mode: pr\n          token: ${{ secrets.BOT }}#' "$WORK/pr.yml" >"$WORK/pr-token.yml"
    validate_file "$WORK/pr-token.yml"
    [ "$status" -eq 0 ]
}

@test "the validator imports nothing that could run or fetch anything" {
    # The docs say the check is structural and never runs the action. This keeps the script
    # honest: it only parses text.
    run grep -nE 'import (subprocess|socket|urllib|requests|http)|os\.system|eval\(|exec\(' "$VALIDATOR"
    [ "$status" -ne 0 ]
}

# bats test_tags=post-release
@test "the docs stop saying that @v3 is not released once a v3 tag exists" {
    # The docs say "@v3 is available after the v3 release", and SECURITY.md says "Not released yet". Those
    # sentences are promises with no date, so they must go with the release (docs/releasing.md lists them,
    # and scripts/release-check.sh prints them as TODO lines). This test fails once a v3 tag exists and a
    # sentence is still in a doc. The CHANGELOG is history and is not checked. A shallow clone without tags
    # cannot see the tag, so the check runs where the tags are fetched, such as a local clone. The release
    # workflow runs at the tag, before the docs are changed, so it leaves this test out with its tag
    # `post-release`: `bats --filter-tags '!post-release' tests/`.
    local tags doc
    tags=$(git -C "$REPO_ROOT" tag -l 'v3' 'v3.*')
    [ -z "$tags" ] || {
        for doc in README.md examples/README.md "$REPO_ROOT"/docs/*.md; do
            doc=${doc#"$REPO_ROOT"/}
            # docs/releasing.md quotes the sentence, because it is the procedure that removes it.
            [ "$doc" != docs/releasing.md ] || continue
            if grep -q 'after the v3 release' "$REPO_ROOT/$doc"; then
                echo "$doc still says that @v3 is not released, and the tag exists: $tags" >&2
                return 1
            fi
        done
        if grep -q 'Not released yet' "$REPO_ROOT/SECURITY.md"; then
            echo "SECURITY.md still says that v3 is not released, and the tag exists: $tags" >&2
            return 1
        fi
        # The home page of the docs site says "in development" in the same way.
        if grep -q 'in development' "$REPO_ROOT/site/sitekit.config.json"; then
            echo "site/sitekit.config.json still says that v3 is in development, and the tag exists: $tags" >&2
            return 1
        fi
    }
}

# --- the pages of the docs site ----------------------------------------------------------

@test "the pages of the docs site, their reference table and the site config pass" {
    run python3 "$VALIDATOR" --tables "$REPO_ROOT/docs/reference.md" --site-config "$REPO_ROOT/site/sitekit.config.json" \
        --require-modes "$REPO_ROOT/docs/getting-started.md" "$REPO_ROOT"/docs/mode-*.md \
        "$REPO_ROOT/docs/example-workflows.md" "$REPO_ROOT/docs/breaking-changes.md"
    [ "$status" -eq 0 ]
    assert_contains "0 errors" || return 1
    # The one skipped block is the v2 "stay on v2" snippet of the breaking changes page.
    assert_contains "1 skipped" || return 1
}

@test "mutation: a made up input in a page of the docs site fails the check" {
    add_input_to_first_action_step "$WORK/docs/mode-check.md" "bogus-input: true"
    run python3 "$VALIDATOR" "$WORK/docs/mode-check.md"
    [ "$status" -ne 0 ]
    assert_contains "input 'bogus-input' does not exist in action.yml" || return 1
}

@test "mutation: a getting started page without persist-credentials false fails the check" {
    delete_first_line "$WORK/docs/getting-started.md" "persist-credentials: false # the build cannot"
    run python3 "$VALIDATOR" "$WORK/docs/getting-started.md"
    [ "$status" -ne 0 ]
    assert_contains "persist-credentials: false" || return 1
}

@test "mutation: a changed default in the generated reference table fails the check" {
    replace_first_line "$WORK/docs/reference.md" '| `node-version` |' '| `node-version` | `20` |'
    run python3 "$VALIDATOR" --tables "$WORK/docs/reference.md" "$REPO_ROOT/examples/quick-start.yml"
    [ "$status" -ne 0 ]
    assert_contains "input 'node-version' shows default '20', action.yml has '24'" || return 1
}

@test "mutation: an install command of the home page at @v2 fails the check" {
    replace_first_line "$WORK/site/sitekit.config.json" '"installCommand"' '    "installCommand": "uses: miguelcolmenares/npm-auto-build@v2",'
    run python3 "$VALIDATOR" --site-config "$WORK/site/sitekit.config.json" "$REPO_ROOT/examples/quick-start.yml"
    [ "$status" -ne 0 ]
    assert_contains "must end in @v3, @main or a 40 character commit SHA" || return 1
}

@test "mutation: a home page without the card of a mode fails the check" {
    replace_first_line "$WORK/site/sitekit.config.json" '"eyebrow": "mode: build"' '      "eyebrow": "mode: deploy",'
    run python3 "$VALIDATOR" --site-config "$WORK/site/sitekit.config.json" "$REPO_ROOT/examples/quick-start.yml"
    [ "$status" -ne 0 ]
    assert_contains "no card with the eyebrow 'mode: build'" || return 1
    assert_contains "'mode: deploy' is not one of the modes" || return 1
}
