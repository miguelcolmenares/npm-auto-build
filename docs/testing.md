# Testing

How to test the action locally and what CI runs. This page describes the v3 composite
action on `main`. The Docker based scripts of v2 are gone, they stay in the `v2` tag.

## Local checks

```bash
npm test
```

It runs `shellcheck` on every tracked `*.sh` file, then `bats tests/` when bats is
installed. To install the tools on macOS:

```bash
brew install shellcheck bats-core
```

On Ubuntu: `sudo apt-get install -y shellcheck bats`. The tests need Node.js and npm
(the fixture is built with the real `npm`). Use Node 24 to match the action default.

## The bats tests

| File | What it covers |
|---|---|
| `tests/validate-inputs.bats` | Mode gate, input validation, values that must stay literal text (spaces, quotes, `$()`, a leading `-`, `..`, absolute paths, newlines, very long values) |
| `tests/aliases.bats` | The v2 inputs (`build-only`, `create-pr`, `directory`, `build-dir`, `github-token`) and their warnings |
| `tests/install.bats` | Install command per lockfile, with fake package managers on `PATH` |
| `tests/build.bats` | The real build of the fixture, a missing path, no directory guessing, scripts that do not exist |
| `tests/package-managers.bats` | Detection by the `packageManager` field and by each lockfile, two lockfiles, bun, yarn classic and berry, an explicit input, `install-command`, `ignore-scripts` for each manager, corepack, and the build command. The managers are fake binaries |
| `tests/registries.bats` | The private registry contract (see below), the `registry-url` and `scope` inputs, and a real `npm install` against a local registry that needs a token |
| `tests/token.bats` | The token is not in the environment of install and build scripts |
| `tests/check.bats` | Mode check in a throwaway git repository: fresh, modified, new, deleted and ignored files, line endings, the cap of 50 files, paths outside the repository, no token, the diff files, standalone use |
| `tests/commit.bats` | Mode commit against a local bare repository used as `origin`: commit and push, no second commit, detached HEAD, refused paths, rebase and retry, protected branch, author and message, and every place the token must not be |
| `tests/action.bats` | Rules about `action.yml` (composite, `shell: bash`, pinned actions, no expression inside `run:`) |

`tests/commit.bats` needs no network. Its `origin` is a bare repository on disk and the
working repository is a clone of it, both under `$BATS_TEST_TMPDIR`. A fake `git` first on
`PATH` records the arguments and the credential variables of every call, so the tests can
show that the token is in no argument list and reaches only `git fetch` and `git push`.
A `file://` remote ignores the `http.extraheader`, so the push itself proves nothing about
the credential: the tests check how the header is built (`nab_build_auth_header`) and how it
is passed (`nab_git_remote`) separately.

`tests/fixture/` is a tiny project without dependencies. Its `build` script writes
`dist/out.txt`. `tests/helpers.bash` holds the shared helpers.

`tests/fixtures/` (with an s) holds the projects for the package managers. `pnpm`, `yarn-classic` and
`yarn-berry` have no dependencies, a `packageManager` field and a lockfile made by that manager.
`registry/` has the small registry server and the package it serves. `tests/pm_helpers.bash` builds
the fake `npm`, `pnpm`, `yarn` and `corepack`. Each fake writes its arguments and the token and registry
variables it sees into a log, and the scripts run with a short `PATH`, so a manager installed on your
machine is never used.

## Package managers and private registries

How the install step picks the manager, with `package-manager: auto`:

1. The `packageManager` field of `package.json` (`npm@x`, `pnpm@x`, `yarn@x`). `bun` or any other name fails.
2. The lockfile: `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` or `npm-shrinkwrap.json`.
3. Otherwise npm, with `npm install` and a warning that the lockfile is missing.

Lockfiles of two managers and no `packageManager` field is an error that names both files. An explicit
`package-manager` input wins over everything, and the action still checks that the tool runs.

| Manager | Install command |
|---|---|
| npm | `npm ci` (`npm install` without a lockfile) |
| pnpm | `pnpm install --frozen-lockfile` (`--no-frozen-lockfile` without a lockfile) |
| yarn classic (1.x) | `yarn install --frozen-lockfile` |
| yarn berry (2+) | `yarn install --immutable` |

Berry is detected from `packageManager: yarn@2` or newer, then a `.yarnrc.yml` file, then a `__metadata:` line
in `yarn.lock`, then `yarn --version`. `ignore-scripts: true` adds `--ignore-scripts`, except for berry, which
has no such flag: the action sets `YARN_ENABLE_SCRIPTS=false` for that one command. `install-command` replaces
all of it, and the build still runs with the manager that detection picked (`pnpm run build`, `yarn run build`).

**Corepack.** `corepack enable` runs when the `packageManager` field names pnpm or yarn, or when pnpm or
yarn is chosen and not installed. The action never runs `npm install -g`. Without corepack the step fails and
says to install the manager in a step before the action, or to set `install-command`.

**Private registries.** The action has no registry or token input of its own. Give the registry to
`setup-node` through the two optional inputs, and give the token through the job environment:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      NODE_AUTH_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
    steps:
      - uses: actions/checkout@v7
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          mode: build
          registry-url: https://npm.pkg.github.com
          scope: "@my-org"
```

The contract, and the tests that hold it:

- `setup-node` writes an `.npmrc` with a `${NODE_AUTH_TOKEN}` placeholder, never the token. A project
  `.npmrc` that uses the same placeholder works the same way.
- The install and the build inherit `NODE_AUTH_TOKEN` and every `NPM_CONFIG_*`, `YARN_*` and `PNPM_*`
  variable that the job sets. `setup-node` itself sets `NPM_CONFIG_USERCONFIG` to its `.npmrc`.
- The GitHub token variables (`GITHUB_TOKEN`, `GH_TOKEN`, `INPUT_TOKEN`, `INPUT_GITHUB_TOKEN`,
  `ACTIONS_RUNTIME_TOKEN`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN`) never reach the install or the build.
- The scripts never write an `.npmrc` or any other file with a credential.
- `registry-url` is not a secret: a URL with a user name or password in it is refused.

**Risk.** Do not put the GitHub token in `NODE_AUTH_TOKEN`. The action removes `GITHUB_TOKEN` from the
install and the build, but it cannot hide a variable that you set on purpose, and the lifecycle scripts of
the dependencies (`postinstall`) can read `NODE_AUTH_TOKEN`. Use a token made for the registry, with read
access only. `ignore-scripts: true` also stops those scripts.

## Run the scripts by hand

The scripts read the `INPUT_*` variables that `action.yml` sets from the inputs. This
runs the same steps as the action does in `build` mode, against the fixture (the commit step
needs a git repository with an `origin`, see `tests/commit.bats`):

```bash
export GITHUB_ENV="$(mktemp)" GITHUB_OUTPUT="$(mktemp)"
export INPUT_MODE=build INPUT_PATHS=dist INPUT_COMMAND=build INPUT_WORKING_DIRECTORY=tests/fixture
bash scripts/validate-inputs.sh
# Load the values the validate step wrote, the way GitHub does between steps:
for key in NAB_MODE NAB_WORKDIR NAB_COMMAND NAB_INSTALL_COMMAND NAB_PACKAGE_MANAGER NAB_PATHS NAB_IGNORE_SCRIPTS; do
  export "$key=$(awk -v k="$key" '!f && index($0,k"<<")==1 {d=substr($0,length(k)+3); f=1; next} f && $0==d {exit} f' "$GITHUB_ENV")"
done
bash scripts/install.sh
bash scripts/build.sh
cat tests/fixture/dist/out.txt
```

## Use the check outside GitHub

`scripts/check.sh` needs only bash and git (2.16 or newer), so any CI can use it as the
gate. In Bitbucket Pipelines, after your own install and build steps:

```yaml
script:
  - npm ci
  - npm run build
  - NAB_PATHS=dist NAB_COMMAND=build bash scripts/check.sh
```

The step fails when the committed build output is stale. Without `GITHUB_OUTPUT` the
script prints `stale=true` or `stale=false`, and the error is printed as a plain
`::error::` line. It reads these variables:

| Variable | Meaning | Default |
|---|---|---|
| `NAB_PATHS` | Build output paths, one per line, relative to the working directory | `dist` |
| `NAB_WORKDIR` | Working directory, relative to the current one | `.` |
| `NAB_COMMAND` | The build script, only used in the message that says how to fix it | `build` |
| `NAB_PACKAGE_MANAGER` | `auto`, `npm`, `yarn` or `pnpm`, only used in the same message | `auto` |
| `RUNNER_TEMP` | Where `nab-check/diff.patch` and `nab-check/files.txt` are written | a `mktemp -d` directory, printed in the log |

It does not replace the rest of the action: it does not install dependencies, does not
run the build, and does not set up Node.js. Run those yourself before it. The checkout
must have `HEAD` with the build output committed, and a shallow clone is enough. It
does not upload the diff either, keep `diff.patch` with the artifacts feature of your CI.

How it decides: a tracked file that differs from `HEAD`, a tracked file that is deleted,
and a file that git does not track (new, or ignored by `.gitignore`) are stale. A
difference of carriage returns at the end of lines alone is not. A path that resolves
outside the repository is refused.

## Mode commit in a workflow

`mode: commit` (the default) builds the project, then commits the `paths` to the branch
that is checked out and pushes it. The workflow needs three things:

```yaml
permissions:
  contents: write            # the push needs write access

concurrency:                 # one run per branch at a time
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          persist-credentials: false   # the build cannot read a token from .git/config
      - uses: miguelcolmenares/npm-auto-build@<sha> # vX.Y.Z
        with:
          mode: commit
```

- **`persist-credentials: false`.** Without it `actions/checkout` writes the token to
  `.git/config`, where the install and build scripts can read it. The action prints a
  warning when it finds such a header in the config.
- **`permissions: contents: write`.** The default `GITHUB_TOKEN` of a read-only workflow
  cannot push.
- **`concurrency`.** If two runs push to the same branch, the second push is rejected. The
  action then fetches the branch, rebases its one commit on top and pushes again, up to three
  attempts, and it never force-pushes. A `concurrency` group avoids the race, and the extra
  build, in the first place. If the rebase conflicts, the step aborts it and fails.
- **A branch push.** A tag push and a `pull_request` event leave HEAD detached, so there is
  no branch to push to and the step fails with an error that says so. Use `mode: check` for
  pull requests.
- **A protected branch.** `GITHUB_TOKEN` cannot push there. Pass a personal access token or a
  GitHub App token that may bypass the protection as `token`, or use `mode: pr` (issue #5).
- **The loop risk.** The default message ends with `[skip ci]`. A push with `GITHUB_TOKEN`
  does not start workflows, but a push with a personal access token or a GitHub App token
  does, so keep `[skip ci]` in a custom `commit-message`. The step prints a notice when it is
  missing.

How the token is used: only the commit step receives it. It copies it into a shell
variable, masks it and its base64 form, and gives it to `git fetch` and `git push` only,
as an `http.extraheader` in the `GIT_CONFIG_*` environment variables of that one command.
It is never in a command line, a URL, `.git/config`, `git config --global` or a file.
This needs git 2.31 or newer, which every GitHub-hosted runner has.

## CI

| Job | What it does |
|---|---|
| `shellcheck` | Lints every tracked shell script |
| `workflows` | Parses every workflow and `action.yml` |
| `bats` | Runs `bats tests/` on Ubuntu |
| `self-test-check` | Commits a fresh build of `tests/fixture` locally and runs the action with `mode: check`, which must pass. Then it changes the build output without committing it and runs the action again, which must fail with `stale=true`, and downloads the artifact `npm-auto-build-stale-diff` to check the diff |
| `self-test-commit` | Runs `mode: commit` on Ubuntu on a throwaway branch, with `origin` pointed at a bare repository the job creates, so it never pushes to this repository. It checks the commit in that remote and `changed=true`, that a second run makes no commit (`changed=false`), and that a detached HEAD fails |
| `self-test-pm` | Runs the action against `tests/fixtures/pnpm`, `yarn-classic` and `yarn-berry` on Ubuntu, and checks `dist/out.txt` of each |
| `self-test` | Runs the action itself (`uses: ./`) against `tests/fixture` on Ubuntu, macOS and Windows in `mode: build`, and checks that `dist/out.txt` exists. It also checks that a mode that is not available yet (`pr`) fails |
