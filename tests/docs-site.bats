#!/usr/bin/env bats
# The docs site (issue #12). Three kinds of checks:
#
#   * tests/docs-generated.py: docs/reference.md is generated from action.yml, and a page shows
#     the same file as the examples/ file it names. Both must fail when they go stale, and each
#     test below breaks a scratch copy to prove it.
#   * The breaking changes page against the migration guide and action.yml.
#   * The security page against SECURITY.md.
#
# These tests only read files. They do not run the action and they do not build the site: the
# Docs workflow builds the site and runs the credential and link checks of docs-sitekit.
#
# Bash 3.2 (macOS) does not fail a test on a bare [[ ]] or `! cmd`, so every check here is a
# function that returns 1, or a [ ] test.

load helpers

GENERATOR="$REPO_ROOT/tests/docs-generated.py"

setup() {
    if ! python3 -c 'import yaml' 2>/dev/null; then
        if [ -n "${CI:-}" ]; then
            echo "PyYAML is missing in CI: install python3-yaml" >&2
            return 1
        fi
        skip "PyYAML is not installed (python3 -m pip install pyyaml)"
    fi
    ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$ROOT/docs" "$ROOT/examples"
    cp "$REPO_ROOT/action.yml" "$ROOT/action.yml"
    cp "$REPO_ROOT"/docs/*.md "$ROOT/docs/"
    cp "$REPO_ROOT"/examples/* "$ROOT/examples/"
    cp "$REPO_ROOT/SECURITY.md" "$ROOT/SECURITY.md"
    mkdir -p "$ROOT/docs/audits"
    cp "$REPO_ROOT"/docs/audits/*.md "$ROOT/docs/audits/"
}

assert_contains() {
    case "$output" in
        *"$1"*) return 0 ;;
    esac
    echo "expected the output to contain: $1"
    echo "$output"
    return 1
}

# Replace the first line of a file that contains $2 with $3, as plain text.
replace_first_line() {
    local file=$1 needle=$2 replacement=$3 tmp="$1.tmp"
    NEEDLE="$needle" REPLACEMENT="$replacement" awk '
        !done && index($0, ENVIRON["NEEDLE"]) { print ENVIRON["REPLACEMENT"]; done = 1; next }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    grep -qF -- "$replacement" "$file"
}

# --- the generated docs as they are -----------------------------------------------------

@test "the generated docs of the repository are up to date" {
    run python3 "$GENERATOR"
    [ "$status" -eq 0 ]
    assert_contains "0 stale" || return 1
    assert_contains "0 problems" || return 1
}

@test "every file of examples/ is shown by a page" {
    run python3 "$GENERATOR"
    [ "$status" -eq 0 ]
    local count
    count=$(ls "$REPO_ROOT"/examples/*.yml | wc -l | tr -d ' ')
    assert_contains "$count examples shown" || return 1
}

@test "the reference page names every input and output of action.yml" {
    local name
    for name in $(ruby -ryaml -e 'a = YAML.safe_load(File.read(ARGV[0])); puts a["inputs"].keys + a["outputs"].keys' "$REPO_ROOT/action.yml"); do
        grep -qF -- "\`$name\`" "$REPO_ROOT/docs/reference.md" || { echo "docs/reference.md does not name $name"; return 1; }
    done
}

# --- mutation proofs: break a scratch copy, the check must fail -------------------------

@test "mutation: a new input in action.yml makes the reference page stale" {
    printf '  brand-new-input:\n    description: "A made up input."\n    required: false\n    default: "x"\n' >"$BATS_TEST_TMPDIR/input.txt"
    awk 'FNR == NR { extra = extra $0 "\n"; next } { print } /^inputs:/ { printf "%s", extra }' "$BATS_TEST_TMPDIR/input.txt" "$ROOT/action.yml" >"$ROOT/action.new"
    mv "$ROOT/action.new" "$ROOT/action.yml"
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "docs/reference.md is stale" || return 1
}

@test "mutation: a changed default in action.yml makes the reference page stale" {
    replace_first_line "$ROOT/action.yml" 'default: "24"' '    default: "20"'
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "docs/reference.md is stale" || return 1
}

@test "mutation: a hand edit of the reference page is found" {
    replace_first_line "$ROOT/docs/reference.md" '| `mode` |' '| `mode` | `check` |'
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "docs/reference.md is stale" || return 1
}

@test "mutation: an example file that changed makes the pages that show it stale" {
    printf '# a new comment\n' >>"$ROOT/examples/quick-start.yml"
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "docs/getting-started.md is stale" || return 1
    assert_contains "docs/example-workflows.md is stale" || return 1
}

@test "mutation: a page that shows a different copy of an example is found" {
    replace_first_line "$ROOT/docs/mode-check.md" "mode: check" "          mode: build"
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "docs/mode-check.md is stale" || return 1
}

@test "mutation: --write repairs the stale pages, and then the check passes" {
    printf '# a new comment\n' >>"$ROOT/examples/check.yml"
    replace_first_line "$ROOT/docs/reference.md" '| `mode` |' '| `mode` | `check` |'
    run python3 "$GENERATOR" --root "$ROOT" --write
    [ "$status" -eq 0 ]
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -eq 0 ]
    grep -qF "# a new comment" "$ROOT/docs/mode-check.md"
}

@test "mutation: a new example file that no page shows is found" {
    cp "$ROOT/examples/check.yml" "$ROOT/examples/another.yml"
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "examples/another.yml is not shown by any page" || return 1
}

@test "mutation: a marker with no fence after it is found" {
    replace_first_line "$ROOT/docs/mode-build.md" '```yaml' 'no fence here'
    run python3 "$GENERATOR" --root "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "is not followed by a \`\`\`yaml fence" || return 1
}

@test "the generator reads and writes text only" {
    run grep -nE 'import (subprocess|socket|urllib|requests|http)|os\.system|eval\(|exec\(' "$GENERATOR"
    [ "$status" -ne 0 ]
}

# --- the breaking changes page ----------------------------------------------------------
# Each check is a function on the files under $1, so a test can run it on a broken copy.

# Every v2 alias of action.yml has a row in the page and in the migration guide.
check_aliases() {
    local root=$1 alias
    for alias in $(ruby -ryaml -e 'a = YAML.safe_load(File.read(ARGV[0])); puts a["inputs"].select { |_, v| v["description"].start_with?("Deprecated") }.keys' "$root/action.yml"); do
        grep -qF -- "| \`$alias" "$root/docs/breaking-changes.md" || { echo "docs/breaking-changes.md has no row for the v2 input $alias"; return 1; }
        grep -qF -- "| \`$alias" "$root/docs/migration-v2-to-v3.md" || { echo "docs/migration-v2-to-v3.md has no row for the v2 input $alias"; return 1; }
    done
}

# Each phrase is one breaking change that issue #10 lists. The migration guide has them too.
check_contract() {
    local root=$1 phrase
    for phrase in \
        "composite" \
        "Node 24" \
        "node-version" \
        "No guessing of the build directory" \
        "A detached HEAD is an error" \
        "one pull request" \
        "mode: build" \
        "mode: pr" \
        "persist-credentials: false" \
        "Stay on v2"; do
        grep -qF -- "$phrase" "$root/docs/breaking-changes.md" || { echo "docs/breaking-changes.md does not mention: $phrase"; return 1; }
    done
}

# Every link of the page to a heading of the migration guide finds that heading.
check_anchors() {
    local root=$1 anchor slug found heading
    for anchor in $(grep -o 'migration-v2-to-v3\.md#[a-z0-9-]*' "$root/docs/breaking-changes.md" | sed 's/.*#//' | sort -u); do
        found=0
        while IFS= read -r heading; do
            slug=$(printf '%s' "$heading" | sed 's/^#* *//' | tr 'A-Z' 'a-z' | tr -d '`,.:' | tr ' ' '-')
            [ "$slug" = "$anchor" ] && found=1
        done < <(grep '^#' "$root/docs/migration-v2-to-v3.md")
        [ "$found" -eq 1 ] || { echo "the migration guide has no heading for #$anchor"; return 1; }
    done
}

@test "the breaking changes page lists every v2 alias of action.yml, and the guide lists the same" {
    check_aliases "$ROOT"
}

@test "the breaking changes page names every change of the v3 contract of issue 10" {
    check_contract "$ROOT"
}

@test "every link of the breaking changes page to the migration guide points at a heading that exists" {
    check_anchors "$ROOT"
}

@test "mutation: a v2 alias without a row in the page is found" {
    grep -v '^| `build-dir`' "$ROOT/docs/breaking-changes.md" >"$ROOT/page.tmp"
    mv "$ROOT/page.tmp" "$ROOT/docs/breaking-changes.md"
    run check_aliases "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "no row for the v2 input build-dir" || return 1
}

@test "mutation: a breaking change that the page no longer names is found" {
    grep -v 'No guessing of the build directory' "$ROOT/docs/breaking-changes.md" >"$ROOT/page.tmp"
    mv "$ROOT/page.tmp" "$ROOT/docs/breaking-changes.md"
    run check_contract "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "does not mention: No guessing of the build directory" || return 1
}

@test "mutation: a link to a heading that the guide renamed is found" {
    replace_first_line "$ROOT/docs/migration-v2-to-v3.md" "### The action is composite, not Docker" "### The action is a composite action"
    run check_anchors "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "has no heading for #the-action-is-composite-not-docker" || return 1
}

# --- the security page ------------------------------------------------------------------

check_security() {
    local root=$1 phrase
    for phrase in \
        "Supported until v3.0.0 is published." \
        "From that day v2 gets no patches, and the \`v2\` tag stays as it is." \
        "We acknowledge a report within 7 days." \
        "within 7 days when its severity is high or critical, and within 30 days for the others"; do
        grep -qF -- "$phrase" "$root/SECURITY.md" || { echo "SECURITY.md does not say: $phrase"; return 1; }
        grep -qF -- "$phrase" "$root/docs/security.md" || { echo "docs/security.md does not say: $phrase"; return 1; }
    done
}

@test "the security page and SECURITY.md say the same about the supported versions" {
    check_security "$ROOT"
}

@test "mutation: a security policy that changes the v2 support is found" {
    replace_first_line "$ROOT/SECURITY.md" "Supported until v3.0.0 is published." "| v2 (\`v2\` tag and \`v2.x.x\`) | Security fixes only, until the sunset date."
    run check_security "$ROOT"
    [ "$status" -ne 0 ]
    assert_contains "SECURITY.md does not say: Supported until v3.0.0 is published." || return 1
}

@test "the security page links the threat model, the audit, the architecture and the policy" {
    local target
    for target in "./threat-model.md" "./audits/2026-11-12.md" "./architecture.md" "../SECURITY.md"; do
        grep -qF -- "($target)" "$ROOT/docs/security.md" || { echo "docs/security.md does not link $target"; return 1; }
    done
    [ -f "$ROOT/docs/audits/2026-11-12.md" ]
    grep -q '| T12 |' "$ROOT/docs/threat-model.md"
}
