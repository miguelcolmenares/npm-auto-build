#!/usr/bin/env bash
# Mode check. Compare the build output with HEAD and fail when it differs.
#
# Run it after the build, from the repository (or from the working directory inside it).
# It needs only bash and git, so it works outside GitHub, for example in a Bitbucket
# Pipelines step:
#
#   NAB_PATHS=dist NAB_COMMAND=build bash scripts/check.sh
#
# Reads these environment variables:
#   NAB_PATHS            build output paths, one per line, relative to the working directory
#                        (default: dist)
#   NAB_WORKDIR          the working directory, relative to the current one (default: .)
#   NAB_COMMAND          the build script, only used in the message that says how to fix it
#                        (default: build)
#   NAB_PACKAGE_MANAGER  auto, npm, yarn or pnpm, only used in the same message (default: auto)
#   RUNNER_TEMP          where the diff files go, in a nab-check directory (default: mktemp -d)
#   GITHUB_OUTPUT        when set, the output "stale" is appended to this file, otherwise
#                        the script prints "stale=true" or "stale=false"
#
# May do: run git (read only, apart from a scratch copy of the index), write the diff files.
# May not: read a token, run the project's code, touch the network, change the repository.
#
# Stale means one of: a tracked file that differs from HEAD, a tracked file that is deleted,
# a file that git does not track (new, or ignored by .gitignore). A difference of carriage
# returns at the end of lines alone is not stale. A staged new file is labelled `added`.
# Known limit: a path with a tab or a line break in its name is not parsed correctly. Needs git 2.16 or newer, for
# --ignore-cr-at-eol. Exit code: 0 fresh, 1 stale or any error.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# At most this many files are named in the error message. files.txt holds all of them.
NAB_CHECK_MAX_LISTED=50

# Paths are names here, never patterns, and git must not wait for a lock to read.
export GIT_LITERAL_PATHSPECS=1
export GIT_OPTIONAL_LOCKS=0

# Report the result: in the step output on GitHub, on standard output anywhere else.
emit_stale() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        nab_write_output stale "$1"
    else
        printf 'stale=%s\n' "$1"
    fi
}

# Join a prefix (the working directory inside the repository, with a trailing slash
# or empty) and an entry, remove "." and ".." parts, and set REL_PATH to the result,
# relative to the repository root. Returns 1 when the path leaves the root.
resolve_under_root() {
    local rest="$1$2" part out=""
    while [ -n "$rest" ]; do
        case "$rest" in
            */*)
                part=${rest%%/*}
                rest=${rest#*/}
                ;;
            *)
                part=$rest
                rest=""
                ;;
        esac
        case "$part" in
            '' | .) ;;
            ..)
                [ -n "$out" ] || return 1
                case "$out" in
                    */*) out=${out%/*} ;;
                    *) out="" ;;
                esac
                ;;
            *) out="${out:+$out/}$part" ;;
        esac
    done
    REL_PATH=${out:-.}
}

# Succeed when the directory (an existing path) is the root or inside it, after
# following every symbolic link. Both sides are resolved with pwd -P, so the two
# spellings of one directory (git prints C:/x on Windows, bash prints /c/x) agree.
inside_root() {
    local root_physical=$1 target=$2 physical
    # A target that cannot be entered is not a directory to read, so it does not fail here.
    # No file read happens for such a target, the caller checks that it exists.
    physical=$(cd -P -- "$target" 2>/dev/null && pwd -P) || return 0
    [ "$physical" = "$root_physical" ] && return 0
    case "$physical" in
        "$root_physical"/*) return 0 ;;
    esac
    return 1
}

main() {
    local workdir=${NAB_WORKDIR:-.}
    local command=${NAB_COMMAND:-build}
    local paths=${NAB_PATHS-dist}
    [ -n "$paths" ] || die "NAB_PATHS is empty. List at least one path, for example 'dist'."

    [ -d "$workdir" ] || die "working-directory '$workdir' does not exist."
    cd -- "$workdir"

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "'$workdir' is not inside a git work tree, so the build output cannot be compared."
    git rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null \
        || die "The repository has no commit yet, there is nothing to compare the build output with."

    # --ignore-cr-at-eol needs git 2.16. An older git exits with 129, a usage error.
    local probe=0
    git diff --no-index --quiet --ignore-cr-at-eol /dev/null /dev/null >/dev/null 2>&1 || probe=$?
    [ "$probe" -le 1 ] || die "git is too old: 'git diff --ignore-cr-at-eol' needs git 2.16 or newer."

    local root prefix root_physical
    root=$(git rev-parse --show-toplevel) || die "Could not find the repository root."
    prefix=$(git rev-parse --show-prefix)
    root_physical=$(cd -P -- "$root" && pwd -P) || die "Could not enter the repository root."

    # The package manager only names the fix command, resolve it from the working directory.
    # The detection stops with an error on an unreadable package.json or two lockfiles. That
    # must not stop the check, so it runs in a subshell and the message falls back to npm.
    local pm
    pm=$( (nab_resolve_package_manager >/dev/null 2>&1 && printf '%s' "$NAB_RESOLVED_PM") ) || pm=npm
    [ -n "$pm" ] || pm=npm

    # Resolve every path against the repository root, and refuse one that leaves it.
    local specs=() entry
    while IFS= read -r entry || [ -n "$entry" ]; do
        entry=${entry%$'\r'}
        [ -n "$entry" ] || continue
        case "$entry" in
            -*) die "paths entry '$entry' must not start with '-', it could be read as an option." ;;
            /* | \\* | [A-Za-z]:*) die "paths entry '$entry' must be relative to the working directory, not absolute." ;;
        esac
        resolve_under_root "$prefix" "$entry" \
            || die "paths entry '$entry' is outside the repository, the check only compares paths inside it."
        # A symbolic link in the middle of the path, or as the path itself, can lead out.
        if [ -d "$root/$REL_PATH" ]; then
            inside_root "$root_physical" "$root/$REL_PATH" \
                || die "paths entry '$entry' resolves to a place outside the repository, the check only compares paths inside it."
        else
            inside_root "$root_physical" "$(dirname -- "$root/$REL_PATH")" \
                || die "paths entry '$entry' resolves to a place outside the repository, the check only compares paths inside it."
        fi
        # Nothing on disk and nothing in HEAD under it: the build did not make it.
        if [ ! -e "$root/$REL_PATH" ] && [ ! -L "$root/$REL_PATH" ] \
            && [ -z "$(git -C "$root" ls-tree --name-only HEAD -- "$REL_PATH")" ]; then
            die "path '$entry' does not exist (relative to working-directory '$workdir') and is not in HEAD. Fix 'paths' or the build script."
        fi
        specs+=("$REL_PATH")
    done <<<"$paths"
    [ "${#specs[@]}" -gt 0 ] || die "NAB_PATHS has no entry."

    # The diff files go in a directory of their own, emptied first so nothing old stays.
    local outdir
    if [ -n "${RUNNER_TEMP:-}" ]; then
        outdir="$RUNNER_TEMP/nab-check"
        rm -rf -- "$outdir"
        mkdir -p -- "$outdir"
    else
        outdir=$(mktemp -d)
    fi

    cd -- "$root"
    local work
    work=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf -- '$work'" EXIT
    local entries="$work/entries"
    : >"$entries"

    # 1. Tracked files that changed or were deleted, compared with HEAD (index and work
    # tree together). A modified file counts only when its patch is not empty after
    # --ignore-cr-at-eol, so a line-ending change alone is fresh. The verdict comes from
    # the patch, not from how a given git version prints --name-only with that flag.
    local meta path status
    while IFS= read -r -d '' meta; do
        IFS= read -r -d '' path || break
        status=${meta##* }
        case "$status" in
            D*) printf 'deleted\t%s\n' "$path" >>"$entries" ;;
            A*) printf 'added\t%s\n' "$path" >>"$entries" ;;
            *)
                if [ -n "$(git diff --no-ext-diff --ignore-cr-at-eol HEAD -- "$path")" ]; then
                    printf 'modified\t%s\n' "$path" >>"$entries"
                fi
                ;;
        esac
    done < <(git diff --raw -z --no-renames --no-ext-diff HEAD -- "${specs[@]}")

    # 2. Files git does not track. An ignored one is output that no commit can carry
    # unless it is forced in, so it counts too, with its own label.
    local ignored="$work/ignored"
    git ls-files --others --ignored --exclude-standard -z -- "${specs[@]}" | tr '\0' '\n' >"$ignored"
    while IFS= read -r -d '' path; do
        if grep -Fxq -- "$path" "$ignored"; then
            printf 'ignored\t%s\n' "$path" >>"$entries"
        else
            printf 'untracked\t%s\n' "$path" >>"$entries"
        fi
    done < <(git ls-files --others -z -- "${specs[@]}")

    LC_ALL=C sort -u -o "$entries" "$entries"
    local total
    total=$(grep -c . "$entries" || true)

    if [ "$total" -eq 0 ]; then
        emit_stale false
        log_info "The build output is fresh, it matches HEAD."
        return 0
    fi

    cut -f2- "$entries" | LC_ALL=C sort >"$outdir/files.txt"

    # The patch: the real index is left alone. A scratch copy of it gets every file in
    # the paths added with --intent-to-add, so new and ignored files show in the patch.
    local index
    index=$(git rev-parse --git-path index)
    if cp -- "$index" "$work/index" 2>/dev/null \
        && GIT_INDEX_FILE="$work/index" git add --intent-to-add --force -- "${specs[@]}" 2>/dev/null \
        && GIT_INDEX_FILE="$work/index" git diff --no-ext-diff --no-color --ignore-cr-at-eol HEAD -- "${specs[@]}" >"$outdir/diff.patch"; then
        :
    else
        log_warn "Could not write the diff of the stale files. The list of files is still in files.txt."
        : >"$outdir/diff.patch"
    fi

    local listing="" count=0
    while IFS=$'\t' read -r status path; do
        count=$((count + 1))
        [ "$count" -le "$NAB_CHECK_MAX_LISTED" ] || break
        listing="${listing}  ${status}: ${path}"$'\n'
    done <"$entries"
    if [ "$total" -gt "$NAB_CHECK_MAX_LISTED" ]; then
        listing="${listing}  ... and $((total - NAB_CHECK_MAX_LISTED)) more"$'\n'
    fi

    local joined="" ignore_hint=""
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        joined="${joined:+$joined, }$entry"
    done <<<"${paths//$'\r'/}"
    if grep -q . "$ignored"; then
        ignore_hint=" Files marked 'ignored' match .gitignore, add them with 'git add --force' or remove the path from .gitignore."
    fi

    emit_stale true
    log_error "The committed build output is out of date (working directory '$workdir'). $total file(s) differ from HEAD:"$'\n'"${listing}To fix it, run '$pm run $command' in '$workdir' and commit the changed paths ($joined).${ignore_hint}"
    log_info "The diff is in $outdir/diff.patch and the file list in $outdir/files.txt"
    return 1
}

main
