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
| `tests/architecture.bats` | The rules in [architecture.md](architecture.md): which scripts may read the token, run `git push` or `git fetch`, or call a network tool, the shape of every script header, and no `${{ }}` in a `run:` block |
| `tests/failure-paths.bats` | Gaps from the review for issue 11: a very long value in every input, a leading dash in `working-directory` and in the commit message, a fork pull request in mode commit and mode check, no step that can run the commit after a failure, and two runs at the same time on one branch |
| `tests/validate-inputs.bats` | Mode gate, input validation, values that must stay literal text (spaces, quotes, `$()`, a leading `-`, `..`, absolute paths, newlines, very long values) |
| `tests/aliases.bats` | The v2 inputs (`build-only`, `create-pr`, `directory`, `build-dir`, `github-token`) and their warnings |
| `tests/install.bats` | Install command per lockfile, with fake package managers on `PATH` |
| `tests/build.bats` | The real build of the fixture, a missing path, no directory guessing, scripts that do not exist |
| `tests/package-managers.bats` | Detection by the `packageManager` field and by each lockfile, two lockfiles, bun, yarn classic and berry, an explicit input, `install-command`, `ignore-scripts` for each manager, corepack, and the build command. The managers are fake binaries |
| `tests/registries.bats` | The private registry contract (see below), the `registry-url` and `scope` inputs, and a real `npm install` against a local registry that needs a token |
| `tests/token.bats` | The token is not in the environment of install and build scripts |
| `tests/check.bats` | Mode check in a throwaway git repository: fresh, modified, new, deleted and ignored files, line endings, the cap of 50 files, paths outside the repository, no token, the diff files, standalone use |
| `tests/pr.bats` | Mode pr against a local bare repository used as `origin`, with a fake `gh`: the bot branch and the pull request are made, a second run updates the same pull request, the base branch is never written to, the branch name guards, the lease, the auto-merge toggle, invalid inputs, and every place the token must not be |
| `tests/commit.bats` | Mode commit against a local bare repository used as `origin`: commit and push, no second commit, detached HEAD, refused paths, rebase and retry, protected branch, author and message, and every place the token must not be |
| `tests/action.bats` | Rules about `action.yml` (composite, `shell: bash`, pinned actions, no expression inside `run:`) |
| `tests/docs-examples.bats` | The YAML examples of the docs, through `tests/docs-examples.py`: each one is checked against `action.yml` offline, and a copy of the README with a made up input, an old reference or a missing permission must fail the check. It needs PyYAML (`python3 -m pip install pyyaml`), and skips without it outside CI |

`tests/commit.bats` needs no network. Its `origin` is a bare repository on disk and the
working repository is a clone of it, both under `$BATS_TEST_TMPDIR`. A fake `git` first on
`PATH` records the arguments and the credential variables of every call, so the tests can
show that the token is in no argument list and reaches only `git fetch` and `git push`.
A `file://` remote ignores the `http.extraheader`, so the push itself proves nothing about
the credential: the tests check how the header is built (`nab_build_auth_header`) and how it
is passed (`nab_git_remote`) separately.

`tests/pr.bats` works the same way, and adds a fake `gh` that logs its arguments and the
`GH_TOKEN` it sees, and keeps the one pull request it "opened" in a state file. It also lets a
test run a command just before a push (a racing run), to show that the lease refuses and that
the run looks at the branch again. The git helpers that `commit.sh` and `pr.sh` share
(`nab_git_remote`, `nab_build_auth_header` and the others) live in `scripts/git-lib.sh`.

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
2. The lockfile: `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` or `npm-shrinkwrap.json`. A bun lockfile
   (`bun.lock` or `bun.lockb`) with no other lockfile fails, next to another lockfile it is ignored.
3. Otherwise npm, with `npm install` and a warning that the lockfile is missing.

Lockfiles of two managers and no `packageManager` field is an error that names both files. An explicit
`package-manager` input wins over everything, and the action still checks that the tool runs.

| Manager | With a lockfile | Without a lockfile (a warning is printed) |
|---|---|---|
| npm | `npm ci` | `npm install` |
| pnpm | `pnpm install --frozen-lockfile` | `pnpm install --no-frozen-lockfile` |
| yarn classic (1.x) | `yarn install --frozen-lockfile` | `yarn install` |
| yarn berry (2+) | `yarn install --immutable` | `yarn install --no-immutable` |

Berry is detected from `packageManager: yarn@2` or newer, then a `.yarnrc.yml` file, then a `__metadata:` line
in `yarn.lock`, then `yarn --version`. `ignore-scripts: true` adds `--ignore-scripts`, except for berry, which
has no such flag: the action sets `YARN_ENABLE_SCRIPTS=false` for that one command. `install-command` replaces
all of it, `ignore-scripts` has no effect then (the action warns), and the build still runs with the manager that
detection picked (`pnpm run build`, `yarn run build`). The build step checks that this manager is on `PATH`, so an
`install-command` that does not install it fails with a message that names the manager.

**Corepack.** `corepack enable` runs when the `packageManager` field names pnpm or yarn, or when pnpm or
yarn is chosen and not installed. The action never runs `npm install -g`. Without corepack, a manager that is
already on `PATH` (for example from `pnpm/action-setup`) is used with a warning and still checked with `--version`.
Without corepack and without the manager the step fails and says to install it in a step before the action, or
to set `install-command`.

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
      - uses: ./ # becomes miguelcolmenares/npm-auto-build@v3 after the v3 release
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
- `registry-url` is not a secret: a URL with a user name, a password, a query (`?`), a fragment (`#`) or a
  setting such as `_authToken`, `token`, `password` or `apikey` in it is refused. An `http://` URL is
  accepted with a warning that the token travels in clear text, unless the host is `localhost` or `127.0.0.1`.

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
  GitHub App token that may bypass the protection as `token`, or use `mode: pr`.
- **The loop risk.** The default message ends with `[skip ci]`. A push with `GITHUB_TOKEN`
  does not start workflows, but a push with a personal access token or a GitHub App token
  does, so keep `[skip ci]` in a custom `commit-message`. The step prints a notice when it is
  missing.

How the token is used: only the commit step receives it (and the pr step in mode pr, see below). It copies it into a shell
variable, masks it and its base64 form, and gives it to `git fetch` and `git push` only,
as an `http.extraheader` in the `GIT_CONFIG_*` environment variables of that one command.
It is never in a command line, a URL, `.git/config`, `git config --global` or a file.
This needs git 2.31 or newer, which every GitHub-hosted runner has.

## Mode pr in a workflow

`mode: pr` is for a repository whose default branch does not accept direct pushes. It builds the
project, commits the `paths` to a branch of its own and keeps **one** pull request up to date.
The checked out branch is the base of the pull request.

```yaml
on:
  push:
    branches: [main]           # a branch push, not a tag and not a pull_request

permissions:
  contents: write              # the push of the bot branch
  pull-requests: write         # gh pr create, edit and merge

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@<sha> # vX.Y.Z
        id: build
        with:
          mode: pr
          pr-labels: build
          auto-merge: "false"
```

The repository setting that PR mode needs, with the default `GITHUB_TOKEN`: **Settings, Actions,
General, "Allow GitHub Actions to create and approve pull requests"**. Without it `gh pr create`
fails and the error says so. A personal access token or a GitHub App token as `token` does not need it.

- **A pull request made with `GITHUB_TOKEN` starts no other workflows.** GitHub does this so
  that actions cannot trigger each other without end. A required check on the base branch then
  never runs on the bot's pull request, so the pull request cannot merge. Pass a personal access
  token or a GitHub App token as `token` when checks are required. The default
  `commit-message` has no `[skip ci]` in this mode for the same reason: GitHub skips the checks of
  a pull request whose head commit has it, and the step prints a notice when a custom message has one.
- **What it does, in order.** It stages the `paths` (also when `.gitignore` ignores them), makes one
  commit on top of the base with `git commit-tree` (the base branch and the working tree do not move), and
  force-pushes it to the bot branch with `--force-with-lease=<branch>:<tip it looked at>`. Then it
  looks for an open pull request from that branch to the base. It opens one when there is none, and
  it sets the title again and adds the labels when there is one. A second run never opens another pull
  request. It sets `pull-request-url` and `pull-request-number`.
- **No difference means no pull request.** When the build output is the same as on the base, the
  step pushes nothing, opens nothing and leaves both outputs empty. A pull request that is already open
  is left as it is. When the branch already holds this exact build on the current base, nothing is
  pushed either.
- **The bot branch.** The `branch` input, or `auto-build/<base branch>`. The branch is rewritten
  on every run, so the action refuses to write to one that is not its own: the base branch, the
  default branch of the remote, a reserved name (`main`, `master`, `develop`, `development`, `dev`, `trunk`,
  `stable`, `production`, `prod`, `staging`, `gh-pages`, `HEAD`, `release`, `releases/*` and `release/*`, in any
  case), and a branch that exists but whose tip commit does not have the line
  `Generated-by: npm-auto-build`, which the action puts in every commit it makes. A bot branch cannot be
  protected against force-pushes: exclude it from the protection rules. A checked out branch that
  starts with `auto-build/` is refused too, it would make a pull request from a pull request branch.
- **A lease, never a plain force.** If a person or another run moves the branch between the look and
  the push, the lease makes git refuse. The step looks at the branch again and tries again, up to three
  attempts, and fails when it is still moving. Use a `concurrency` group so runs go one at a time.
- **`auto-merge: "true"`.** After the pull request is open, the step runs `gh pr merge --auto` with the
  first merge method that the repository allows (squash, then merge, then rebase). The repository needs
  "Allow auto-merge" and a protection rule with required checks on the base branch, or `gh` fails and the
  step fails with a message that says so. The pull request stays open and the outputs are already set.
  Auto-merge is never turned off by a run with `auto-merge: "false"`.
- **Labels.** `pr-labels` is a comma separated list. The labels must exist in the repository, `gh`
  does not create them. They are added on every run and never removed.

How the token is used: the pr step is the only other step that receives it. As in mode commit, it is
removed from the environment of the script and masked, and given to `git ls-remote`, `git fetch` and
`git push` as an `http.extraheader` in the `GIT_CONFIG_*` variables of that one command. It goes to
`gh` as `GH_TOKEN`, set for that one command only. It is in no command line, URL, git config file, output or
file, and the install and build steps never see it.

## CI

| Job | What it does |
|---|---|
| `shellcheck` | Lints every tracked shell script |
| `workflows` | Parses every workflow and `action.yml` |
| `bats` | Runs `bats tests/` on Ubuntu |
| `self-test-check` | Commits a fresh build of `tests/fixture` locally and runs the action with `mode: check`, which must pass. Then it changes the build output without committing it and runs the action again, which must fail with `stale=true`, and downloads the artifact `npm-auto-build-stale-diff` to check the diff |
| `self-test-commit` | Runs `mode: commit` on Ubuntu on a throwaway branch, with `origin` pointed at a bare repository the job creates, so it never pushes to this repository. It checks the commit in that remote and `changed=true`, that a second run makes no commit (`changed=false`), and that a detached HEAD fails |
| `self-test-pr` | Runs `mode: pr` on Ubuntu on a throwaway branch, with `origin` pointed at a bare repository the job creates and a stand-in `gh` first on `PATH`, so neither the push nor the pull request leaves the runner. It checks the bot branch in that remote (one commit on the base, with the output, the base unchanged), the outputs, that a second run opens no second pull request and pushes nothing, that auto-merge asks for `gh pr merge --auto`, and that the base branch, a protected name and a detached HEAD are refused. It does not open a real pull request: that needs a repository to open it in, so the `gh` calls are checked as a log and the real `gh` is only covered by its documented interface |
| `self-test-pm` | Runs the action against `tests/fixtures/pnpm`, `yarn-classic` and `yarn-berry` on Ubuntu, and checks `dist/out.txt` of each |
| `self-test` | Runs the action itself (`uses: ./`) against `tests/fixture` on Ubuntu, macOS and Windows in `mode: build`, and checks that `dist/out.txt` exists. It also checks that an unknown mode (`deploy`) fails |
| `docs-examples` | Runs `tests/docs-examples.py` on the README (with its inputs and outputs tables and every mode), on `examples/` and on the recipes, the migration guide, the docs index and the Marketplace text. It checks the YAML structure against `action.yml`: the action reference (`@v3`, `@main` or a commit SHA), the inputs and their values, the checkout and the permissions of each mode. It does not run the examples, the self-test jobs run the action itself |
