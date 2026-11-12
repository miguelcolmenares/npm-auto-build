<!-- agents-toolkit:planning-doc issue=4 -->
# Plan: mode check (issue #4)

Goal: the same build as the other modes, then fail the job when the build output differs from what is committed. Read only, so it works on `pull_request` and on forks, and no step reads a token.

## Design

- `scripts/check.sh` holds all the logic. It needs only bash, git and these variables: `NAB_PATHS` (newline list, relative to the working directory), `NAB_COMMAND` and `NAB_PACKAGE_MANAGER` (only for the fix message), `NAB_WORKDIR` (only for the message), `RUNNER_TEMP` and `GITHUB_OUTPUT` (both optional). A Bitbucket Pipelines step can run it with one line after its own build.
- It runs from the working directory, finds the repository root with `git rev-parse --show-toplevel`, and refuses a path that resolves outside the root (`..` or a symlink that leaves the repository).
- Stale means: a tracked file that differs from `HEAD`, a tracked file that is deleted, a file that is not tracked (new, or ignored by `.gitignore`).
- Line endings: a difference of only CR at the end of a line is not stale. Use `git diff --ignore-cr-at-eol` (git 2.16 or newer) and compare the file list from `git diff --name-only` after the same normalisation. `git status` alone is not used for tracked files, because it reports a CRLF-only change as modified.
- On stale: `::error::` with the files (cap 50, then "and N more"), the working directory and the fix command; output `stale=true`; write `diff.patch` and `files.txt` in `$RUNNER_TEMP/nab-check` (or a `mktemp` directory); exit 1. Fresh: `stale=false`, exit 0. Without `GITHUB_OUTPUT` the script prints `stale=true|false`.

## action.yml

- The validate step gets the `mode` output, the check step runs only when it is `check`, after the build step.
- `Upload the diff` uses `actions/upload-artifact` pinned by SHA, with `always()` so the failing check step does not skip it.
- The output `stale` points to `steps.check.outputs.stale`.

## validate-inputs.sh

- `check` is accepted by the mode gate. `commit` and `pr` keep failing with their issue numbers.

## Tests

- `tests/check.bats` with a throwaway git repository, no network.
- CI job `self-test-check` builds the fixture twice, fresh and stale, and asserts the outcome and the artifact.

## Docs

- `docs/testing.md`: the new test file, the new job, and "Use the check outside GitHub".
- `CHANGELOG.md`: an Added entry and the mode statement at the top.
