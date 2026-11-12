<!-- agents-toolkit:planning-doc issue=1 -->
# Plan: CI, Dependabot and housekeeping (issue #1)

## Problem

The repository has no workflows, so nothing checks a codebase that holds a write token. It also has leftovers from before the v3 work (#10).

## Done before this plan

The default branch was renamed from `master` to `main` through the GitHub API. No file in the tree referred to `master` as the branch name.

## Work, in three groups on separate files

1. **Workflows** (`.github/workflows/*`, `.github/dependabot.yml`): shellcheck on all `*.sh`, CodeQL, Dependabot for npm, github-actions and docker, and Dependabot auto-merge in the style of the other repositories. Every action is pinned by commit SHA and every workflow sets least-privilege `permissions:`.
2. **Housekeeping** (`docker-compose.yml`, `package.json`, `scripts/*`, `test*.sh`, `Dockerfile.debug`, docs): remove `docker-compose.yml`, fix `package.json`, remove the hard-coded `/Users/miguel/...` paths and translate Spanish comments to English.
3. **Entrypoint** (`entrypoint.sh` only): fix the retried `git push` that exits 1 even when the retry succeeds, the unused `NODE_VERSION` variable (SC2034) and the garbled character. Nothing else changes here, the rewrite is #2.

## Testing

`shellcheck` reports nothing on every `*.sh`. Each workflow parses as YAML. CI is green on `main` after the merge.

## Out of scope

No release, no new tag, no change to action inputs or behavior.
