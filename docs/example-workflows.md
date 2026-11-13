---
order: 21
---

# Example workflows

Complete workflow files. Copy one to `.github/workflows/` in your repository and change the build script and the paths. More setups, such as private registries, pnpm and yarn, tag events and Bitbucket Pipelines, are in the [recipes](./recipes.md).

Every file on this page is a file of the `examples/` directory of the repository. The page is generated from those files, and a test fails when a page shows a copy that differs from its file. Each file is also checked against `action.yml` by `tests/docs-examples.py`.

That check is structural. Each input must exist, the mode must be valid, the checkout must have `persist-credentials: false` and the job must have the permissions that the mode needs. **It does not run the workflows.** The self-test jobs of the repository run the action, against the fixture projects and not against these files. The script names, directories and secret that the files use (`build:prod`, `build:lib`, `apps/*`, `packages/ui`, `BUILD_BOT_TOKEN`) are yours to define.

The files write the action as `miguelcolmenares/npm-auto-build@v3`.

## Quick start, mode commit

<!-- example: examples/quick-start.yml -->
```yaml
# The smallest workflow: mode commit, the default.
#
# On every push to main it installs Node.js 24, installs the dependencies, runs the
# `build` script of package.json and commits the changed `dist` folder to main.
# When the build output did not change, it makes no commit.
#
# Copy the file to .github/workflows/ and change nothing else to start.
name: Build

on:
  push:
    branches: [main]

permissions:
  contents: write # the push of the build commit

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false # the build cannot read a token from .git/config
      - uses: miguelcolmenares/npm-auto-build@v3
```

## Check and commit in one workflow

Mode `check` on pull requests, and mode `commit` on pushes to `main`.

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

## Monorepo

One job per package, each with its own `working-directory` and `paths`, pushed one after the other.

<!-- example: examples/monorepo.yml -->
```yaml
# A monorepo with one job per package.
#
# Every job has its own working-directory and its own paths (relative to the working
# directory), and makes its own commit when its build output changed.
#
# The concurrency group is on the workflow, not on the job. A job level group is shared
# by all the matrix jobs, and GitHub keeps only one running and one pending job in a group,
# so it would cancel the others. max-parallel: 1 makes the jobs push one after the other.
name: Build packages

on:
  push:
    branches: [main]

permissions:
  contents: write

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      max-parallel: 1
      matrix:
        package:
          - name: web-app
            directory: apps/web
            command: build
            paths: dist
          - name: admin-panel
            directory: apps/admin
            command: build:prod
            paths: build
          - name: shared-ui
            directory: packages/ui
            command: build:lib
            paths: lib
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          working-directory: ${{ matrix.package.directory }}
          command: ${{ matrix.package.command }}
          paths: ${{ matrix.package.paths }}
          commit-message: "chore(${{ matrix.package.name }}): update build output [skip ci]"
```

## Protected branch, mode pr

A bot branch and one pull request, for a branch that does not accept direct pushes.

<!-- example: examples/protected-branch-pr.yml -->
```yaml
# A branch that does not accept direct pushes: mode pr.
#
# The action commits the build output to its own branch (auto-build/main by default) and
# keeps one pull request up to date, so main is never written to. A person merges it.
#
# With the default GITHUB_TOKEN, turn on "Allow GitHub Actions to create and approve pull
# requests" in the repository settings (Settings, Actions, General). A pull request made
# with that token starts no other workflows. When you require checks on main, pass a
# personal access token or a GitHub App token as `token` (see protected-branch-token.yml).
# The bot branch is rewritten on every run, so exclude it from branch protection.
name: Build pull request

on:
  push:
    branches: [main]

permissions:
  contents: write # the push of the bot branch
  pull-requests: write # open and update the pull request

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        id: build
        with:
          mode: pr
          pr-title: "chore: update build output"
      - name: Show the pull request
        if: steps.build.outputs.pull-request-url != ''
        env:
          PR_URL: ${{ steps.build.outputs.pull-request-url }}
        run: echo "Build pull request $PR_URL"
```

## Protected branch, with a token

Mode `commit` with a personal access token or a GitHub App token that may bypass the protection.

<!-- example: examples/protected-branch-token.yml -->
```yaml
# A protected branch, with a token that may bypass the protection.
#
# BUILD_BOT_TOKEN is a repository secret: a personal access token, or a token of a GitHub
# App, that is allowed to bypass the branch protection or the ruleset of main. Only the
# commit step receives it. A push with such a token starts workflows, so keep [skip ci] in
# the commit message (the default has it), or this workflow runs again and again.
name: Build

on:
  push:
    branches: [main]

# The job reads the repository with the default token. The push uses BUILD_BOT_TOKEN.
permissions:
  contents: read

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          token: ${{ secrets.BUILD_BOT_TOKEN }}
          commit-message: "chore: update build output [skip ci]"
```

## Mode check on pull requests

<!-- example: examples/check.yml -->
```yaml
# Mode check: fail a pull request when the committed build output is stale.
#
# The action builds, compares the build output with the checked out commit and fails
# when a build file differs, is deleted or is new. It pushes nothing and reads no token,
# so the job needs only contents: read and it also works for pull requests from forks.
name: Check the build

on:
  pull_request:

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: check
```

## Mode build on pull requests

<!-- example: examples/build.yml -->
```yaml
# Mode build: test that the project builds, with nothing pushed.
#
# The action installs, builds and checks that every path of `paths` exists after the
# build. It needs no write permission and reads no token. `build:prod`, `dist` and
# `types` are examples: use the script and the folders of your project.
name: Build

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: build
          command: build:prod
          paths: |
            dist
            types
```
