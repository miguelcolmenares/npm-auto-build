#!/usr/bin/env bats
# scripts/release-check.sh against a throwaway repository: a bare "origin", a clone that is
# ready for the release 3.0.0, and a stand-in `gh` that answers from files. The first test
# is the all-green case. Every other test breaks one rule on purpose and expects exactly one
# FAIL line for it, so each rule is seen failing (a rule that cannot fail proves nothing).
# The script is read only, a test checks that nothing in the repository or the remote moved.
#
# bash 3.2 (macOS): a bare [[ ]] or `! cmd` in a test body does not fail the test, so the
# checks use `run` with the status, [ ] tests and `|| false`.

load helpers

CHECK="$SCRIPTS/release-check.sh"

# A fresh origin and a clone that is ready for 3.0.0: every item of the script passes.
setup() {
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    WORK="$BATS_TEST_TMPDIR/work"
    FAKE_GH_DIR="$BATS_TEST_TMPDIR/gh-data"
    export FAKE_GH_DIR
    mkdir -p "$FAKE_GH_DIR" "$BATS_TEST_TMPDIR/bin"

    git init -q --bare --initial-branch=main "$ORIGIN"
    git init -q --initial-branch=main "$WORK"
    cd "$WORK"
    git remote add origin "$ORIGIN"
    mkdir -p .github/workflows docs examples
    cat >CHANGELOG.md <<'EOF'
# Changelog

## [Unreleased]

## [3.0.0] - 2026-11-20

### Added
- The composite action.

## [2.1.2] - 2025-11-10

### Fixed
- Something.
EOF
    printf '{\n  "name": "x",\n  "version": "3.0.0"\n}\n' >package.json
    printf '{\n  "name": "x",\n  "version": "3.0.0",\n  "packages": {\n    "": {\n      "version": "3.0.0"\n    }\n  }\n}\n' >package-lock.json
    printf '# Security\n\n| v3 | Supported |\n' >SECURITY.md
    cat >action.yml <<'EOF'
name: "Example Action"
description: "Build your project and commit the output, so you do not commit dist/ by hand."
runs:
  using: composite
  steps:
    - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
      with:
        node-version: "24"
branding:
  icon: "package"
  color: "blue"
EOF
    cat >.github/workflows/ci.yml <<'EOF'
name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ./
EOF
    git add -A
    git -c commit.gpgsign=false commit -q -m "ready"
    git tag v2
    git push -q origin main v2

    # The stand-in gh. It prints what `gh api ... --jq` would print, from the files of FAKE_GH_DIR.
    printf 'shellcheck\nbats\ndependency-review\n' >"$FAKE_GH_DIR/contexts"
    printf 'shellcheck\tcompleted\tsuccess\nbats\tcompleted\tsuccess\nother\tcompleted\tfailure\n' >"$FAKE_GH_DIR/runs"
    printf 'identical\n' >"$FAKE_GH_DIR/compare"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Stand-in for gh: answers a GET of the three endpoints from files. Never writes.
case "$*" in
    *"api"*"required_status_checks"*)
        [ ! -f "$FAKE_GH_DIR/fail-contexts" ] || { echo "HTTP 403" >&2; exit 1; }
        cat "$FAKE_GH_DIR/contexts" ;;
    *"api"*"check-runs"*) cat "$FAKE_GH_DIR/runs" ;;
    *"api"*"compare"*) cat "$FAKE_GH_DIR/compare" ;;
    *) echo "unexpected gh call: $*" >&2; exit 2 ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Commit what changed in the work tree and push it, so the tree stays clean and equal to origin.
commit_push() {
    git add -A
    git -c commit.gpgsign=false commit -q -m "change"
    git push -q origin main
}

# A snapshot of everything a read only script must leave alone.
snapshot() {
    {
        git -C "$WORK" status --porcelain
        git -C "$WORK" for-each-ref
        git -C "$ORIGIN" for-each-ref
        git -C "$WORK" rev-parse HEAD
    }
}

# Run the check and expect it to fail with exactly one FAIL line that has the given text.
expect_one_fail() {
    run bash "$CHECK" "${@:2}"
    [ "$status" -eq 1 ] || {
        echo "expected exit 1, got $status" >&2
        echo "$output" >&2
        return 1
    }
    local count
    count=$(printf '%s\n' "$output" | grep -c '^FAIL' || true)
    [ "$count" -eq 1 ] || {
        echo "expected exactly 1 FAIL line, got $count" >&2
        echo "$output" >&2
        return 1
    }
    printf '%s\n' "$output" | grep -F "FAIL  " | grep -qF -- "$1" || {
        echo "the FAIL line does not say: $1" >&2
        echo "$output" >&2
        return 1
    }
}

has() {
    printf '%s\n' "$output" | grep -qF -- "$1" || {
        echo "the output does not have: $1" >&2
        echo "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# The green case, and that the script only reads

@test "a repository that is ready: every item passes, exit 0, one skip for the pull request only check" {
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
    has "Result: 0 FAIL, 1 SKIP, 0 TODO"
    has 'PASS  CHANGELOG.md has the dated section [3.0.0]'
    has 'PASS  Nothing is left under [Unreleased]'
    has 'PASS  package.json has the version 3.0.0'
    has 'PASS  package-lock.json has the version 3.0.0'
    has 'PASS  SECURITY.md has no TBD'
    has 'PASS  The description of action.yml has'
    has 'PASS  action.yml has branding'
    has 'PASS  Every uses: is pinned by a 40 character SHA (3 checked)'
    has 'PASS  The tag v3.0.0 does not exist here'
    has 'PASS  The tag v3.0.0 does not exist on origin'
    has 'PASS  The floating tag v3 does not exist yet'
    has 'PASS  The tag v2 exists on origin and stays as it is'
    has 'PASS  The working tree is clean'
    has 'PASS  On the branch main'
    has 'PASS  All 2 required checks are green'
    has 'SKIP  Required check "dependency-review" runs on pull requests only'
}

@test "the check changes nothing: the work tree, the refs and the remote are the same after a run" {
    local before after
    before=$(snapshot)
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ]
    run bash "$CHECK" --tag 3.0.0
    after=$(snapshot)
    [ "$before" = "$after" ] || {
        echo "before:" >&2
        echo "$before" >&2
        echo "after:" >&2
        echo "$after" >&2
        return 1
    }
}

@test "a version that is not like 3.0.0 fails, and no argument is a usage error" {
    run bash "$CHECK" three
    [ "$status" -eq 1 ]
    has 'is not like 3.0.0'
    run bash "$CHECK"
    [ "$status" -eq 2 ]
    run bash "$CHECK" --tag
    [ "$status" -eq 2 ]
}

@test "a leading v on the version is accepted" {
    run bash "$CHECK" v3.0.0
    [ "$status" -eq 0 ]
    has 'PASS  CHANGELOG.md has the dated section [3.0.0]'
}

# ---------------------------------------------------------------------------
# CHANGELOG.md

@test "FAIL: the CHANGELOG has no section for the version" {
    sed 's/^## \[3.0.0\] - 2026-11-20$/## [3.0.1] - 2026-11-20/' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has 'FAIL  CHANGELOG.md has no section [3.0.0]'
}

@test "FAIL: the section of the version has no date" {
    sed 's/^## \[3.0.0\] - 2026-11-20$/## [3.0.0]/' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    expect_one_fail "has no date" 3.0.0
}

@test "FAIL: the date is not a date" {
    sed 's/2026-11-20/2026-13-45/' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    expect_one_fail "has no date" 3.0.0
}

@test "FAIL: the section of the version is empty" {
    awk '/^## \[3.0.0\]/ { print; print ""; skip = 1; next } /^## \[2.1.2\]/ { skip = 0 } !skip' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    expect_one_fail "is empty" 3.0.0
}

@test "FAIL: an entry is left under [Unreleased]" {
    sed 's/^## \[Unreleased\]$/## [Unreleased]\n\n### Added\n- Something new./' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    expect_one_fail "left under [Unreleased]" 3.0.0
}

@test "FAIL: the intro text of [Unreleased] counts as left over too" {
    sed 's/^## \[Unreleased\]$/## [Unreleased]\n\nNothing is released yet./' CHANGELOG.md >c && mv c CHANGELOG.md
    commit_push
    expect_one_fail "left under [Unreleased]" 3.0.0
}

@test "FAIL: there is no CHANGELOG.md" {
    git rm -q CHANGELOG.md
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has 'FAIL  CHANGELOG.md does not exist'
}

# ---------------------------------------------------------------------------
# Versions, SECURITY.md, action.yml, pins

@test "FAIL: package.json has another version" {
    sed 's/"version": "3.0.0"/"version": "2.1.2"/' package.json >c && mv c package.json
    commit_push
    expect_one_fail 'package.json has the version "2.1.2", expected 3.0.0' 3.0.0
}

@test "FAIL: package-lock.json has another version" {
    sed 's/"version": "3.0.0"/"version": "2.1.2"/' package-lock.json >c && mv c package-lock.json
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has 'FAIL  package-lock.json has the version "2.1.2", expected 3.0.0'
}

@test "FAIL: SECURITY.md still has a TBD" {
    printf '| v2 | Sunset: TBD |\n' >>SECURITY.md
    commit_push
    expect_one_fail "SECURITY.md still has a TBD" 3.0.0
}

@test "FAIL: the description is one character over the limit, and 125 characters pass" {
    local d125 d126
    d125=$(printf 'a%.0s' $(seq 1 125))
    d126=${d125}a
    sed "s/^description: .*/description: \"$d125\"/" action.yml >c && mv c action.yml
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ]
    has "has 125 characters"
    sed "s/^description: .*/description: \"$d126\"/" action.yml >c && mv c action.yml
    commit_push
    expect_one_fail "has 126 characters, the most is 125" 3.0.0
}

@test "FAIL: the description is empty" {
    sed 's/^description: .*/description: ""/' action.yml >c && mv c action.yml
    commit_push
    expect_one_fail "description of action.yml is empty" 3.0.0
}

@test "FAIL: the description is a block and not one line" {
    sed 's/^description: .*/description: >\n  Build your project./' action.yml >c && mv c action.yml
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has "is a block, write it as one quoted line"
}

@test "FAIL: action.yml has no branding" {
    sed '/^branding:/,$d' action.yml >c && mv c action.yml
    commit_push
    expect_one_fail "no branding icon and color" 3.0.0
}

@test "FAIL: action.yml has a branding icon and no color" {
    sed '/color:/d' action.yml >c && mv c action.yml
    commit_push
    expect_one_fail "no branding icon and color" 3.0.0
}

@test "FAIL: a workflow uses an action by tag, not by SHA" {
    sed 's#actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 \# v7.0.1#actions/checkout@v7#' .github/workflows/ci.yml >c && mv c .github/workflows/ci.yml
    commit_push
    expect_one_fail "A uses: is not pinned" 3.0.0
    has "ci.yml:7: actions/checkout@v7"
}

@test "FAIL: action.yml uses an action by a short SHA" {
    sed 's#actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1#actions/setup-node@949feb2#' action.yml >c && mv c action.yml
    commit_push
    expect_one_fail "A uses: is not pinned" 3.0.0
}

# ---------------------------------------------------------------------------
# Tags

@test "FAIL: the tag exists here" {
    git tag v3.0.0
    expect_one_fail "The tag v3.0.0 already exists here" 3.0.0
}

@test "FAIL: the tag exists on the remote only" {
    git tag v3.0.0
    git push -q origin v3.0.0
    git tag -d v3.0.0 >/dev/null
    expect_one_fail "The tag v3.0.0 already exists on origin" 3.0.0
}

@test "FAIL: the floating tag v3 exists before the first v3 release" {
    git tag v3
    git push -q origin v3
    expect_one_fail "The floating tag v3 already exists" 3.0.0
}

@test "FAIL: the tag of the previous major is not on the remote" {
    git push -q origin :refs/tags/v2
    expect_one_fail "The tag v2 does not exist on origin" 3.0.0
}

@test "a release that is not X.0.0 does not look for the floating tag or the previous major" {
    sed -i.bak 's/3\.0\.0/3.1.0/g' CHANGELOG.md package.json package-lock.json && rm -f ./*.bak
    git push -q origin :refs/tags/v2
    git tag v3
    git push -q origin v3
    commit_push
    run bash "$CHECK" 3.1.0
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
}

@test "FAIL: the remote cannot be read" {
    git remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has "Cannot read the tags of the remote origin"
    has "Cannot read main on the remote origin"
}

# ---------------------------------------------------------------------------
# The work tree and the branch

@test "FAIL: the work tree has a change that is not committed" {
    echo more >>README.md
    expect_one_fail "The working tree has changes" 3.0.0
    has "?? README.md"
}

@test "FAIL: a tracked file is modified" {
    echo more >>SECURITY.md
    expect_one_fail "The working tree has changes" 3.0.0
}

@test "FAIL: the branch is not main" {
    git checkout -q -b other
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has 'FAIL  On "other", not on main'
}

@test "FAIL: a detached HEAD is not main" {
    git checkout -q --detach
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 1 ]
    has 'FAIL  On "a detached HEAD", not on main'
}

@test "FAIL: main is behind the remote" {
    git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/other"
    (
        cd "$BATS_TEST_TMPDIR/other"
        echo x >x.txt
        git add x.txt
        git -c commit.gpgsign=false commit -q -m other
        git push -q origin main
    )
    expect_one_fail "pull or push first" 3.0.0
}

@test "FAIL: main is ahead of the remote" {
    echo x >x.txt
    git add x.txt
    git -c commit.gpgsign=false commit -q -m local
    expect_one_fail "pull or push first" 3.0.0
}

# ---------------------------------------------------------------------------
# The required checks

@test "FAIL: a required check failed" {
    printf 'shellcheck\tcompleted\tfailure\nbats\tcompleted\tsuccess\n' >"$FAKE_GH_DIR/runs"
    expect_one_fail "1 of 2 required checks are green" 3.0.0
    has "shellcheck: completed/failure"
}

@test "FAIL: a required check is still running" {
    printf 'shellcheck\tcompleted\tsuccess\nbats\tin_progress\tnone\n' >"$FAKE_GH_DIR/runs"
    expect_one_fail "1 of 2 required checks are green" 3.0.0
    has "bats: in_progress/none"
}

@test "FAIL: a required check has no run for this commit" {
    printf 'shellcheck\tcompleted\tsuccess\n' >"$FAKE_GH_DIR/runs"
    expect_one_fail "1 of 2 required checks are green" 3.0.0
    has "bats: no run"
}

@test "a required check that failed once and passed on the re-run counts as green" {
    printf 'bats\tcompleted\tfailure\nshellcheck\tcompleted\tsuccess\nbats\tcompleted\tsuccess\n' >"$FAKE_GH_DIR/runs"
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ]
    has "All 2 required checks are green"
}

@test "a check that is not required does not count, even when it failed" {
    # The default runs of the fixture have a failed check named other, and the green case passes.
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qF 'other' && {
        echo "the check named other should not be in the output" >&2
        return 1
    }
    return 0
}

@test "FAIL: the required checks cannot be read" {
    : >"$FAKE_GH_DIR/fail-contexts"
    expect_one_fail "Cannot read the required checks of main" 3.0.0
}

@test "FAIL: the branch has no required check at all" {
    : >"$FAKE_GH_DIR/contexts"
    expect_one_fail "has no required status checks" 3.0.0
}

@test "SKIP: gh is not installed, and the skip is not a pass" {
    local bin="$BATS_TEST_TMPDIR/nogh" tool
    mkdir -p "$bin"
    for tool in git awk sed grep head sh bash cat sort tr dirname basename env seq; do
        ln -s "$(command -v "$tool")" "$bin/$tool"
    done
    PATH="$bin" run "$BASH" "$CHECK" 3.0.0
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
    has "SKIP  Required status checks: gh is not installed"
    has "Result: 0 FAIL, 1 SKIP"
}

# ---------------------------------------------------------------------------
# At tag time

@test "tag mode: the tag points at the checked out commit and the commit is on main" {
    git tag v3.0.0
    run bash "$CHECK" --tag 3.0.0
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
    has "Release check for v3.0.0 (at tag time)"
    has "PASS  The tag v3.0.0 points at the checked out commit"
    has "PASS  The tagged commit"
    has "Result: 0 FAIL, 0 SKIP, 0 TODO"
}

@test "tag mode does not need a clean tree, the branch main or a green list of checks" {
    git tag v3.0.0
    git checkout -q --detach
    echo more >>README.md
    printf 'shellcheck\tcompleted\tfailure\n' >"$FAKE_GH_DIR/runs"
    run bash "$CHECK" --tag 3.0.0
    [ "$status" -eq 0 ]
}

@test "tag mode FAIL: the tag is not in the checkout" {
    run bash "$CHECK" --tag 3.0.0
    [ "$status" -eq 1 ]
    has "FAIL  The tag v3.0.0 is not in this checkout"
}

@test "tag mode FAIL: the tag points at another commit than the checkout" {
    git tag v3.0.0
    echo x >x.txt
    git add x.txt
    git -c commit.gpgsign=false commit -q -m later
    expect_one_fail "The tag v3.0.0 points at" --tag 3.0.0
}

@test "tag mode FAIL: the tagged commit is not on main" {
    git tag v3.0.0
    printf 'ahead\n' >"$FAKE_GH_DIR/compare"
    expect_one_fail "is not on main (compare says: ahead)" --tag 3.0.0
}

@test "tag mode FAIL: the CHANGELOG has no date for the tag" {
    git tag v3.0.0
    sed 's/^## \[3.0.0\] - 2026-11-20$/## [3.0.0]/' CHANGELOG.md >CHANGELOG.new && mv CHANGELOG.new CHANGELOG.md
    commit_push
    git tag -f v3.0.0 >/dev/null
    expect_one_fail "has no date" --tag 3.0.0
}

@test "tag mode FAIL: the tag is not the version of package.json" {
    git tag v3.0.1
    run bash "$CHECK" --tag 3.0.1
    [ "$status" -eq 1 ]
    has "FAIL  CHANGELOG.md has no section [3.0.1]"
    has 'FAIL  package.json has the version "3.0.0", expected 3.0.1'
}

@test "tag mode SKIP: gh is not installed" {
    local bin="$BATS_TEST_TMPDIR/nogh" tool
    git tag v3.0.0
    mkdir -p "$bin"
    for tool in git awk sed grep head sh bash cat sort tr dirname basename env seq; do
        ln -s "$(command -v "$tool")" "$bin/$tool"
    done
    PATH="$bin" run "$BASH" "$CHECK" --tag 3.0.0
    [ "$status" -eq 0 ]
    has "SKIP  HEAD is on main: gh is not installed"
}

# ---------------------------------------------------------------------------
# After the release

@test "TODO: the sentences that wait for the release are listed, and they are not a failure" {
    printf 'The tag @v3 is available after the v3 release.\n' >README.md
    printf 'Also available after the v3 release, and again: available after the v3 release.\n' >docs/recipes.md
    printf '| v3 | Not released yet |\n' >>SECURITY.md
    commit_push
    run bash "$CHECK" 3.0.0
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
    has "TODO  After the release, remove the 2 sentence(s) that say @v3 is available after the release: README.md docs/recipes.md"
    has "TODO  After the release, change the v3 row of SECURITY.md"
    has "Result: 0 FAIL, 1 SKIP, 2 TODO"
}
