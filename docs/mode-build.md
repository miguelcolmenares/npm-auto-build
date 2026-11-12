---
order: 13
---

# Mode build

Builds and checks that the output exists. It pushes nothing.

Use it to test that the project builds. The action installs, builds, and checks that every path of `paths` exists after the build. It needs no write permission and reads no token.

## Example

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

## Outputs

None. Every output is empty in this mode.

## Limits

- The action does not guess the build directory. It uses the `paths` input, one path per line, relative to `working-directory`, and `dist` by default. Every path must exist after the build, or the step fails and lists the missing ones.
- The job needs only `contents: read` and a checkout.
- It does not compare the output with the repository. To fail a pull request when the committed output is stale, use [mode check](./mode-check.md).
- The repository's own self-test runs this mode on Linux, macOS and Windows.
