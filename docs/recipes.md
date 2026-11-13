# Recipes

Short answers for the setups that come up most. Each workflow below is checked against `action.yml` by `tests/docs-examples.py`: the inputs exist, the modes are valid, and the permissions and the checkout match what the mode needs. The check is structural. It does not run the workflows.

The action is written as `@v3`.

- [Protected branch](#protected-branch)
- [Tag and pull request events](#tag-and-pull-request-events)
- [Matrix and monorepo](#matrix-and-monorepo)
- [Private registry](#private-registry)
- [pnpm and yarn](#pnpm-and-yarn)
- [Bitbucket Pipelines](#bitbucket-pipelines)

## Protected branch

The default `GITHUB_TOKEN` cannot push to a protected branch. There are two ways out. Use a token that may bypass the protection, or use mode `pr` and let a person merge the pull request.

The first way is a personal access token, or a token of a GitHub App, that is allowed to bypass the branch protection or the ruleset. Pass it as `token`. The action gives it only to the commit step. A push with such a token starts workflows, so keep `[skip ci]` in the commit message (the default has it).

```yaml
name: Build
on:
  push:
    branches: [main]

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
```

The second way is mode `pr`. The action pushes the build output to a branch of its own and keeps one pull request up to date, so the protected branch is never written to. A pull request made with `GITHUB_TOKEN` does not start other workflows, so required checks would never run on it. When you require checks, give mode `pr` a personal access token (fine-grained, with Contents and Pull requests set to read and write) or a GitHub App token as well.

```yaml
name: Build pull request
on:
  push:
    branches: [main]

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
          mode: pr
          token: ${{ secrets.BUILD_BOT_TOKEN }}
```

The bot branch is rewritten with a force-push on every run. Do not protect it against force-pushes, and do not use a branch name that belongs to people. With the default `GITHUB_TOKEN` the repository setting "Allow GitHub Actions to create and approve pull requests" must be on. See [docs/testing.md](testing.md#mode-pr-in-a-workflow).

## Tag and pull request events

A tag push and a `pull_request` event check out a commit, not a branch, so HEAD is detached. Mode `commit` and mode `pr` need a branch to push to, and fail with a clear message there. Use mode `check` on these events. It builds, compares the build output with the checked out commit, and fails when they differ. It does not push and it reads no token, so the job needs only `contents: read`, and it works for pull requests from forks.

```yaml
name: Check the build
on:
  pull_request:
  push:
    tags: ["v*"]

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

On a pull request, `actions/checkout` checks out the merge of the pull request and its base by default, and the check compares with that commit. When the check fails, the artifact `npm-auto-build-stale-diff` holds `diff.patch` and `files.txt`. To fix it, run the build locally and commit the output, or run mode `commit` on the branch.

## Matrix and monorepo

Give each package its own job, its own `working-directory` and its own `paths`. The `paths` entries are relative to `working-directory`.

Two runs that push to the same branch at the same time can collide. The action retries a rejected push three times, with a fetch and a rebase, and never force-pushes. To avoid the race, put the `concurrency` group on the workflow, not on the job. A job level group is shared by all the matrix jobs, and GitHub keeps only one running and one pending job in a group, so it would cancel the others. Then set `max-parallel: 1`, so the matrix jobs push one after the other.

```yaml
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
        package: [web, admin, shared-ui]
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          working-directory: packages/${{ matrix.package }}
          paths: dist
          commit-message: "chore(${{ matrix.package }}): update build output [skip ci]"
```

Each job makes its own commit, and only when its build output changed. In mode `pr`, all jobs would use the same bot branch and overwrite each other. Give each job its own `branch`, for example `auto-build/main-${{ matrix.package }}`, or build all packages in one job. In mode `check` the jobs do not push, so they can run in parallel and `max-parallel` is not needed.

## Private registry

When the dependencies come from a private registry, give the registry to the action with `registry-url` and `scope`, and give the token through the environment of the job. The action passes both to `actions/setup-node`, which writes an `.npmrc` that reads `NODE_AUTH_TOKEN`. The token is not in the file.

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
    env:
      NODE_AUTH_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: miguelcolmenares/npm-auto-build@v3
        with:
          registry-url: https://npm.pkg.github.com
          scope: "@my-org"
          ignore-scripts: true
```

Use a token made for the registry, with read access only. Do not put the GitHub token in `NODE_AUTH_TOKEN`. The action removes the GitHub token variables from the install and the build, but it cannot hide a variable that you set on purpose, and the lifecycle scripts of your dependencies can read `NODE_AUTH_TOKEN`. That is why the example sets `ignore-scripts: true`. Remove it if a dependency needs its install script. Your build script runs with the same environment and can read the variable too, so keep the registry token read only. A `registry-url` with a user name, a password, a query or a token setting in it is refused. The contract is in [docs/testing.md](testing.md#package-managers-and-private-registries).

## pnpm and yarn

With `package-manager: auto`, the action reads the `packageManager` field of `package.json`, then the lockfile. Set the field, and the action runs `corepack enable` and uses that version. It runs `pnpm install --frozen-lockfile` for pnpm, `yarn install --frozen-lockfile` for yarn classic and `yarn install --immutable` for yarn berry.

```json
{
  "packageManager": "pnpm@10.34.9"
}
```

The workflow needs no extra step.

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

Two lockfiles of different managers, with no `packageManager` field, is an error that names both files. Set `package-manager` to choose one. Bun is not supported. Without corepack, a pnpm or yarn that is already on the `PATH` is used, with a warning. When it is not there, the step fails and asks for it. Install it in a step before the action, or set `install-command`.

## Bitbucket Pipelines

The check is a bash script that needs only bash and git, so any CI can run it. Bitbucket cannot use the action, so clone this repository at a commit that you reviewed, and run `scripts/check.sh` after your own install and build. The script reads `lib.sh` next to it, so keep the whole `scripts/` directory.

```yaml
pipelines:
  pull-requests:
    "**":
      - step:
          name: Check the build output
          image: node:24
          script:
            - npm ci
            - npm run build
            - git clone --quiet https://github.com/miguelcolmenares/npm-auto-build.git /tmp/nab
            - git -C /tmp/nab checkout --quiet <commit SHA>
            - NAB_PATHS=dist NAB_COMMAND=build bash /tmp/nab/scripts/check.sh
```

The step fails when the committed build output is stale. `NAB_PATHS` takes one path per line, and `NAB_WORKDIR` sets the working directory. The other variables, and what the script does and does not do, are in [docs/testing.md](testing.md#use-the-check-outside-github). It does not upload the diff. The log prints where `diff.patch` was written, so add that file to the artifacts of the step if you want it.
