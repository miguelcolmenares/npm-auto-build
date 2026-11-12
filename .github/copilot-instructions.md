# GitHub Copilot Instructions

This is a **GitHub Action** that builds an npm project and commits the build output. `main` holds the v3 composite action in progress (issue #10): `mode: commit` (the default), `mode: check`, `mode: pr` and `mode: build` all work. The v2 Docker action stays available through the `v2` tag. Understanding the line between the steps that run the project's code (no token) and the steps that hold the token is essential for effective contributions.

## Architecture Overview

**Core Components:**
- `action.yml` - Composite action: v3 inputs and outputs, step order, `env:` per step
- `scripts/lib.sh` - Logging (`log_info`, `log_warn`, `log_error`, `die`), env file helpers, package manager detection, `run_without_token`
- `scripts/validate-inputs.sh` - v2 alias mapping, mode gate, validation, writes `NAB_*` to `GITHUB_ENV`
- `scripts/install.sh` - Dependency install, without the token
- `scripts/build.sh` - Runs the build and checks every `paths` entry, without the token
- `scripts/git-lib.sh` - Git helpers shared by the two modes that push: the credential header (`nab_build_auth_header`, `nab_git_remote`), the version check, the branch and path checks
- `scripts/commit.sh` - Mode `commit`: stages the `paths`, commits and pushes to the checked out branch. One of the two scripts that get the token, and it gives it to `git fetch` and `git push` only
- `scripts/pr.sh` - Mode `pr`: commits the build output to a bot branch, force-pushes it with a lease (only that branch, never the base, a protected name or a branch it did not make) and keeps one pull request up to date with `gh`. The other script that gets the token: `git ls-remote`, `git fetch` and `git push` through `GIT_CONFIG_*`, and `gh` as `GH_TOKEN` for one command
- `scripts/check.sh` - Compares the build output with `HEAD` (mode `check`), reads no token, runs without GitHub too
- `scripts/release-check.sh` - Maintainer tool, not part of the action: checks that a release is ready (before the tag) or that the tagged commit is good (in `release.yml`). Read only. `docs/releasing.md` is the procedure
- `tests/` - bats tests and the fixture project in `tests/fixture/`
- `examples/` - Complete v3 workflow files, checked against `action.yml` by `tests/docs-examples.py`
- `docs/recipes.md` and `docs/migration-v2-to-v3.md` - Setups and the v2 to v3 changes, checked by the same script

**Key Design Rules:**
1. Inputs reach scripts only through `env:`, never through `${{ }}` inside `run:`.
2. Install and build never see the token. Do not export it in an `env:` of those steps.
3. Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, and every expansion is quoted.
4. No directory guessing: a missing `paths` entry is an error.

## Critical Workflows

**Local Testing:**
```bash
npm test                 # shellcheck on every script, then bats tests/ when bats exists
bats tests/              # the bats tests alone (brew install bats-core; docs-examples needs PyYAML and skips without it)
```

**Action Input Structure:** In the scripts, inputs arrive as `INPUT_` variables set by `env:` in `action.yml`:
- `command` → `INPUT_COMMAND`
- `working-directory` → `INPUT_WORKING_DIRECTORY`

**Version Strategy:** Uses major version tags (`@v2`) that auto-update to the latest `v2.x.x` release. v3 gets its own tag when it is released.

## Project-Specific Conventions

**Error Handling:** Use the logging functions from `scripts/lib.sh` (`log_info`, `log_warn`, `log_error`, `die`). `log_warn` and `log_error` print `::warning::` and `::error::` workflow commands. Always use them instead of raw `echo`.

**Paths:** `paths` is a newline list, relative to `working-directory`. Entries that are empty, start with `-`, contain `..` or are absolute are rejected.

**Package Manager Detection:** with `package-manager: auto`, the `packageManager` field of `package.json` comes first, then the lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` or `npm-shrinkwrap.json`), then npm without a lockfile. Two lockfiles of different managers and no field is an error, and bun is not supported. Commands: `npm ci`, `pnpm install --frozen-lockfile`, yarn classic `--frozen-lockfile`, yarn berry `--immutable` (the lockfile-less forms are `npm install`, `pnpm install --no-frozen-lockfile`, `yarn install`, `yarn install --no-immutable`). `corepack enable` sets up pnpm and yarn, never `npm install -g`. An explicit `package-manager` input wins, and `install-command` replaces the install command.

## Integration Patterns

**Example Workflow Pattern:**
```yaml
# Complete workflow shows the standard dual-mode pattern
if: github.event_name == 'pull_request'  # mode: check for PRs
if: github.event_name == 'push'          # mode: commit for main
```

**Permission Requirements:**
- Modes `build` and `check`: `contents: read` is enough
- Mode `commit`: `contents: write` and `persist-credentials: false` on the checkout
- Mode `pr`: the same, plus `pull-requests: write`
- Protected branches: a personal access token or a GitHub App token as `token`, or mode `pr`

## Development Guidelines

**When modifying the scripts:**
- Keep the split by responsibility: validation, install, build, one file each
- Run `npm test` before committing, and add a bats test for each new rule
- Never read or print the token in `install.sh` or `build.sh`

**When updating examples:**
- Use `@v3` references, and `actions/checkout@v7` with `persist-credentials: false`
- Use only inputs that exist in `action.yml`, and never the v2 names (`github-token`, `directory`, `build-dir`, `build-only`, `create-pr`) except in the v2 "before" blocks of the migration guide, which carry the skip marker
- Run `python3 tests/docs-examples.py --tables README.md --require-modes README.md` and the same script on the other docs after an edit, or `bats tests/docs-examples.bats`

**Marketplace Compliance:**
- The Marketplace requires a public repository, a single `action.yml` or `action.yaml` at the root and a unique `name` ([requirements](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace)). Workflow files under `.github/workflows/` are allowed, and the repository has them for CI.
- All examples should use the action via the marketplace reference, not local paths

**Major Version Tag Management:**
After each release, update the major version tag to point to the latest version:
```bash
# For v1.x.x releases - update v1 tag
git tag -f v1 v1.2.0
git push -f origin v1

# For v2.x.x releases - create/update v2 tag  
git tag -f v2 v2.0.0
git push -f origin v2
```

**GitHub CLI Usage:**
Always disable pager when using `gh` to prevent terminal hanging:
```bash
PAGER=cat gh release list
gh api repos/owner/repo/releases | cat
# Or pipe output to cat for any gh command that might use pager
```

**Key Files to Reference:**
- `examples/complete-workflow.yml` - Standard dual-mode pattern
- `examples/monorepo.yml` - Matrix strategy for multiple packages  
- `examples/protected-branch-pr.yml` and `examples/protected-branch-token.yml` - Mode `pr` and a token that may bypass the protection
