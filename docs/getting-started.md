---
order: 1
---

# Getting started

The smallest working workflow for `mode: commit`, what it needs, and what to expect in the first run.

The tag `@v3` is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`. The examples write `@v3`.

## The workflow

This workflow builds the project on every push to `main` and commits the changed `dist/` folder to `main`. Copy it to `.github/workflows/build.yml`.

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

## What it needs

Mode `commit` needs two things in the workflow, with the default token:

- `permissions: contents: write` for the push.
- `persist-credentials: false` on `actions/checkout`. Without it, the checkout writes the token to `.git/config`, where the install and build scripts could read it. The action finds such a header before the install and the build. Mode `commit` and mode `pr` fail there, and mode `check` and mode `build` print a warning.

A `concurrency` group is a good idea whenever several runs can push to the same branch, as in the example. The build folders in `paths` may be in `.gitignore`, because the action adds them with `git add --force`.

The package needs a `package.json` with the build script, and a checkout of it with `actions/checkout`.

## What to expect in the first run

With no inputs the action installs Node.js 24, installs the dependencies, runs the `build` script of `package.json` and commits the `dist` folder. When the build output did not change, it makes no commit. That is normal.

- The commit message is `chore: update build output [skip ci]`, and the author is `github-actions[bot]`. The `[skip ci]` keeps a push made with a personal access token or a GitHub App token from starting the workflow again.
- The step sets the outputs `changed` and `commit-sha`. `changed` is `true` when the action pushed a commit, and `false` when nothing changed.
- The action does not guess the build directory. When the build writes somewhere other than `dist`, set `paths`, one path per line. A missing path is an error that lists it.
- A tag push and a `pull_request` event leave HEAD detached, so mode `commit` fails there with a message that says so. Use [mode check](./mode-check.md) for pull requests.

## Next steps

- [The four modes](./mode-commit.md): `commit`, `check`, `pr` and `build`.
- [Reference](./reference.md): every input and output.
- [Recipes](./recipes.md): protected branches, tag and pull request events, matrix and monorepo, private registries, pnpm and yarn.
- Moving from v2? See [Breaking changes](./breaking-changes.md).
