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
| `tests/token.bats` | The token is not in the environment of install and build scripts |
| `tests/action.bats` | Rules about `action.yml` (composite, `shell: bash`, pinned actions, no expression inside `run:`) |

`tests/fixture/` is a tiny project without dependencies. Its `build` script writes
`dist/out.txt`. `tests/helpers.bash` holds the shared helpers.

## Run the scripts by hand

The scripts read the `INPUT_*` variables that `action.yml` sets from the inputs. This
runs the same steps as the action does in `build` mode, against the fixture:

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

## CI

| Job | What it does |
|---|---|
| `shellcheck` | Lints every tracked shell script |
| `workflows` | Parses every workflow and `action.yml` |
| `bats` | Runs `bats tests/` on Ubuntu |
| `self-test` | Runs the action itself (`uses: ./`) against `tests/fixture` on Ubuntu, macOS and Windows, and checks that `dist/out.txt` exists. It also checks that a mode that is not available yet fails |
