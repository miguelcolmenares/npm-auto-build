# NPM Auto Build

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/miguelcolmenares/npm-auto-build)](https://github.com/miguelcolmenares/npm-auto-build/releases)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-NPM%20Auto%20Build-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/npm-auto-build)
[![License](https://img.shields.io/github/license/miguelcolmenares/npm-auto-build?label=License)](LICENSE)
[![CI](https://github.com/miguelcolmenares/npm-auto-build/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/miguelcolmenares/npm-auto-build/actions/workflows/ci.yml)
[![CodeQL](https://github.com/miguelcolmenares/npm-auto-build/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/miguelcolmenares/npm-auto-build/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/miguelcolmenares/npm-auto-build/badge)](https://scorecard.dev/viewer/?uri=github.com/miguelcolmenares/npm-auto-build)

This GitHub Action builds and commits `dist/` for you. A push runs your project's build, and the action commits the build output to the repository, so nobody has to do it by hand.

It is not a general CI tool. It does one job and tries to do it safely: your build runs without the write token, and only two small steps ever hold it.

> **Version note.** This README describes v3. The tag `@v3` is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`. The examples below write `@v3`. The stable version today is `@v2`, and the [migration guide](docs/migration-v2-to-v3.md) lists what changed.

## Quick start

This workflow builds the project on every push to `main` and commits the changed `dist/` folder to `main`.

```yaml
name: Build
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
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
```

With no inputs the action installs Node.js 24, installs the dependencies, runs the `build` script of `package.json` and commits the `dist` folder. When the build output did not change, it makes no commit.

## The four modes

The `mode` input picks what the action does. The default is `commit`.

| Mode | What it does | Pushes | Needs the token |
|---|---|---|---|
| `commit` | Builds, then commits the build output to the checked out branch. | Yes, to that branch | Yes |
| `check` | Builds, then fails when the committed build output is stale. | No | No |
| `pr` | Builds, then commits the output to a branch of its own and keeps one pull request up to date. | Yes, to the bot branch only | Yes |
| `build` | Builds and checks that the output exists. | No | No |

### Mode commit

Use it when the branch accepts pushes from the workflow. This is the original behavior of the action, and the Quick start above is this mode. It needs a branch checkout. A tag push and a `pull_request` event leave HEAD detached, so the step fails there with a message that says so. The outputs `changed` and `commit-sha` tell what happened.

### Mode check

Use it on pull requests, to make sure that the build output in the branch is what the build makes. The job fails when a build file differs from `HEAD`, is deleted, or is new. It reads no token, so it also works for pull requests from forks. When the output is stale, the action sets the output `stale` to `true` and uploads the diff as an artifact.

```yaml
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

### Mode pr

Use it when the default branch does not accept direct pushes. The action commits the build output to its own branch, `auto-build/<checked out branch>` by default, and opens a pull request from it. A second run updates that same pull request and does not open another. It force-pushes only that branch, and refuses to write to a branch that it did not make.

```yaml
name: Build pull request
on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

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
        run: echo "$PR_URL"
```

With the default `GITHUB_TOKEN`, the repository setting "Allow GitHub Actions to create and approve pull requests" must be on. A pull request made with that token does not start other workflows, so required checks need a personal access token or a GitHub App token as `token`. The details are in [docs/testing.md](docs/testing.md#mode-pr-in-a-workflow).

### Mode build

Use it to test that the project builds, with nothing pushed. The action installs, builds, and checks that every path of `paths` exists after the build. It needs no write permission and reads no token.

```yaml
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

## Permissions and checkout

Mode `commit` and mode `pr` need two things in the workflow, with the default token:

- `permissions: contents: write` for the push. Mode `pr` also needs `pull-requests: write`.
- `persist-credentials: false` on `actions/checkout`. Without it, the checkout writes the token to `.git/config`, where the install and build scripts could read it. The action prints a warning when it finds such a header.

Mode `check` and mode `build` need only `contents: read` and a checkout. A `concurrency` group is a good idea whenever several runs can push to the same branch, as in the examples above. For a protected branch, see the [recipes](docs/recipes.md#protected-branch).

## The token

The action runs code that it does not control: the install scripts of your dependencies and your build script. So the write token never reaches them. The validate, install and build steps do not receive the `token` input, and the scripts remove the known GitHub token variables from the environment of the package manager. The `token` input is read only in the Commit step (mode `commit`) and the Pull request step (mode `pr`), and mode `check` and mode `build` read no token at all.

Those two steps give the token to `git fetch`, `git push` and, in mode `pr`, `gh`, for that one command. It goes through an `http.extraheader` in `GIT_CONFIG_*` variables and through `GH_TOKEN`. It is never in a command line, a URL, `.git/config` or a file, and it is masked in the log. A registry token that you set yourself, such as `NODE_AUTH_TOKEN`, is a different matter, see [the recipe](docs/recipes.md#private-registry). The full model is in [docs/threat-model.md](docs/threat-model.md).

## Inputs

| Input | Default | Description |
|---|---|---|
| `mode` | `commit` | What the action does: `commit`, `check`, `pr` or `build`. See the modes above. |
| `working-directory` | `.` | Directory with the `package.json`, relative to the workspace. |
| `command` | `build` | Name of the `package.json` script that builds the project. |
| `install-command` | (empty) | Command that installs the dependencies. Empty means the action picks it for the package manager. When set, `ignore-scripts` has no effect. |
| `package-manager` | `auto` | `auto`, `npm`, `yarn` or `pnpm`. Auto reads the `packageManager` field of `package.json`, then the lockfile. Bun is not supported. |
| `node-version` | `24` | Node.js version to install, for example `24` or `22.x`. Ignored when `node-version-file` is set. |
| `node-version-file` | (empty) | File with the Node.js version, for example `.nvmrc`, relative to the workspace. It wins over `node-version`. |
| `registry-url` | (empty) | Registry URL for `actions/setup-node`, for example `https://npm.pkg.github.com`. Set `NODE_AUTH_TOKEN` in the `env:` of the job. Never put a credential in the URL. |
| `scope` | (empty) | Scope of the registry, for example `@my-org`. Used only with `registry-url`. |
| `paths` | `dist` | Build output paths, one per line, relative to `working-directory`. Every path must exist after the build. |
| `token` | `${{ github.token }}` | GitHub token that pushes the build output and, in mode `pr`, opens the pull request. Read only by the commit and pr steps. |
| `commit-message` | `chore: update build output [skip ci]` | Commit message (modes `commit` and `pr`). Keep `[skip ci]` in mode `commit`. In mode `pr` the default is used without it. |
| `git-user-name` | `github-actions[bot]` | Git user name of the commit (modes `commit` and `pr`). |
| `git-user-email` | `github-actions[bot]@users.noreply.github.com` | Git user email of the commit (modes `commit` and `pr`). |
| `branch` | (empty) | Mode `pr`: the branch that holds the build output. Empty means `auto-build/<checked out branch>`. Only the action may write to it. |
| `pr-title` | `chore: update build output` | Pull request title (mode `pr`). It is set again on every run. |
| `pr-labels` | (empty) | Pull request labels, comma separated (mode `pr`). The labels must exist. They are added on every run and never removed. |
| `auto-merge` | `false` | Turn on auto-merge for the pull request (mode `pr`). The repository needs "Allow auto-merge" and required checks. |
| `ignore-scripts` | `false` | Install without lifecycle scripts. No effect when `install-command` is set. |
| `upload-diff` | `true` | Upload the diff of a stale build as an artifact (mode `check`). |
| `artifact-name` | `npm-auto-build-stale-diff` | Name of that artifact (mode `check`). Use a different name for each use of the action in one workflow run. |

The v2 inputs `github-token`, `directory`, `build-dir`, `build-only` and `create-pr` are still accepted as aliases and print a warning. They are not part of the v3 interface. The [migration guide](docs/migration-v2-to-v3.md) lists each one.

## Outputs

| Output | When it is set | Description |
|---|---|---|
| `changed` | Mode `commit` | `true` when the action pushed a commit with new build output, `false` when nothing changed. |
| `stale` | Mode `check` | `true` when the committed build output is out of date, `false` when it is fresh. |
| `commit-sha` | Mode `commit` | SHA of the pushed commit. Empty when nothing changed. |
| `pull-request-url` | Mode `pr` | URL of the pull request. Empty when nothing changed. |
| `pull-request-number` | Mode `pr` | Number of the pull request. Empty when nothing changed. |

In the other modes an output is empty.

## Package managers and registries

The action works with npm, pnpm, yarn classic and yarn berry. With `package-manager: auto` it reads the `packageManager` field of `package.json`, then the lockfile, and it sets pnpm and yarn up with corepack. A private registry needs the inputs `registry-url` and `scope`, and a `NODE_AUTH_TOKEN` in the `env:` of the job. The [recipes](docs/recipes.md) show both, and [docs/testing.md](docs/testing.md#package-managers-and-private-registries) has the full contract.

## More documentation

- [Recipes](docs/recipes.md): protected branches, tag and pull request events, matrix and monorepo, private registry, pnpm and yarn, and the check outside GitHub.
- [Migration guide from v2](docs/migration-v2-to-v3.md): renamed inputs, breaking changes, and how to stay on `@v2`.
- [Examples](examples/README.md): complete workflow files.
- [Testing guide](docs/testing.md): local checks, the bats tests, and what CI runs.
- [Architecture](docs/architecture.md): the two trust zones and what each script may do.
- [Threat model](docs/threat-model.md) and [security policy](SECURITY.md).
- [Changelog](CHANGELOG.md).

## Requirements

- A repository with a `package.json` that has the build script, and a checkout of it with `actions/checkout`.
- Git 2.31 or newer for the commit and pr steps. Every GitHub-hosted runner has it. Mode `pr` also needs the `gh` command, which GitHub-hosted runners have.
- The action is composite and runs on the host, not in a container. The repository's self-test runs mode `build` on Linux, macOS and Windows, and the other modes on Linux.

## Troubleshooting

| What you see | Why, and what to do |
|---|---|
| The commit step fails with a detached HEAD error. | The event was a tag push or a `pull_request`. Run mode `commit` on a branch push. Use mode `check` for pull requests. |
| The build finished but some paths do not exist. | The action does not guess the build directory. Set `paths` to what your build writes. |
| The push was rejected because the branch is protected. | Use a personal access token or a GitHub App token that may bypass the protection as `token`, or use mode `pr`. See the [recipes](docs/recipes.md#protected-branch). |
| The push was refused. | Check `permissions: contents: write`, that `token` is valid, and `persist-credentials: false` on the checkout. |
| The workflow runs again and again. | A push with a personal access token or a GitHub App token starts workflows. Keep `[skip ci]` in `commit-message` in mode `commit`. |
| Nothing was committed. | The build output did not change. This is normal. |

## Contributing

Contributions are welcome, as an issue or a pull request. Run `npm test` before you open one. It runs shellcheck on every shell script and the bats tests. [docs/testing.md](docs/testing.md) has the details.

## License

This project is licensed under the MIT License, see the [LICENSE](LICENSE) file.

## Author

**Miguel Colmenares**

- GitHub: [@miguelcolmenares](https://github.com/miguelcolmenares)
- Email: me@miguelcolmenares.com
