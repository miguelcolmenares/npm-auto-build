<!-- agents-toolkit:planning-doc issue=2 -->
# Plan: rewrite as a composite action (issue #2)

Temporary file. The last commit of the branch removes it.

## Goal

Replace the Docker action with a composite action that supports only `mode: build`.
The full v3 input and output contract from #10 is declared now, so #3, #4 and #5
only add behavior. Any other mode fails at once with a clear error that names the
issue that implements it.

## Layout

| File | Responsibility | Reads the token? |
|---|---|---|
| `action.yml` | Contract (inputs, outputs), step order, `env:` per step | No (the token is not passed to any step in build mode) |
| `scripts/lib.sh` | Logging (`log_info`, `log_warn`, `log_error`, `die`), env file helpers, package manager detection, `run_without_token` | No |
| `scripts/validate-inputs.sh` | v2 alias mapping with warnings, mode gate, validation, normalization, writes `NAB_*` to `GITHUB_ENV` | No |
| `scripts/install.sh` | Dependency install (`npm ci`, yarn, pnpm or `install-command`) | No |
| `scripts/build.sh` | Run the build script, check that every `paths` entry exists | No |

Step order: validate, setup-node, install, build.

## Rules

- Inputs travel only through `env:` of each step. No `${{ inputs.x }}` inside `run:`.
- Validation: `paths` entries may not be empty, start with `-`, contain `..` or be
  absolute. `working-directory` may not contain `..` or be absolute. Values that
  contain a newline, or are longer than 1024 characters, are rejected. Spaces, quotes
  and `$()` are allowed and never interpreted, because every expansion is quoted.
- Install and build run through `run_without_token`, which unsets the known token
  variables (`GITHUB_TOKEN`, `GH_TOKEN`, `INPUT_TOKEN`, `INPUT_GITHUB_TOKEN`) even when
  the workflow exported one. Bats proves it by printing the environment.
- No directory guessing. A missing path is an error that lists the missing paths.
- Package manager, minimum only (issue #6 does the rest): `package-lock.json` is
  `npm ci`, `yarn.lock` is `yarn install --frozen-lockfile`, `pnpm-lock.yaml` is
  `pnpm install --frozen-lockfile`, else `npm install`. `ignore-scripts: true` adds
  `--ignore-scripts`. `install-command` overrides.
- v2 aliases (`github-token`, `directory`, `build-dir`, `build-only`, `create-pr`)
  are accepted and mapped in `validate-inputs.sh`, each with a warning that names the
  new input. The v3 input wins when it was moved away from its default.
- Bash 3.2 compatible (macOS), no GNU only flags.

## Tests (bats, `tests/`)

Fixture in `tests/fixture/`. Cases: input validation, alias mapping and warnings, a
missing path, a mode that is not `build`, install detection per lockfile (fake package
manager on `PATH`), token absent from install and build environments.

## CI

`bats` job on ubuntu, `self-test` job on ubuntu, macos and windows (`uses: ./` against
the fixture, then assert `tests/fixture/dist/out.txt`). Existing job names stay.

## Not in scope

Modes `commit`, `check`, `pr` (#3, #4, #5), corepack, yarn berry, private registries
(#6), README rewrite (#7), docs and security workflows (#11). No release, no tag.
