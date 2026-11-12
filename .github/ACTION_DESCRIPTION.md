# NPM Auto Build

**Builds your npm project and commits `dist/` for you**

A push runs your project's build, and the action commits the build output to the repository, so nobody has to do it by hand.

## What it does

The action installs your dependencies, runs your build script and, depending on the mode, commits the result, checks it, or opens a pull request with it. Your build runs without the write token. Only the commit step and the pull request step hold it.

## The four modes

- `commit` (default): builds, then commits the build output to the current branch.
- `check`: builds, then fails when the committed build output is stale.
- `pr`: commits the build output to a branch of its own and keeps one pull request up to date.
- `build`: builds and checks that the output exists, and pushes nothing.

## Also

- Node.js 24 by default, or the version you set.
- npm, pnpm, yarn classic and yarn berry, and private registries.
- A composite action that runs on Linux, macOS and Windows runners.
- Every action that it uses is pinned by commit SHA.

## Quick start

```yaml
name: Build
on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
```

The examples use `@v3`. See the README for the inputs, the outputs and the other modes, and the migration guide if you come from v2.
