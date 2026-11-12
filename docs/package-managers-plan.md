<!-- agents-toolkit:planning-doc issue=6 -->
# Plan for issue #6: pnpm, yarn berry and private registries

Branch `feat/6-package-managers`, based on `feat/2-composite-action` (PR #16). Only `mode: build` exists, so this work touches the install step and the detection, and adds two inputs.

## Detection (`package-manager: auto`)

1. The `packageManager` field of `package.json` (`npm@x`, `pnpm@x`, `yarn@x`). `bun` and any other name fail with a message that lists the supported managers.
2. Lockfiles: `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` or `npm-shrinkwrap.json`. A bun lockfile alone fails too.
3. No lockfile: npm, with `npm install` and a `::warning::`.
4. Two lockfiles of different managers and no field: fail and name both. No guessing.
5. An explicit `package-manager` input wins over everything, but the binary is still checked with `--version`.

## Yarn classic and berry

Berry (2+) when, in this order: the field says `yarn@2` or newer, `.yarnrc.yml` exists, `yarn.lock` has a `__metadata:` line, or `yarn --version` says 2 or newer (read after corepack, when yarn is on PATH). Otherwise classic.

- classic: `yarn install --frozen-lockfile`
- berry: `yarn install --immutable`
- `ignore-scripts`: `--ignore-scripts` for npm, pnpm and yarn classic, `YARN_ENABLE_SCRIPTS=false` in the environment of the berry command.

## Corepack

`corepack enable` runs when the field names pnpm or yarn, or when pnpm or yarn is the chosen manager and its binary is missing. Never `npm install -g`. Then `<pm> --version` must work. Without corepack the step fails and says how to install the manager (a step before the action, or `install-command`). npm ships with Node.js, so a field `npm@x` does not call corepack.

## Code layout

- `scripts/lib.sh`: `nab_resolve_package_manager` (pure detection, used by install and build), `nab_prepare_package_manager` (corepack and the version check), `nab_detect_yarn_berry`.
- `scripts/install.sh`: the commands per manager, the lockfile warning.
- `scripts/build.sh`: unchanged, it already runs `$NAB_RESOLVED_PM run <command>`.

## Private registries

No new credential handling. The contract, documented and tested: the install and build steps inherit `NODE_AUTH_TOKEN` and `NPM_CONFIG_*`, `YARN_*`, `PNPM_*` from the job `env:`, a project `.npmrc` with `${NODE_AUTH_TOKEN}` works, the GitHub token variables never reach them, and the scripts never write `.npmrc`. New optional inputs `registry-url` and `scope` go to the existing setup-node step. They are validated (single line, http or https, no credentials in the URL).

## Tests

- `tests/package-managers.bats`: fake managers on a restricted PATH that record argv and the relevant environment.
- `tests/registries.bats`: the environment contract with fakes, and one real npm install against a local registry that needs a bearer token (`tests/fixtures/registry/`).
- `tests/fixtures/{pnpm,yarn-classic,yarn-berry}`: tiny real projects, and a `self-test-pm` CI job over them.

## Commits

`feat:` detection and corepack, `feat:` registry inputs, `test:` fixtures and bats, `ci:` self-test-pm, `docs:` testing and changelog, then `git rm` of this file.
