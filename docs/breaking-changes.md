---
order: 30
---

# Breaking changes, v2 to v3

What breaks when you change `@v2` to `@v3`, in one place. This page is the short form. The steps, the warnings that each renamed input prints and a before and after workflow are in the [migration guide](./migration-v2-to-v3.md).

v3 keeps the idea of v2: build the project and commit the build output for you. It changes how the action runs, how it uses the token, and how it names its inputs. For most workflows, three edits are enough:

1. Change `@v2` to `@v3`.
2. Add `persist-credentials: false` to `actions/checkout`, and remove `token:` from the checkout.
3. Rename the inputs in the table below, or leave them, they still work and print a warning.

The tag `@v3` is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`.

## The changes

| Change | In v2 | In v3 |
|---|---|---|
| [The action is composite, not Docker](./migration-v2-to-v3.md#the-action-is-composite-not-docker) | A Docker container on an Alpine image. | A composite action that runs on the runner itself, on Linux, macOS and Windows. Install what your build needs in a step before the action. |
| [Node 24 is the default, and `node-version` works](./migration-v2-to-v3.md#node-24-is-the-default-and-node-version-works) | `node-version` had no effect, the container used its own Node.js. | The action installs the version you ask for with `actions/setup-node`. The default is `24`. `node-version-file` wins over `node-version`. |
| [The token is only in the commit and pr steps](./migration-v2-to-v3.md#the-token-is-only-in-the-commit-and-pr-steps) | The token was in the same container as `npm ci` and your build. | The validate, install and build steps never receive it. Set `persist-credentials: false` on `actions/checkout`. If the checkout keeps its credentials, mode `commit` and mode `pr` fail before the install, and mode `check` and mode `build` print a warning. |
| [No guessing of the build directory](./migration-v2-to-v3.md#no-guessing-of-the-build-directory) | It looked for `dist`, `build`, `lib`, `public`, `out` and `.next`. | It commits the folders of `paths`, which defaults to `dist`. A path that does not exist after the build fails the step and is listed. |
| [A detached HEAD is an error](./migration-v2-to-v3.md#the-default-mode-is-commit) | A tag push or a `pull_request` event broke the push. | Mode `commit` fails early with a message that names the options: a branch push, mode `check`, or mode `pr`. |
| [Mode `pr` keeps one pull request](./migration-v2-to-v3.md#mode-pr-keeps-one-pull-request) | `create-pr: true` made a new timestamped branch and a new pull request on every run. | One branch, `auto-build/<checked out branch>` by default, and one pull request kept up to date. |
| [`build-only` and `create-pr` are modes](./migration-v2-to-v3.md#renamed-inputs) | Two boolean inputs. | `mode: build` and `mode: pr`. Mode `check` is new. |
| [The default `commit-message`](./migration-v2-to-v3.md#the-default-mode-is-commit) | `chore: update build files`. | `chore: update build output [skip ci]`. Keep `[skip ci]` in your own message. |
| [Package manager detection](./migration-v2-to-v3.md#other-changes) | It always preferred `package-lock.json`. | It reads the `packageManager` field first, then the lockfile. Two lockfiles of different managers and no `packageManager` field fail. |

## Renamed inputs

The v2 names are accepted as aliases. Each one prints a warning that names the new input. The aliases are a bridge, not part of the v3 interface, and no release date is promised for their removal. Rename them now.

| v2 input | v3 input |
|---|---|
| `github-token` | `token` |
| `directory` | `working-directory` |
| `build-dir` | `paths` |
| `build-only: true` | `mode: build` |
| `create-pr: true` | `mode: pr` |

What each warning says, and how each alias behaves when both names are set, is in the [migration guide](./migration-v2-to-v3.md#renamed-inputs). The other v2 inputs keep their name: `command`, `commit-message`, `git-user-name`, `git-user-email` and `node-version`.

## Changed defaults

| Input or behavior | v2 | v3 |
|---|---|---|
| `node-version` | No effect. | `24`, and it works. |
| `paths` | Guessed from `dist`, `build`, `lib`, `public`, `out` and `.next`. | `dist`, with no guessing. |
| `commit-message` | `chore: update build files` | `chore: update build output [skip ci]` |
| `token` | `github-token`, required. | `${{ github.token }}`, no longer required. |
| `mode` | None. | `commit`, which builds and commits as v2 did. |
| A detached HEAD | The push failed. | An error that names `mode: check`, a branch push and `mode: pr`. |
| A rejected push | Not retried. | Retried up to three times, with a fetch and a rebase of the one build commit. The action never force-pushes in mode `commit`. |

## Stay on v2

v2 keeps working through the `v2` tag, and the last release is `v2.1.2`. Pin one of them:

<!-- docs-examples: skip -->
```yaml
- uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Use `@v2.1.2` instead of `@v2` when you want a build that never changes. v2 does not get the changes of this page. The README that describes v2 is in the `v2` tag.

v2 is supported until v3.0.0 is published. From that day v2 gets no patches, and the `v2` tag stays as it is, so plan the move to v3. See the [security policy](../SECURITY.md).
