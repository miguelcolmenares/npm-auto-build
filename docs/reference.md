# Reference

<!-- Generated from action.yml by tests/docs-generated.py. Do not edit it by hand: change action.yml, then run `python3 tests/docs-generated.py --write`. A test fails while this page is out of date. -->

Every input and output of the action, as `action.yml` declares them. This page is generated from that file, so it cannot drift from it. The README and the other pages say when to use each one.

## Inputs

| Input | Default |
|---|---|
| `mode` | `commit` |
| `working-directory` | `.` |
| `command` | `build` |
| `install-command` | (empty) |
| `package-manager` | `auto` |
| `node-version` | `24` |
| `node-version-file` | (empty) |
| `registry-url` | (empty) |
| `scope` | (empty) |
| `paths` | `dist` |
| `token` | `${{ github.token }}` |
| `commit-message` | `chore: update build output [skip ci]` |
| `git-user-name` | `github-actions[bot]` |
| `git-user-email` | `github-actions[bot]@users.noreply.github.com` |
| `branch` | (empty) |
| `pr-title` | `chore: update build output` |
| `pr-labels` | (empty) |
| `auto-merge` | `false` |
| `ignore-scripts` | `false` |
| `upload-diff` | `true` |
| `artifact-name` | `npm-auto-build-stale-diff` |

What each input does:

### `mode`

Default: `commit`

What the action does: commit (default), check, pr or build. Commit builds and pushes the build output to the current branch. It needs a branch checkout (not a tag or a pull_request merge ref), actions/checkout with persist-credentials: false and permissions: contents: write. Check fails when the committed build output is stale and reads no token. Pr commits the build output to its own branch (the branch input), force-pushes only that bot-owned branch and keeps one pull request up to date against the checked out branch. It needs the same checkout, plus permissions: pull-requests: write and the setting Allow GitHub Actions to create and approve pull requests (or a personal access token or a GitHub App token as token).

### `working-directory`

Default: `.`

Directory that contains the package.json file. Relative to the workspace.

### `command`

Default: `build`

Name of the package.json script that builds the project.

### `install-command`

Default: (empty)

Command that installs the dependencies. Empty means the action picks the command for the package manager. When set, it replaces detection of the install command and ignore-scripts has no effect, the build still uses the detected package-manager.

### `package-manager`

Default: `auto`

Package manager: auto, npm, yarn or pnpm. Auto reads the packageManager field of package.json, then the lockfile (two lockfiles of different managers is an error, bun is not supported). An explicit value wins over both.

### `node-version`

Default: `24`

Node.js version to install, for example 24 or 22.x. Ignored when node-version-file is set.

### `node-version-file`

Default: (empty)

File with the Node.js version, for example .nvmrc or package.json. Relative to the workspace. When set, it wins over node-version.

### `registry-url`

Default: (empty)

Registry URL for actions/setup-node, for example https://npm.pkg.github.com. setup-node then writes an .npmrc that reads NODE_AUTH_TOKEN, set it in the env: of the job. Not a secret, so no credential in the URL.

### `scope`

Default: (empty)

Scope for the registry-url, for example @my-org. Only used together with registry-url.

### `paths`

Default: `dist`

Build output paths, one per line, relative to working-directory. Every path must exist after the build.

### `token`

Default: `${{ github.token }}`

GitHub token that pushes the build output and, in mode pr, opens the pull request (modes commit and pr, not read in build and check mode). Only the commit or pr step reads it, install and build never see it. The default GITHUB_TOKEN does not start new workflow runs, and a pull request opened with it does not start the checks either, so required checks need a personal access token or a GitHub App token. To push to a protected branch use a personal access token or a GitHub App token that may bypass the protection.

### `commit-message`

Default: `chore: update build output [skip ci]`

Commit message for the build output (modes commit and pr). In mode commit keep [skip ci] in it: a push with a personal access token or a GitHub App token starts the workflow again, and without [skip ci] it can loop. In mode pr the default message is used without [skip ci], because GitHub skips the checks of a pull request whose head commit has it.

### `git-user-name`

Default: `github-actions[bot]`

Git user name for commits (modes commit and pr).

### `git-user-email`

Default: `github-actions[bot]@users.noreply.github.com`

Git user email for commits (modes commit and pr).

### `branch`

Default: (empty)

Branch that holds the build output in pr mode. Empty means auto-build/\<checked out branch>. The action force-pushes this branch on every run, so it must be a branch that only the action writes to: it is refused when it is the base branch, the default branch of the remote, a reserved name (main, master, develop, release/\* and similar), or a branch that already exists and was not made by this action.

### `pr-title`

Default: `chore: update build output`

Pull request title (mode pr). It is set again on every run.

### `pr-labels`

Default: (empty)

Pull request labels, comma separated (mode pr). The labels must exist in the repository. They are added on every run and never removed.

### `auto-merge`

Default: `false`

Enable auto-merge on the pull request with gh pr merge --auto (mode pr). The repository needs Allow auto-merge and a branch protection rule with required checks. The merge method is the first one the repository allows: squash, merge or rebase.

### `ignore-scripts`

Default: `false`

Install dependencies without running lifecycle scripts: --ignore-scripts for npm, pnpm and yarn classic, YARN_ENABLE_SCRIPTS=false for yarn berry. No effect when install-command is set.

### `upload-diff`

Default: `true`

Upload the diff of a stale build as an artifact (mode check).

### `artifact-name`

Default: `npm-auto-build-stale-diff`

Name of the artifact with the diff (mode check). Set a different name for each use of the action in one workflow run, a duplicate name makes the upload fail.

## Outputs

| Output | Description |
|---|---|
| `changed` | true when the action pushed a commit with new build output, false when nothing changed (mode commit). Empty in the other modes. |
| `stale` | true when the committed build output is out of date, false when it is fresh (mode check). Empty in the other modes. |
| `commit-sha` | SHA of the pushed commit with the build output (mode commit). Empty when nothing changed and in build and check mode. |
| `pull-request-url` | URL of the pull request (mode pr). Empty when nothing changed and in the other modes. |
| `pull-request-number` | Number of the pull request (mode pr). Empty when nothing changed and in the other modes. |

## Deprecated v2 inputs

The v2 names are accepted as aliases and print a warning. They are not part of the v3 interface. The [migration guide](./migration-v2-to-v3.md) says how each one behaves.

| Alias | Description |
|---|---|
| `github-token` | Deprecated, use token. Accepted so a v2 workflow keeps working: a warning is printed and the value is used as the token of the commit and pr steps, where it wins over token. |
| `directory` | Deprecated, use working-directory. Accepted as an alias. |
| `build-dir` | Deprecated, use paths. Accepted as an alias. |
| `build-only` | Deprecated, use mode: build. Accepted as an alias. |
| `create-pr` | Deprecated, use mode: pr. Accepted as an alias. |
