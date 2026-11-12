# GitHub Copilot Instructions

This is a **GitHub Action** that builds an npm project and commits the build output. `main` holds the v3 composite action in progress (issue #10): `mode: build` and `mode: check` work, the modes `commit` and `pr` come with issues #3, #4 and #5. The v2 Docker action stays available through the `v2` tag. Understanding the line between the steps that run the project's code (no token) and the steps that hold the token is essential for effective contributions.

## Architecture Overview

**Core Components:**
- `action.yml` - Composite action: v3 inputs and outputs, step order, `env:` per step
- `scripts/lib.sh` - Logging (`log_info`, `log_warn`, `log_error`, `die`), env file helpers, package manager detection, `run_without_token`
- `scripts/validate-inputs.sh` - v2 alias mapping, mode gate, validation, writes `NAB_*` to `GITHUB_ENV`
- `scripts/install.sh` - Dependency install, without the token
- `scripts/build.sh` - Runs the build and checks every `paths` entry, without the token
- `scripts/check.sh` - Compares the build output with `HEAD` (mode `check`), reads no token, runs without GitHub too
- `tests/` - bats tests and the fixture project in `tests/fixture/`
- `examples/` - Usage patterns (still written for v2, rewritten by issue #7)

**Key Design Rules:**
1. Inputs reach scripts only through `env:`, never through `${{ }}` inside `run:`.
2. Install and build never see the token. Do not export it in an `env:` of those steps.
3. Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, and every expansion is quoted.
4. No directory guessing: a missing `paths` entry is an error.

## Critical Workflows

**Local Testing:**
```bash
npm test                 # shellcheck on every script, then bats tests/ when bats exists
bats tests/              # the bats tests alone (brew install bats-core)
```

**Action Input Structure:** In the scripts, inputs arrive as `INPUT_` variables set by `env:` in `action.yml`:
- `command` → `INPUT_COMMAND`
- `working-directory` → `INPUT_WORKING_DIRECTORY`

**Version Strategy:** Uses major version tags (`@v2`) that auto-update to the latest `v2.x.x` release. v3 gets its own tag when it is released.

## Project-Specific Conventions

**Error Handling:** Use the logging functions from `scripts/lib.sh` (`log_info`, `log_warn`, `log_error`, `die`). `log_warn` and `log_error` print `::warning::` and `::error::` workflow commands. Always use them instead of raw `echo`.

**Paths:** `paths` is a newline list, relative to `working-directory`. Entries that are empty, start with `-`, contain `..` or are absolute are rejected.

**Package Manager Detection:** `package-lock.json` runs `npm ci`, `yarn.lock` runs `yarn install --frozen-lockfile`, `pnpm-lock.yaml` runs `pnpm install --frozen-lockfile`, otherwise `npm install`. Issue #6 extends this.

## Integration Patterns

**Example Workflow Pattern:**
```yaml
# Complete workflow shows the standard dual-mode pattern
if: github.event_name == 'pull_request'  # Build-only for PRs
if: github.event_name == 'push'          # Build+commit for main
```

**Permission Requirements:**
- Build-only mode: No special permissions needed
- Build+commit mode: Requires `contents: write` permission
- Protected branches: Requires Personal Access Token (PAT)

## Development Guidelines

**When modifying the scripts:**
- Keep the split by responsibility: validation, install, build, one file each
- Run `npm test` before committing, and add a bats test for each new rule
- Never read or print the token in `install.sh` or `build.sh`

**When updating examples:**
- Use `@v2` tag references (not specific versions like `@v2.1.2`)
- Include both build-only and build+commit scenarios
- Reference `actions/checkout@v5` for Node.js 24 compatibility

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
- `examples/protected-branches.yml` - PAT configuration
