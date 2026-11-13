# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2026-11-12

v3.0.0 is a rewrite of the action. It is a composite action that runs on the runner, on Linux, macOS and Windows, with Node.js 24 by default. Its modes are `commit` (the default, the original behavior), `check`, `pr` and `build`. Your build runs without the write token. v2 keeps working through the `v2` tag. The v2 input names still work in v3, with a warning. Read the [migration guide](https://github.com/miguelcolmenares/npm-auto-build/blob/main/docs/migration-v2-to-v3.md) before you change `@v2` to `@v3`.

### Breaking changes from v2
- The default Node.js version is 24, and `node-version` has an effect.
- The action does not guess the build directory. Set `paths`, which is `dist` by default.
- A detached HEAD (a tag push or a `pull_request` event) is an error in mode `commit`.
- The pull request branch is fixed (`auto-build/<branch>`), so a pull request is updated and not opened again.
- The action runs on the host and not in an Alpine container.
- `build-only` is `mode: build` and `create-pr` is `mode: pr`. The old names work for now, with a warning.
- Two lockfiles of different package managers are an error, and a checkout that kept its credentials is refused in modes `commit` and `pr`.
- v2 support ends with this release (see `SECURITY.md`).

### Added
- **`mode: pr`, one pull request kept up to date (issue #5).** For a base branch that does not accept direct pushes. After the build the action stages the `paths`, makes one commit on top of the checked out branch (with `git commit-tree`, so the base branch and the working tree do not move) and force-pushes it to the bot branch, the `branch` input or `auto-build/<base branch>`. Then it opens a pull request to the base with `pr-title` and `pr-labels`, or, when one is already open from that branch, sets the title again and adds the labels. A second run never opens another pull request, and the same build on the same base pushes nothing. No difference from the base means no push and no pull request. The outputs `pull-request-url` and `pull-request-number` come from this step. It uses the `gh` CLI, which GitHub-hosted runners have, and not a third-party action.
- **`auto-merge`** runs `gh pr merge --auto` with the first merge method that the repository allows (squash, merge, rebase). It fails the step, after the pull request and the outputs exist, with the repository setting to change when GitHub refuses.
- `docs/testing.md` documents what PR mode needs: the repository setting "Allow GitHub Actions to create and approve pull requests", `permissions: contents: write` and `pull-requests: write`, and that a pull request made with `GITHUB_TOKEN` starts no other workflows, so required checks need a personal access token or a GitHub App token.
- Tests: `tests/pr.bats` (a local bare remote and a fake `gh`), and the CI job `self-test-pr`, which runs mode pr against a local bare remote with a stand-in `gh`. It never pushes to this repository and never opens a real pull request.
- **`mode: commit`, the auto build (the default, issue #3).** After the build, the action runs `git add --force` on each `paths` entry (so ignored build folders work), and when something is staged it commits with `git-user-name` and `git-user-email` and the `commit-message`, then pushes to the checked out branch. When nothing changed it exits 0 without a commit and sets `changed=false`. The outputs `changed` and `commit-sha` come from this step.
- A notice when `commit-message` has no `[skip ci]`: a push with a personal access token or a GitHub App token starts the workflow again and can loop. The message is never changed.
- **Composite action** (`runs: using: composite`), so it runs on Linux, macOS and Windows runners, on the host and not in an Alpine container.
- **The full v3 contract is declared:** the inputs `mode`, `working-directory`, `command`, `install-command`, `package-manager`, `node-version`, `node-version-file`, `paths`, `token`, `commit-message`, `git-user-name`, `git-user-email`, `branch`, `pr-title`, `pr-labels`, `auto-merge`, `ignore-scripts` and `upload-diff`, and the outputs `changed`, `stale`, `commit-sha`, `pull-request-url` and `pull-request-number`. The outputs of a mode that did not run are empty.
- **A real `node-version`**, default `24`, installed with `actions/setup-node` (pinned by commit SHA). `node-version-file` is supported and wins over `node-version`.
- `ignore-scripts` input: installs with `--ignore-scripts`. Yarn berry has no such flag, so the action sets `YARN_ENABLE_SCRIPTS=false` for that one command.
- **pnpm and yarn berry.** pnpm runs `pnpm install --frozen-lockfile`, yarn classic (1.x) `yarn install --frozen-lockfile` and yarn berry (2+) `yarn install --immutable`. Berry is detected from the `packageManager` field, a `.yarnrc.yml` file, a berry `yarn.lock` or `yarn --version`. The build runs with the same manager (`pnpm run`, `yarn run`, `npm run`).
- **Corepack.** `corepack enable` runs when the `packageManager` field names pnpm or yarn, or when the chosen pnpm or yarn is not installed. The action never runs `npm install -g`. Without corepack, a manager already on `PATH` is used with a warning, and the step fails only when the manager is missing too. The manager is checked with `--version` before the install.
- **Private registries.** The new optional inputs `registry-url` and `scope` (default empty) go to `actions/setup-node`, which writes an `.npmrc` with a `${NODE_AUTH_TOKEN}` placeholder. They are additions to the v3 contract of issue #10. The documented and tested contract: the install and the build inherit `NODE_AUTH_TOKEN` and the `NPM_CONFIG_*`, `YARN_*` and `PNPM_*` variables of the job, a project `.npmrc` with `${NODE_AUTH_TOKEN}` works, `NODE_AUTH_TOKEN` is kept even when its value equals the GitHub token, while the GitHub token variables are removed (see the risk in `docs/testing.md`), and the scripts never write an `.npmrc`. A `registry-url` with credentials, a query, a fragment or a setting such as `_authToken` in it is rejected, and an `http://` URL (other than localhost) is accepted with a warning that the token travels in clear text.
- Tests: `tests/package-managers.bats` and `tests/registries.bats` with fake package managers, a real `npm install` against a local registry that needs a token, the fixtures `tests/fixtures/pnpm`, `yarn-classic` and `yarn-berry`, and the CI job `self-test-pm`.
- **bats tests** (`tests/`) with a fixture project, and CI jobs `bats` and `self-test`. The self-test runs the action against the fixture on Ubuntu, macOS and Windows.
- `.gitattributes` keeps LF line endings in shell scripts, so a Windows checkout does not break them.
- **`mode: check`** (issue #4): runs the build, then compares the `paths` with `HEAD` and fails the job when they differ. A modified file, a deleted file, a new file and a file that `.gitignore` ignores are all stale. A line ending difference alone (carriage returns, `git diff --ignore-cr-at-eol`, git 2.16 or newer) is not. The `::error::` names the working directory and up to 50 files (then "and N more"), and says to run `<package manager> run <command>` and commit the changed paths. A path that resolves outside the repository is refused. It only reads, never reads a token, so it works on `pull_request` events from forks.
- **Output `stale`** is `true` or `false` in mode `check`, and the step exits 1 when it is `true`. With `upload-diff: true` the action uploads `diff.patch` and `files.txt` as the artifact `npm-auto-build-stale-diff` (7 days), when the check found stale output. `actions/upload-artifact` is pinned by commit SHA.
- **`scripts/check.sh` works without GitHub**: it needs only bash, git and the `NAB_PATHS` variable, and prints `stale=true` or `stale=false` when `GITHUB_OUTPUT` is not set, so Bitbucket Pipelines can use it with one line. See `docs/testing.md`.
- The validate step has a `mode` output, and the CI job `self-test-check` runs the action on the fixture, once fresh and once stale.
- `docs/migration-v2-to-v3.md`: the renamed inputs with what each warning says, the breaking changes, and how to stay on `@v2`.
- `docs/recipes.md`: protected branches, tag and `pull_request` events, matrix and monorepo, a private registry, pnpm and yarn, and a Bitbucket Pipelines step for `scripts/check.sh`.
- `examples/` rewritten for v3: `complete-workflow.yml`, `monorepo.yml`, `protected-branch-pr.yml` and `protected-branch-token.yml`. They replace `protected-branches.yml` and the v2 examples.
- **The examples cannot rot unnoticed.** `tests/docs-examples.py` reads the YAML snippets of the README, the examples, the recipes and the other docs, and checks each one against `action.yml`: the `@v3`, `@main` or SHA reference, only inputs that exist (and no v2 names), a valid `mode`, the checkout with `persist-credentials: false` and the permissions that the mode needs. It runs in `tests/docs-examples.bats`, with a test that adds a wrong input to a copy of the README and expects a failure, and in the CI job `docs-examples`. It does not run the action. A test also fails once a `v3` tag exists while the docs still say that `@v3` is not released.
- **Release tooling (issue #9).** `docs/releasing.md` is the release procedure: the checklist, the commands in order, who does each step and the rollback. `scripts/release-check.sh` is a read only check that a release is ready. With `--tag` it checks the tagged commit instead. `.github/workflows/release.yml` runs only on a tag `v3.x.y`. It checks the tag, runs the tests and makes a source archive with a build provenance attestation. Then it creates the GitHub release as a draft, with the CHANGELOG section as the notes, and moves the floating tag `v3`. `tests/release-check.bats` tests the script with each rule broken on purpose, and `tests/architecture.bats` has a list of maintainer tools for it.

### Deprecated
- **v2 input names are accepted as aliases** with a warning that names the new input: `build-only` (`mode: build`), `create-pr` (`mode: pr`), `directory` (`working-directory`), `build-dir` (`paths`) and `github-token` (`token`). `github-token` prints the warning and its value is used as the token of the commit and pr steps, where it wins over `token`, so a v2 workflow keeps pushing.

### Changed
- The `workflows` job of CI parses the YAML files with Ruby, which comes with the runner, and no longer installs PyYAML with `pip`. That closes the Scorecard alert Pinned-Dependencies (`pipCommand not pinned by hash`), and `actions/setup-python` is gone from the workflow.
- The git helpers that mode commit and mode pr share (the credential header, the git version check, the branch and path checks) moved from `scripts/commit.sh` to `scripts/git-lib.sh`. Nothing changed in how mode commit behaves. The detached HEAD and protected branch messages of mode commit now point to `mode: pr` without saying it is not available.
- **A detached HEAD is an error in mode commit** (a tag push, or a `pull_request` event), with a message that names `mode: check`, a branch push and `mode: pr`. There is no more `HEAD` used as a branch name.
- The self-test of the mode gate runs an unknown mode (`deploy`), now that every documented mode works. A new CI job `self-test-commit` runs `mode: commit` against a local bare remote. `docs/testing.md` explains the workflow requirements: `persist-credentials: false`, `permissions: contents: write` and a `concurrency` group.
- The default Node.js version is 24 and `node-version` has an effect now.
- The scripts live in `scripts/` (`lib.sh`, `validate-inputs.sh`, `install.sh`, `build.sh`), one responsibility each, with `set -euo pipefail`. The logic is no longer in the YAML.
- A missing `paths` entry after the build is an error that lists the missing paths.
- **Package manager detection (`package-manager: auto`).** The order is the `packageManager` field of `package.json`, then the lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` or `npm-shrinkwrap.json`), then npm without a lockfile (`npm install` and a warning). v2 always preferred `package-lock.json`. Now lockfiles of two different managers and no `packageManager` field **fail** and name both files, instead of picking one. A `packageManager` field of `bun`, or a bun lockfile alone, fails with the list of supported managers. An explicit `package-manager` input wins over everything. `install-command` overrides the install command, and the build still runs with the detected manager.
- **New warnings and errors:** without corepack, a pnpm or yarn that is already on `PATH` is used with a warning, and the step fails only when the manager is missing too. The build step fails with a message that names `install-command` when the manager is not on `PATH`. A missing lockfile warns.
- pnpm and yarn without a lockfile install without the frozen flags and print a warning, like npm does, instead of failing on the missing lockfile.
- `npm test` runs shellcheck and, when bats is installed, `bats tests/`. Dependabot no longer watches Docker.
- The CI and housekeeping from #13 and the push fix of the Docker action are in no release: the Docker code they changed is removed here.
- **README rewritten for v3 (issue #7).** The premise first, the four modes with one example each, the inputs and outputs tables (checked against `action.yml` by `tests/docs-examples.py`), the permissions and `persist-credentials: false` that modes `commit` and `pr` need, and the token model. The badges for CI, CodeQL and the OpenSSF Scorecard were added, and the license badge is labeled "License". The release badge shows the latest tag.
- Stale v2 text removed from the README, `docs/README.md`, `.github/ACTION_DESCRIPTION.md` and `.github/copilot-instructions.md`: the old Node.js version and checkout version in examples, the `@v2` references, the claim of fewer merge conflicts, the auto detected build directory, and the description of how the action runs.
- The description of `action.yml`, the text that the Marketplace shows, is shorter and says what the action does: `Build your project and commit the output, so you do not commit dist/ by hand. Can also check it is current, or open a PR.` (issue #9).

### Removed
- `Dockerfile` and `entrypoint.sh`, and the Docker only scripts `test.sh`, `test-build-only.sh`, `scripts/test-local.sh`, `scripts/test-debug.sh` and `scripts/Dockerfile.debug`. They stay available through the `v2` tag.
- **The guessing of the build directory** (`dist`, `build`, `lib`, `public`, `out`, `.next`).

### Security
- **The force-push is limited to a branch the action owns.** It uses `--force-with-lease=<branch>:<tip it looked at>`, never a plain force, so a push that races with a person or another run is refused and looked at again (three attempts). The destination is always `refs/heads/<branch>`. The branch is refused when it is the base branch, the default branch of the remote, a reserved name (`main`, `master`, `develop`, `release/*` and similar, in any case), or when it already exists and its tip commit has no `Generated-by: npm-auto-build` line, so a branch that a person made is never overwritten. A checked out branch that starts with `auto-build/` is refused, so a pull request branch cannot get a pull request of its own. The name is checked by the validate step, before the build.
- **The token in mode pr** follows the rules of mode commit: only the pr step receives it, `git ls-remote`, `git fetch` and `git push` get it as an `http.extraheader` in `GIT_CONFIG_*` for that one command, and `gh` gets it as `GH_TOKEN` for that one command. It is in no argument list, URL, git config, file or output, and install and build never see it.
- **The token is used only by the commit step (and the pr step in mode pr).** It is removed from the step environment, masked together with its base64 form, and given to `git fetch` and `git push` only, as an `http.extraheader` in the `GIT_CONFIG_*` variables of that one command. It is not in a command line (`git -c` would show it in `ps`), a URL, `.git/config`, `git config --global` or a file. Tests check each of these places. Needs git 2.31 or newer. `actions/checkout` should use `persist-credentials: false`, and the action warns when it finds credentials in `.git/config`.
- **Push safety.** A rejected push is retried up to three times: the action fetches the branch, rebases its commit on top and pushes again. Mode commit never force-pushes. A rebase conflict is aborted and fails with a clear message. A protected branch fails with the two options that work: a personal access token or a GitHub App token that may bypass the protection, or `mode: pr`. If a parallel run already pushed the same output, nothing is pushed and `changed=false`.
- **Safe `paths` for commit.** An entry is resolved against the repository root. `.`, the repository root, `.git` (and anything inside it) and a path outside the repository are refused. A name is never read as a glob or a pathspec magic. Anything already staged before the step is refused, so it cannot end up in the build commit. Repository hooks do not run.
- **The install and build steps run without the token.** The token is not passed to them, and the scripts remove the known token variables (`GITHUB_TOKEN`, `GH_TOKEN`, `INPUT_TOKEN`, `INPUT_GITHUB_TOKEN`, `ACTIONS_RUNTIME_TOKEN` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`) from their environment even when the workflow exports one. A test prints the environment of an install script and a build script and finds no token.
- **Input validation.** Inputs reach the scripts only through environment variables. A `paths` entry that is empty, starts with `-`, contains `..` or is absolute is rejected, and so is a `working-directory` that leaves the workspace. Values with a line break, or longer than 1024 characters, are rejected. Spaces, quotes and `$()` are kept as text and never run.
- Workflow checks for this repository, in `.github/workflows/workflow-security.yml`: `actionlint`, `zizmor`, and a check that every `uses:` is pinned to a commit SHA.
- OpenSSF Scorecard (`.github/workflows/scorecard.yml`) and a dependency review on pull requests (`.github/workflows/dependency-review.yml`).
- `docs/threat-model.md`: the assets, actors, trust boundaries and threats of the action, and the known v2 findings with the v3 fix for each.
- `SECURITY.md`: how to report a vulnerability, which versions are supported, and the response times.
- `docs/architecture.md` and `tests/architecture.bats` (issue #11): the two trust zones, what each script may do, and tests that fail when a script outside the allowlist reads a token variable, runs `git push` or `git fetch`, calls a network tool, or when a `run:` block holds a `${{ }}` expression. `tests/failure-paths.bats` adds tests for long values in every input, a leading dash, a fork pull request, a failed build and two runs at the same time. The last one found that a push that loses a ref lock race (`cannot lock ref`) was not retried, so `commit.sh` now treats it like a rejected push.
- **A checkout that kept its credentials is refused before the install** in mode `commit` and mode `pr` (issue #26). The check runs in `validate-inputs.sh`, reads only the key names of `http.*.extraheader` in the local git config, and tells you to set `persist-credentials: false` on `actions/checkout`. Mode `check` and mode `build` print a warning. Before, the warning came after the build, when the token had already been readable.
- **Build provenance for the release (issue #9, audit finding F4).** The release workflow attests the build provenance of the source archive of each release, and `gh attestation verify` checks it. Each job of the workflow has the permissions it needs and no more, and only the release job can write to the repository.

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

See the [README](README.md) for the current usage of the action, and the [examples](examples/README.md) for complete workflows. The usage of v2 is in the `v2` tag.
