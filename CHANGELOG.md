# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

`main` is now the v3 composite action in progress (issue #10). Only `mode: build` works so far. The modes `commit`, `check` and `pr` come with issues #3, #4 and #5, so `main` offers less than v2 until they land. Nothing is released from `main` yet. v2 stays available through the `v2` tag: use `miguelcolmenares/npm-auto-build@v2` for the Docker action.

### Added
- **Composite action** (`runs: using: composite`), so it runs on Linux, macOS and Windows runners, on the host and not in an Alpine container.
- **The full v3 contract is declared:** the inputs `mode`, `working-directory`, `command`, `install-command`, `package-manager`, `node-version`, `node-version-file`, `paths`, `token`, `commit-message`, `git-user-name`, `git-user-email`, `branch`, `pr-title`, `pr-labels`, `auto-merge`, `ignore-scripts` and `upload-diff`, and the outputs `changed`, `stale`, `commit-sha`, `pull-request-url` and `pull-request-number`. In `build` mode the outputs are empty. A mode other than `build` fails at once and names the issue that implements it.
- **A real `node-version`**, default `24`, installed with `actions/setup-node` (pinned by commit SHA). `node-version-file` is supported and wins over `node-version`.
- **The install and build steps run without the token.** The token is not passed to them, and the scripts remove the known token variables (`GITHUB_TOKEN`, `GH_TOKEN`, `INPUT_TOKEN`, `INPUT_GITHUB_TOKEN`, `ACTIONS_RUNTIME_TOKEN` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`) from their environment even when the workflow exports one. A test prints the environment of an install script and a build script and finds no token.
- **Input validation.** Inputs reach the scripts only through environment variables. A `paths` entry that is empty, starts with `-`, contains `..` or is absolute is rejected, and so is a `working-directory` that leaves the workspace. Values with a line break, or longer than 1024 characters, are rejected. Spaces, quotes and `$()` are kept as text and never run.
- **v2 input names are accepted as aliases** with a warning that names the new input: `build-only` (`mode: build`), `create-pr` (`mode: pr`), `directory` (`working-directory`), `build-dir` (`paths`) and `github-token` (`token`). `github-token` only prints the warning for now: its value is not read, and issue #3 decides whether it feeds the commit step.
- `ignore-scripts` input: installs with `--ignore-scripts`.
- **bats tests** (`tests/`) with a fixture project, and CI jobs `bats` and `self-test`. The self-test runs the action against the fixture on Ubuntu, macOS and Windows.
- `.gitattributes` keeps LF line endings in shell scripts, so a Windows checkout does not break them.

### Changed
- The default Node.js version is 24 and `node-version` has an effect now.
- The scripts live in `scripts/` (`lib.sh`, `validate-inputs.sh`, `install.sh`, `build.sh`), one responsibility each, with `set -euo pipefail`. The logic is no longer in the YAML.
- A missing `paths` entry after the build is an error that lists the missing paths.
- Package manager detection: `package-lock.json` runs `npm ci`, `yarn.lock` runs `yarn install --frozen-lockfile`, `pnpm-lock.yaml` runs `pnpm install --frozen-lockfile`, otherwise `npm install`. `install-command` overrides it.
- `npm test` runs shellcheck and, when bats is installed, `bats tests/`. Dependabot no longer watches Docker.
- The CI and housekeeping from #13 and the push fix of the Docker action are in no release: the Docker code they changed is removed here.
- README: a note at the top says that v3 is in development and `@v2` is the stable version. The rest is rewritten by issue #7.

### Removed
- `Dockerfile` and `entrypoint.sh`, and the Docker only scripts `test.sh`, `test-build-only.sh`, `scripts/test-local.sh`, `scripts/test-debug.sh` and `scripts/Dockerfile.debug`. They stay available through the `v2` tag.
- **The guessing of the build directory** (`dist`, `build`, `lib`, `public`, `out`, `.next`).

## [2.1.2] - 2025-11-10

### Fixed
- **Enhanced .gitignore detection for build directories**
  - Build directories with trailing slash (e.g., `dist/`) are now properly detected
  - Multiple pattern checks: `dist`, `dist/`, and `dist/*`
  - Fallback grep validation for direct .gitignore file check
  - Ensures proper use of `git add --force` for ignored directories

### Technical Details
The action now performs comprehensive checks to detect if a build directory is in `.gitignore`:
1. `git check-ignore $BUILD_DIR` - Check exact directory name
2. `git check-ignore $BUILD_DIR/` - Check with trailing slash
3. `git check-ignore $BUILD_DIR/*` - Check files within directory
4. Direct grep in `.gitignore` file - Fallback validation

This fixes a critical issue where `dist/` (with trailing slash) in `.gitignore` wasn't being detected, causing the action to fail when attempting to commit build files.

### Impact
Users who have their build directories in `.gitignore` (common best practice) will now have their builds properly committed by the action without errors.


## [2.1.1] - 2025-11-04

### Fixed
- **CREATE_PR parameter debugging**: Added comprehensive debug logging to identify why `create-pr: true` parameter wasn't working properly
- **Enhanced troubleshooting**: Added variable state logging and comparison result logging for better issue diagnosis
- **Protected branch debugging**: Improved debugging capabilities for protected branch configuration issues

### Debug Features
- Added debug output showing `CREATE_PR` parameter value at startup
- Added comparison result logging before push/PR decision
- Enhanced error diagnostics for protected branch scenarios

## [2.1.0] - 2025-11-04

### Added
- **Protected branch support**: New `create-pr` parameter for handling protected branches
- **Automatic PR creation**: Creates pull requests when direct push fails due to branch protection
- **GitHub CLI integration**: Installs and configures GitHub CLI for seamless PR creation
- **Enhanced error handling**: Detailed error messages with solutions for protected branch issues

### Features
- **New Input**: `create-pr: true` - Creates PR instead of direct push
- **Smart detection**: Automatically detects protected branch push failures
- **Unique branch naming**: Creates timestamped branches for each build
- **Comprehensive logging**: Shows PR creation process and branch information

## [2.0.2] - 2025-11-04

### Fixed
- **Git configuration error**: Fixed "Author identity unknown" error when git user inputs are not provided
- **Input validation**: Added proper validation for git user name and email
- **Default values**: Added fallback default values for all input parameters
- **Debug logging**: Enhanced logging to show git configuration values for troubleshooting

## [2.0.1] - 2025-11-04

### Fixed
- **Critical .gitignore handling**: Build directories in .gitignore (like `dist/`) are now properly committed using `--force` flag
- **Enhanced logging**: Added detailed git status logging to help diagnose commit issues
- **Improved detection**: Better detection of ignored directories and files

### Technical Details
This fixes a critical issue where build files weren't committed if the build directory was in `.gitignore`. This is common practice where developers ignore `dist/` locally but want the action to commit official builds.

## [2.0.0] - 2025-11-04

> **Note**: This is the first fully functional release. Previous v1.x versions contained a critical Docker configuration issue that prevented execution.

### Added

- **🚀 NPM Auto Build GitHub Action**: Complete functional GitHub Action for automating npm build and commit workflows
- **🔧 Build-only mode**: New `build-only` input parameter for testing builds without committing changes
- **🐳 Docker-based execution**: Containerized environment with Node.js 20, Git, and Bash
- **📁 Flexible build detection**: Auto-detects build directories (dist/, build/, public/, out/, lib/)
- **📦 Package manager support**: Automatic detection and support for both npm and yarn
- **📚 Comprehensive examples**: Real-world usage patterns for different scenarios
  - Complete CI/CD workflow with PR testing and main branch deployment
  - Monorepo setup with matrix strategy for multiple packages
  - Protected branches configuration with Personal Access Token
- **🧪 Local testing scripts**: Enhanced development workflow with Docker-based test scripts
- **🏪 GitHub Marketplace compliance**: Full compliance with marketplace requirements
- **📖 Complete documentation**: Detailed README with troubleshooting and permission guides

### Core Features

- **Input parameters**:
  - `command`: NPM script to build your package (default: "build")
  - `directory`: Directory containing package.json (default: ".")
  - `commit-message`: Custom commit message (default: "chore: update build files")
  - `build-dir`: Build output directory (default: "dist", auto-detected)
  - `github-token`: GitHub token for authentication (required)
  - `git-user-name`: Git user name (default: "github-actions[bot]")
  - `git-user-email`: Git user email (default: "github-actions[bot]@users.noreply.github.com")
  - `node-version`: Node.js version (default: "18")
  - `build-only`: Test mode without committing (default: "false")

### Technical Implementation

- **Base image**: node:20-alpine with bash, git, and npm/yarn
- **Shell script**: entrypoint.sh with comprehensive error handling and logging
- **Action metadata**: Properly formatted action.yml with all input definitions
- **Docker support**: Multi-architecture container support
- **Permission handling**: Documented requirements for `contents: write`

### Breaking Changes

- **Version 2.0.0**: Complete rewrite from v1.x (which were non-functional)
- **Node.js 20**: Updated from Node.js 18 for better performance and security
- **Alpine Linux**: Switched to Alpine base image with proper bash support
- **Enhanced validation**: Stricter input validation and error reporting

## Usage

```yaml
- name: Build and Deploy
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    build-dir: dist
    commit-message: "chore: update build files [skip ci]"
```

For complete usage examples, see the [examples/](examples/) directory.