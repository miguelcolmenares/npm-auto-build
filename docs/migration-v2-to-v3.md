# Migrating from v2 to v3

v3 keeps the idea of v2: build the project and commit the build output for you. It changes how the action runs, how it uses the token, and how it names its inputs. This page lists what to change, and how to stay on `@v2` if you are not ready.

The tag `@v3` is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`.

## The short version

For most workflows, three edits are enough:

1. Change `@v2` to `@v3`.
2. Add `persist-credentials: false` to `actions/checkout`, and remove `token:` from the checkout.
3. Rename the inputs in the table below, or leave them, they still work and print a warning.

Before, with v2:

<!-- docs-examples: skip -->
```yaml
steps:
  - uses: actions/checkout@v4
    with:
      token: ${{ secrets.GITHUB_TOKEN }}
  - uses: miguelcolmenares/npm-auto-build@v2
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      directory: ./frontend
      build-dir: dist
      create-pr: true
```

After, with v3:

```yaml
name: Build
on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: pr
          working-directory: ./frontend
          paths: dist
```

## Renamed inputs

The v2 names are accepted as aliases. Each one prints a warning that names the new input. The aliases are a bridge, not part of the v3 interface, and no release date is promised for their removal. Rename them now.

| v2 input | v3 input | What the warning says | How the alias behaves |
|---|---|---|---|
| `github-token` | `token` | `Input 'github-token' is a v2 name. Use 'token' instead.` It adds that the value still works as the token of the commit and pr steps, and wins over `token`. | The value is used as the token of the commit and pr steps only. |
| `directory` | `working-directory` | `Input 'directory' is a v2 name. Use 'working-directory' instead.` | Used when `working-directory` is not set. When both are set to different values, `working-directory` wins and a second warning says so. |
| `build-dir` | `paths` | `Input 'build-dir' is a v2 name. Use 'paths' instead.` | Used when `paths` is not set. When both are set to different values, `paths` wins and a second warning says so. |
| `build-only: true` | `mode: build` | `Input 'build-only' is a v2 name. Use 'mode: build' instead.` | Sets the mode to `build` when `mode` is `commit`, the default. When `mode` is already `check`, `pr` or `build`, the alias is ignored and a second warning says so. |
| `create-pr: true` | `mode: pr` | `Input 'create-pr' is a v2 name. Use 'mode: pr' instead.` | Same rules as `build-only`. |

Two details. A `build-only` or `create-pr` value other than `true` or `false` fails the step. And `build-only: false` or `create-pr: false` still prints the warning, and changes nothing.

The other v2 inputs keep their name: `command`, `commit-message`, `git-user-name`, `git-user-email` and `node-version`. Only the defaults of `commit-message` and `node-version` changed, see below.

## Breaking changes

### The action is composite, not Docker

v2 ran in a Docker container on an Alpine image. v3 is a composite action that runs on the runner itself, on Linux, macOS and Windows. Your build now sees the tools of the runner, not the ones of an Alpine image. If your build relied on something in that image, install it in a step before the action. On a self-hosted runner, the action needs bash and git, and mode `pr` also needs `gh`.

### Node 24 is the default, and `node-version` works

In v2 the `node-version` input had no effect, the container always used its own Node.js. In v3 the action installs the version you ask for with `actions/setup-node`. The default is `24`. Set `node-version`, or `node-version-file` (for example `.nvmrc`), when your project needs another version. The file wins over `node-version`.

### The token is only in the commit and pr steps

In v2 the token was in the same container as `npm ci` and your build. In v3 the validate, install and build steps never receive it. Only the Commit step (mode `commit`) and the Pull request step (mode `pr`) hold it, and they give it to `git` and `gh` for one command at a time.

Two changes follow in your workflow. Set `persist-credentials: false` on `actions/checkout`, and do not pass a token to it. If the checkout keeps its credentials, the action prints a warning, and the push can fail with two Authorization headers. And `token` is no longer required, it defaults to `${{ github.token }}`. The job needs `permissions: contents: write`, and mode `pr` also needs `pull-requests: write`.

### No guessing of the build directory

v2 looked for `dist`, `build`, `lib`, `public`, `out` and `.next`. v3 does not guess. It commits the folders of `paths`, which defaults to `dist`, one per line, relative to `working-directory`. When a path does not exist after the build, the step fails and lists the missing paths. If your build writes to `build` or `lib`, set `paths`.

### The default mode is `commit`

When you set no `mode`, the action builds and commits, as v2 did. What changed around it:

- A tag push or a `pull_request` event leaves HEAD detached, and in v2 that broke the push. v3 fails early with a message that names the options: a branch push, mode `check`, or mode `pr`.
- The default `commit-message` is now `chore: update build output [skip ci]` (v2: `chore: update build files`). Keep `[skip ci]` in your own message, or a push with a personal access token can start the workflow again.
- A push that is rejected is retried up to three times, with a fetch and a rebase of the one build commit. The action never force-pushes in mode `commit`.

### Mode `pr` keeps one pull request

v2 with `create-pr: true` made a new timestamped branch and a new pull request on every run. Mode `pr` always uses one branch, `auto-build/<checked out branch>` by default, and keeps one pull request up to date. See the [recipes](recipes.md#protected-branch).

### Other changes

- Package manager detection changed. v2 always preferred `package-lock.json`. v3 reads the `packageManager` field first, then the lockfile, and two lockfiles of different managers with no `packageManager` field fail. pnpm and yarn are supported, see [Package managers](testing.md#package-managers-and-private-registries).
- The action has outputs now: `changed`, `stale`, `commit-sha`, `pull-request-url` and `pull-request-number`.
- Mode `check` is new. It is the gate for pull requests.

## Stay on v2

v2 keeps working through the `v2` tag, and the last release is `v2.1.2`. Pin one of them:

<!-- docs-examples: skip -->
```yaml
- uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Use `@v2.1.2` instead of `@v2` when you want a build that never changes. v2 does not get the changes of this page. The README that describes v2 is in the `v2` tag.
