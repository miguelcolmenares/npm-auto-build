---
order: 10
---

# Mode commit

Builds, then commits the build output to the checked out branch and pushes it. This is the default mode and the original behavior of the action.

Use it when the branch accepts pushes from the workflow. It needs a branch checkout. The [getting started](./getting-started.md) page shows the smallest workflow. The example below does two jobs in one file: mode `check` on pull requests, and mode `commit` on pushes to `main`.

## Example

<!-- example: examples/complete-workflow.yml -->
```yaml
# One workflow for pull requests and for the main branch.
#
# On a pull request the action only checks that the committed build output is fresh
# (mode check). It reads no token, so it also works for pull requests from forks.
# On a push to main it builds and commits the changed build output (mode commit).
#
# Copy the file to .github/workflows/ and change the build script and the paths.
name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# The least privilege for the jobs that only read. The commit job asks for more.
permissions:
  contents: read

# One run per branch at a time, so two pushes never race to commit the build.
concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  check:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: check
          command: build:prod
          paths: dist

  commit:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      contents: write # the push of the build commit
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false # the build cannot read a token from .git/config
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          command: build:prod
          paths: dist
          git-user-name: Build Bot
          git-user-email: build-bot@example.com
```

## Outputs

| Output | Value |
|---|---|
| `changed` | `true` when the action pushed a commit with new build output, `false` when nothing changed. |
| `commit-sha` | SHA of the pushed commit. Empty when nothing changed. |

The other outputs are empty in this mode.

## What the workflow needs

- **`permissions: contents: write`.** The default `GITHUB_TOKEN` of a read-only workflow cannot push.
- **`persist-credentials: false`** on `actions/checkout`. The action looks for a persisted credential before the install, and mode `commit` fails when it finds one.
- **`concurrency`.** If two runs push to the same branch, the second push is rejected. The action then fetches the branch, rebases its one commit on top and pushes again, up to three attempts, and it never force-pushes. A `concurrency` group avoids the race, and the extra build, in the first place. If the rebase conflicts, the step aborts it and fails.

## Limits

- **A branch push only.** A tag push and a `pull_request` event leave HEAD detached, so there is no branch to push to and the step fails with an error that says so. Use [mode check](./mode-check.md) for pull requests.
- **A protected branch.** `GITHUB_TOKEN` cannot push there. Pass a personal access token or a GitHub App token that may bypass the protection as `token`, or use [mode pr](./mode-pr.md). See the [recipe](./recipes.md#protected-branch).
- **The loop risk.** The default message ends with `[skip ci]`. A push with `GITHUB_TOKEN` does not start workflows, but a push with a personal access token or a GitHub App token does, so keep `[skip ci]` in a custom `commit-message`. The step prints a notice when it is missing.
- **Safe paths.** `.`, the repository root, `.git` and a path outside the repository are refused, and anything already staged before the step is refused, so it cannot end up in the build commit.

## How the token is used

Only the commit step receives it (and the pr step in mode `pr`). It copies it into a shell variable, masks it and its base64 form, and gives it to `git fetch` and `git push` only, as an `http.extraheader` in the `GIT_CONFIG_*` environment variables of that one command. It is never in a command line, a URL, `.git/config`, `git config --global` or a file. This needs git 2.31 or newer, which every GitHub-hosted runner has. See [Security](./security.md).
