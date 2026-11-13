# Workflow examples

Complete workflow files for NPM Auto Build v3. Copy one to `.github/workflows/` in your repository and change the build script and the paths.

The files write the action as `miguelcolmenares/npm-auto-build@v3`.

Every file here is checked against `action.yml` by `tests/docs-examples.py`, in the bats tests and in the CI job `docs-examples`. The check is structural: each input exists, the mode is valid, the checkout has `persist-credentials: false` and the job has the permissions that the mode needs. It does not run the workflows. The script names, directories and secret that the files use (`build:prod`, `build:lib`, `apps/*`, `packages/ui`, `BUILD_BOT_TOKEN`) are yours to define.

| File | What it shows |
|---|---|
| [`quick-start.yml`](./quick-start.yml) | The smallest workflow: mode `commit` on pushes to `main`. |
| [`check.yml`](./check.yml) | Mode `check` on pull requests: fail when the committed build output is stale. |
| [`build.yml`](./build.yml) | Mode `build` on pull requests: test that the project builds, with nothing pushed. |
| [`complete-workflow.yml`](./complete-workflow.yml) | Mode `check` on pull requests, and mode `commit` on pushes to `main`, in one workflow. |
| [`monorepo.yml`](./monorepo.yml) | One job per package, each with its own `working-directory` and `paths`, pushed one after the other. |
| [`protected-branch-pr.yml`](./protected-branch-pr.yml) | Mode `pr`: a bot branch and one pull request, for a branch that does not accept direct pushes. |
| [`protected-branch-token.yml`](./protected-branch-token.yml) | Mode `commit` with a personal access token or a GitHub App token that may bypass the protection. |

## How to use them

1. Copy the file to `.github/workflows/` and rename it if you like.
2. Set `command` to the `package.json` script that builds your project, and `paths` to what the build writes. The action does not guess the build directory.
3. Keep `persist-credentials: false` on `actions/checkout` for the modes that push, and the `permissions` of the job.
4. Add the secrets that the file names, if any.

More setups, such as private registries, pnpm and yarn, tag events and Bitbucket Pipelines, are in the [recipes](../docs/recipes.md). What changed from v2 is in the [migration guide](../docs/migration-v2-to-v3.md).
