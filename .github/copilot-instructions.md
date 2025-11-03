# GitHub Copilot Instructions

This is a **GitHub Action** for automating npm build and commit workflows. Understanding the Docker-based architecture and dual-mode operation is essential for effective contributions.

## Architecture Overview

**Core Components:**
- `action.yml` - GitHub Actions metadata and input definitions  
- `entrypoint.sh` - Main execution logic (Bash script)
- `Dockerfile` - Container environment (Node.js + Git)
- `examples/` - Real-world usage patterns for different scenarios

**Key Design Pattern:** This action operates in two distinct modes controlled by `build-only` input:
1. **Build + Commit Mode** (default): Builds project and commits/pushes generated files
2. **Build-Only Mode**: Only builds for testing (no Git operations)

## Critical Workflows

**Local Testing:**
```bash
./test.sh [command] [build-dir] [project-path]  # Full Docker test
./test-build-only.sh                            # Build-only mode test
```

**Action Input Structure:** All inputs are prefixed with `INPUT_` in environment variables:
- `command` → `INPUT_COMMAND` 
- `build-only` → `INPUT_BUILD_ONLY`

**Version Strategy:** Uses major version tags (`@v1`) that auto-update to latest `v1.x.x` releases.

## Project-Specific Conventions

**Error Handling:** Uses colored logging functions (`log_info`, `log_warn`, `log_error`) defined in `entrypoint.sh`. Always use these instead of raw `echo`.

**Directory Detection:** The action auto-detects build directories using this priority order:
1. User-specified `build-dir` input
2. Auto-detection: `dist/`, `build/`, `public/`, `out/`, `lib/`

**Git Operations:** Only performed when `BUILD_ONLY != "true"`. Always check this condition before any Git commands.

**Package Manager Detection:** Automatically chooses between npm/yarn based on lockfile presence (`yarn.lock` vs `package-lock.json`).

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

**When modifying `entrypoint.sh`:**
- Always preserve the `BUILD_ONLY` early exit logic around line 70
- Use the established logging functions for consistency
- Test both modes with local scripts before committing

**When updating examples:**
- Use `@v1` tag references (not specific versions like `@v1.1.0`)
- Include both build-only and build+commit scenarios
- Reference `actions/checkout@v5` for Node.js 24 compatibility

**Marketplace Compliance:**
- **CRITICAL: Never add `.github/workflows/` files** - GitHub Actions repositories "must not contain any workflow files" per [marketplace requirements](https://docs.github.com/en/actions/creating-actions/publishing-actions-in-github-marketplace#prerequisites)
- Keep only `README.md` and `CHANGELOG.md` as documentation
- All examples should use the action via marketplace reference, not local paths

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
- `entrypoint.sh` lines 60-80 - Build-only mode implementation