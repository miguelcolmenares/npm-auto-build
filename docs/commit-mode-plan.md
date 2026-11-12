<!-- agents-toolkit:planning-doc issue=3 -->
# Plan: mode commit (issue #3)

Goal: after a push, build the project and commit the changed build output to the
current branch, so nobody commits `dist/` by hand.

## Files

New: `scripts/commit.sh`, `tests/commit.bats`. Small edits to shared files:
`action.yml`, `scripts/validate-inputs.sh`, `tests/helpers.bash`, `.github/workflows/ci.yml`,
`CHANGELOG.md`, `docs/testing.md`, and the tests that said "commit is not available yet".

## Steps

1. `validate-inputs.sh`: let `commit` pass the mode gate, write the output `mode`, update the
   `github-token` alias warning.
2. `action.yml`: a `Commit` step after `Build`, with `if: steps.validate.outputs.mode == 'commit'`.
   Only this step gets `NAB_TOKEN` (the `github-token` alias wins over `token`). Outputs
   `changed` and `commit-sha` point to this step.
3. `commit.sh`:
   - read the token into a shell variable and remove it from the environment, so only the
     remote commands (fetch, push) can see it, and only through `GIT_CONFIG_*` variables
     set inside a subshell (never in argv, a URL, a config file or `git config --global`)
   - mask the token and its base64 form with `::add-mask::`
   - refuse a detached HEAD with a message that says what to do
   - resolve every `paths` entry against the repository root, refuse `.`, empty, the root,
     `.git` and anything outside the repository, then `git add --force`
   - no staged change: `changed=false`, no commit
   - commit with one-shot `-c user.name` and `-c user.email`, `--no-verify`, empty hooks dir
   - push with up to 3 attempts: on non-fast-forward fetch and rebase, on a rebase conflict
     abort and fail, on a protected branch fail with the two options, never force-push
   - outputs `changed` and `commit-sha`
4. Tests with a local bare repository as `origin`. A fake `git` wrapper on `PATH` records the
   argv and the environment of every call, to prove where the token goes.
5. CI: job `self-test-commit` with a bare remote it creates itself, and the unavailable-mode
   check moves to `mode: pr`.
6. Docs: `docs/testing.md`, CHANGELOG, action descriptions.

## Decisions where the issue is silent

- `GIT_CONFIG_COUNT` variables instead of `git -c http.extraheader=...`, because `-c` puts the
  credential in the process list.
- `rebase --onto origin/<branch> HEAD~1`, so a shallow checkout works.
