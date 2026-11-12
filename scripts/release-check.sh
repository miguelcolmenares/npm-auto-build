#!/usr/bin/env bash
# Release readiness check. Maintainer tool, not part of the action: action.yml never runs it.
#
#   scripts/release-check.sh 3.0.0          before the tag: is the repository ready to release?
#   scripts/release-check.sh --tag 3.0.0    at tag time (the release workflow): is the tagged commit good?
#
# It prints one line per item, `PASS`, `FAIL` or `SKIP`, then the `TODO` lines (what to do after the
# release, never a failure) and a result line. The exit code is 1 when any item failed, 0 otherwise.
# A `SKIP` is not a pass: the item was not checked (for example `gh` is not installed). Docs: docs/releasing.md.
#
# Items, both modes: CHANGELOG.md has a dated section for the version and it is not empty, nothing is left
# under [Unreleased], package.json and package-lock.json carry the version, SECURITY.md has no TBD,
# the action.yml description (at most 125 characters) and its branding, every `uses:` is a 40 character SHA.
# Only before the tag: the tag does not exist (here and on the remote), the floating major tag does not exist
# yet for a X.0.0 release, the previous major tag still exists, the working tree is clean, HEAD is `main` and
# equals the remote `main`, and every required status check of `main` is green for HEAD.
# Only at tag time: the tag points at HEAD, and HEAD is on `main`.
#
# Environment: RELEASE_REMOTE (default origin), RELEASE_BRANCH (default main).
#
# May do: read files, run git (read only: rev-parse, status, ls-remote), run `gh api` for GET requests.
# May not: change the repository, a tag, a branch, a release or a setting; read a token; run the project's code.
set -euo pipefail

REMOTE=${RELEASE_REMOTE:-origin}
BRANCH=${RELEASE_BRANCH:-main}

# The Marketplace listing text is the description of action.yml. The publish form is reported to refuse more than
# 125 characters, and GitHub's public docs state no limit, so the check uses the lower number.
MAX_DESCRIPTION=125

# Required checks that run on pull requests only, so a push to main has no run of them to read.
PR_ONLY_CHECKS="dependency-review"

# The docs that promise `@v<major>` before it exists, and the SECURITY.md row that says "not released".
PROMISE_FILES="README.md docs/README.md docs/recipes.md docs/migration-v2-to-v3.md docs/testing.md examples/README.md"

FAILS=0
SKIPS=0
TODOS=""
TODO_COUNT=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() {
    printf 'FAIL  %s\n' "$*"
    FAILS=$((FAILS + 1))
}
skip() {
    printf 'SKIP  %s\n' "$*"
    SKIPS=$((SKIPS + 1))
}
detail() { printf '        %s\n' "$*"; }
todo() {
    TODOS="${TODOS}TODO  $*"$'\n'
    TODO_COUNT=$((TODO_COUNT + 1))
}

usage() {
    printf 'Usage: %s [--tag] VERSION   (for example 3.0.0)\n' "${0##*/}" >&2
    exit 2
}

MODE=preflight
case "${1:-}" in
    --tag)
        MODE=tag
        shift
        ;;
    -h | --help) usage ;;
esac
[ $# -eq 1 ] || usage
VERSION=${1#v}
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    printf 'FAIL  the version "%s" is not like 3.0.0 or 3.1.0-rc.1\n' "$1"
    exit 1
fi
TAG="v$VERSION"
MAJOR=${VERSION%%.*}
REST=${VERSION#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}
PATCH=${PATCH%%-*}

cd "$(git rev-parse --show-toplevel)"
HEAD_SHA=$(git rev-parse HEAD)
VERSION_RE=${VERSION//./\\.}

# The lines of a CHANGELOG section. $1 is the text inside the brackets of its heading.
changelog_section() {
    awk -v h="$1" '/^## \[/ { p = (index($0, "## [" h "]") == 1); next } p' CHANGELOG.md
}

nonblank_lines() {
    awk 'NF { n++ } END { print n + 0 }'
}

# The first value of a top level "version" key of a JSON file.
json_version() {
    sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

# ---------------------------------------------------------------------------
# Files in the repository

check_changelog() {
    if [ ! -f CHANGELOG.md ]; then
        fail "CHANGELOG.md does not exist"
        return
    fi
    if grep -Eq "^## \\[${VERSION_RE}\\] - [0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])\$" CHANGELOG.md; then
        pass "CHANGELOG.md has the dated section [$VERSION]"
        if [ "$(changelog_section "$VERSION" | nonblank_lines)" -gt 0 ]; then
            pass "The section [$VERSION] has release notes"
        else
            fail "The section [$VERSION] of CHANGELOG.md is empty"
        fi
    elif grep -Eq "^## \\[${VERSION_RE}\\]" CHANGELOG.md; then
        fail "The section [$VERSION] of CHANGELOG.md has no date, write it as: ## [$VERSION] - YYYY-MM-DD"
    else
        fail "CHANGELOG.md has no section [$VERSION], rename [Unreleased] and set the date"
    fi
    local left
    left=$(changelog_section Unreleased | nonblank_lines)
    if [ "$left" -eq 0 ]; then
        pass "Nothing is left under [Unreleased]"
    else
        fail "$left line(s) are left under [Unreleased] in CHANGELOG.md"
    fi
}

check_versions() {
    local file found
    for file in package.json package-lock.json; do
        if [ ! -f "$file" ]; then
            fail "$file does not exist"
            continue
        fi
        found=$(json_version "$file")
        if [ "$found" = "$VERSION" ]; then
            pass "$file has the version $VERSION"
        else
            fail "$file has the version \"$found\", expected $VERSION"
        fi
    done
}

check_security_md() {
    local hits
    if [ ! -f SECURITY.md ]; then
        fail "SECURITY.md does not exist"
        return
    fi
    hits=$(grep -n 'TBD' SECURITY.md || true)
    if [ -z "$hits" ]; then
        pass "SECURITY.md has no TBD"
    else
        fail "SECURITY.md still has a TBD, decide it first"
        detail "$hits"
    fi
}

check_action_yml() {
    local desc name icon color
    if [ ! -f action.yml ]; then
        fail "action.yml does not exist"
        return
    fi
    name=$(sed -n 's/^name:[[:space:]]*//p' action.yml | head -n 1)
    if [ -n "$name" ]; then
        pass "action.yml has a name: $name"
    else
        fail "action.yml has no name"
    fi
    desc=$(sed -n 's/^description:[[:space:]]*//p' action.yml | head -n 1)
    case "$desc" in
        '>'* | '|'*)
            fail "The description of action.yml is a block, write it as one quoted line"
            desc=""
            ;;
        '"'*'"') desc=${desc#\"} desc=${desc%\"} ;;
        "'"*"'") desc=${desc#\'} desc=${desc%\'} ;;
    esac
    if [ -z "$desc" ]; then
        fail "The description of action.yml is empty"
    elif [ "${#desc}" -le "$MAX_DESCRIPTION" ]; then
        pass "The description of action.yml has ${#desc} characters (at most $MAX_DESCRIPTION)"
    else
        fail "The description of action.yml has ${#desc} characters, the most is $MAX_DESCRIPTION"
    fi
    icon=$(awk '/^branding:/ { b = 1; next } b && /^[^[:space:]]/ { b = 0 } b && /^[[:space:]]+icon:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' action.yml)
    color=$(awk '/^branding:/ { b = 1; next } b && /^[^[:space:]]/ { b = 0 } b && /^[[:space:]]+color:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' action.yml)
    if [ -n "$icon" ] && [ -n "$color" ]; then
        pass "action.yml has branding: icon $icon, color $color"
    else
        fail "action.yml has no branding icon and color, the Marketplace needs both"
    fi
}

check_pinned_actions() {
    local file hit lineno content value checked=0 bad=""
    for file in .github/workflows/*.yml action.yml; do
        [ -f "$file" ] || continue
        while IFS= read -r hit; do
            lineno=${hit%%:*}
            content=${hit#*:}
            value=${content#*uses:}
            value=${value#"${value%%[![:space:]]*}"}
            value=${value%%#*}
            value=${value%"${value##*[![:space:]]}"}
            value=${value//\"/}
            value=${value//\'/}
            checked=$((checked + 1))
            case "$value" in ./*) continue ;; esac
            if ! printf '%s' "$value" | grep -Eq '^[^@]+@[0-9a-f]{40}$'; then
                bad="${bad}${file}:${lineno}: ${value}"$'\n'
            fi
        done < <(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "$file" || true)
    done
    if [ -z "$bad" ]; then
        pass "Every uses: is pinned by a 40 character SHA ($checked checked)"
    else
        fail "A uses: is not pinned by a 40 character SHA"
        detail "${bad%$'\n'}"
    fi
}

# ---------------------------------------------------------------------------
# Git state

# Print the lines of `git ls-remote` for the given refs, or return 1 when the remote cannot be read.
remote_refs() {
    git ls-remote "$REMOTE" "$@" 2>/dev/null
}

check_tag_absent() {
    local local_sha remote_out
    local_sha=$(git rev-parse -q --verify "refs/tags/$TAG" || true)
    if [ -z "$local_sha" ]; then
        pass "The tag $TAG does not exist here"
    else
        fail "The tag $TAG already exists here, at ${local_sha:0:7}"
    fi
    if ! remote_out=$(remote_refs "refs/tags/$TAG" "refs/tags/$TAG^{}"); then
        fail "Cannot read the tags of the remote $REMOTE"
    elif [ -z "$remote_out" ]; then
        pass "The tag $TAG does not exist on $REMOTE"
    else
        fail "The tag $TAG already exists on $REMOTE"
    fi
    # The first release of a major creates the floating tag, so it must not be there yet.
    if [ "$MINOR" = 0 ] && [ "$PATCH" = 0 ] && [ "${VERSION#*-}" = "$VERSION" ]; then
        if remote_out=$(remote_refs "refs/tags/v$MAJOR"); then
            if [ -z "$remote_out" ] && [ -z "$(git rev-parse -q --verify "refs/tags/v$MAJOR" || true)" ]; then
                pass "The floating tag v$MAJOR does not exist yet"
            else
                fail "The floating tag v$MAJOR already exists, a X.0.0 release is the first of its major"
            fi
        else
            fail "Cannot read the tags of the remote $REMOTE"
        fi
        if [ "$MAJOR" -ge 2 ]; then
            local prev=$((MAJOR - 1)) line
            if remote_out=$(remote_refs "refs/tags/v$prev"); then
                line=$(printf '%s\n' "$remote_out" | head -n 1)
                if [ -n "$line" ]; then
                    pass "The tag v$prev exists on $REMOTE and stays as it is: ${line%%[[:space:]]*}"
                else
                    fail "The tag v$prev does not exist on $REMOTE, users of @v$prev depend on it"
                fi
            else
                fail "Cannot read the tags of the remote $REMOTE"
            fi
        fi
    fi
}

check_work_tree() {
    local status branch remote_line remote_sha
    status=$(git status --porcelain)
    if [ -z "$status" ]; then
        pass "The working tree is clean"
    else
        fail "The working tree has changes"
        detail "$(printf '%s\n' "$status" | head -n 5)"
    fi
    branch=$(git symbolic-ref -q --short HEAD || true)
    if [ "$branch" = "$BRANCH" ]; then
        pass "On the branch $BRANCH"
    else
        fail "On \"${branch:-a detached HEAD}\", not on $BRANCH"
    fi
    if ! remote_line=$(remote_refs "refs/heads/$BRANCH"); then
        fail "Cannot read $BRANCH on the remote $REMOTE"
    else
        remote_sha=${remote_line%%[[:space:]]*}
        if [ -z "$remote_sha" ]; then
            fail "The remote $REMOTE has no branch $BRANCH"
        elif [ "$remote_sha" = "$HEAD_SHA" ]; then
            pass "HEAD ${HEAD_SHA:0:7} is $REMOTE/$BRANCH"
        else
            fail "HEAD is ${HEAD_SHA:0:7}, $REMOTE/$BRANCH is ${remote_sha:0:7}, pull or push first"
        fi
    fi
}

check_required_checks() {
    local contexts runs ctx ok=0 total=0 bad="" notrun="" line
    if ! command -v gh >/dev/null 2>&1; then
        skip "Required status checks: gh is not installed, read them in the GitHub checks list of ${HEAD_SHA:0:7}"
        return
    fi
    if ! contexts=$(gh api "repos/{owner}/{repo}/branches/$BRANCH/protection/required_status_checks" --jq '.contexts[]' 2>&1); then
        fail "Cannot read the required checks of $BRANCH with gh api"
        detail "$(printf '%s\n' "$contexts" | head -n 2)"
        return
    fi
    if ! runs=$(gh api --paginate "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs?per_page=100" \
        --jq '.check_runs[] | [.name, .status, (.conclusion // "none")] | @tsv' 2>&1); then
        fail "Cannot read the check runs of ${HEAD_SHA:0:7} with gh api"
        detail "$(printf '%s\n' "$runs" | head -n 2)"
        return
    fi
    while IFS= read -r ctx; do
        [ -n "$ctx" ] || continue
        case " $PR_ONLY_CHECKS " in
            *" $ctx "*)
                skip "Required check \"$ctx\" runs on pull requests only, it has no run for ${HEAD_SHA:0:7}"
                continue
                ;;
        esac
        total=$((total + 1))
        if printf '%s\n' "$runs" | NAME="$ctx" awk -F'\t' '$1 == ENVIRON["NAME"] && $2 == "completed" && $3 == "success" { f = 1 } END { exit !f }'; then
            ok=$((ok + 1))
        else
            line=$(printf '%s\n' "$runs" | NAME="$ctx" awk -F'\t' '$1 == ENVIRON["NAME"] { print $2 "/" $3; exit }')
            if [ -z "$line" ]; then
                notrun="${notrun}${ctx}: no run"$'\n'
            else
                bad="${bad}${ctx}: ${line}"$'\n'
            fi
        fi
    done <<EOF
$contexts
EOF
    if [ "$total" -eq 0 ]; then
        fail "$BRANCH has no required status checks, the release has nothing to rely on"
    elif [ "$ok" -eq "$total" ]; then
        pass "All $total required checks are green for ${HEAD_SHA:0:7}"
    else
        fail "$ok of $total required checks are green for ${HEAD_SHA:0:7}"
        detail "$(printf '%s%s' "$bad" "$notrun" | sed '/^$/d')"
    fi
}

check_tag_commit() {
    local tag_sha status
    tag_sha=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" || true)
    if [ -z "$tag_sha" ]; then
        fail "The tag $TAG is not in this checkout"
    elif [ "$tag_sha" = "$HEAD_SHA" ]; then
        pass "The tag $TAG points at the checked out commit ${HEAD_SHA:0:7}"
    else
        fail "The tag $TAG points at ${tag_sha:0:7}, the checkout is ${HEAD_SHA:0:7}"
    fi
    if ! command -v gh >/dev/null 2>&1; then
        skip "HEAD is on $BRANCH: gh is not installed"
        return
    fi
    if ! status=$(gh api "repos/{owner}/{repo}/compare/$BRANCH...$HEAD_SHA" --jq '.status' 2>&1); then
        fail "Cannot compare ${HEAD_SHA:0:7} with $BRANCH with gh api"
        detail "$(printf '%s\n' "$status" | head -n 2)"
        return
    fi
    case "$status" in
        identical | behind) pass "The tagged commit ${HEAD_SHA:0:7} is on $BRANCH" ;;
        *) fail "The tagged commit ${HEAD_SHA:0:7} is not on $BRANCH (compare says: $status), release only from $BRANCH" ;;
    esac
}

# What to do after the release. Never a failure.
collect_todos() {
    local file hits count=0 files=""
    for file in $PROMISE_FILES; do
        [ -f "$file" ] || continue
        hits=$(grep -c "after the v$MAJOR release" "$file" || true)
        if [ "$hits" -gt 0 ]; then
            count=$((count + hits))
            files="$files $file"
        fi
    done
    if [ "$count" -gt 0 ]; then
        todo "After the release, remove the $count sentence(s) that say @v$MAJOR is available after the release:${files}"
    fi
    if [ -f SECURITY.md ] && grep -q 'Not released yet' SECURITY.md; then
        todo "After the release, change the v$MAJOR row of SECURITY.md that says it is not released yet"
    fi
}

# ---------------------------------------------------------------------------

printf 'Release check for %s (%s)\n' "$TAG" "$([ "$MODE" = tag ] && echo "at tag time" || echo "before the tag")"
check_changelog
check_versions
check_security_md
check_action_yml
check_pinned_actions
if [ "$MODE" = tag ]; then
    check_tag_commit
else
    check_tag_absent
    check_work_tree
    check_required_checks
fi
collect_todos

if [ -n "$TODOS" ]; then
    printf '%s' "$TODOS"
fi
printf 'Result: %d FAIL, %d SKIP, %d TODO\n' "$FAILS" "$SKIPS" "$TODO_COUNT"
[ "$FAILS" -eq 0 ]
