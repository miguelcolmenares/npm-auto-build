---
order: 11
---

# Mode check

Builds, then fails when the committed build output is stale. It pushes nothing.

Use it on pull requests, to make sure that the build output in the branch is what the build makes. The job fails when a build file differs from `HEAD`, is deleted, or is new. It reads no token, so it also works for pull requests from forks.

## Example

<!-- example: examples/check.yml -->
```yaml
# Mode check: fail a pull request when the committed build output is stale.
#
# The action builds, compares the build output with the checked out commit and fails
# when a build file differs, is deleted or is new. It pushes nothing and reads no token,
# so the job needs only contents: read and it also works for pull requests from forks.
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

## Outputs

| Output | Value |
|---|---|
| `stale` | `true` when the committed build output is out of date, `false` when it is fresh. |

When the output is stale, the step exits 1 and the action uploads `diff.patch` and `files.txt` as the artifact `npm-auto-build-stale-diff` (set `upload-diff: false` to turn it off, and `artifact-name` to rename it). The other outputs are empty in this mode.

## How it decides

A tracked file that differs from `HEAD`, a tracked file that is deleted, and a file that git does not track (new, or ignored by `.gitignore`) are stale. A difference of carriage returns at the end of lines alone is not. A path that resolves outside the repository is refused.

On a pull request, `actions/checkout` checks out the merge of the pull request and its base by default, and the check compares with that commit. To fix a stale build, run the build locally and commit the output, or run [mode commit](./mode-commit.md) on the branch.

## Limits

- The job needs only `contents: read` and a checkout.
- Output that git does not track, ignored files included, counts as stale, so commit the build output before you use this mode.
- Use an `artifact-name` that is different for each use of the action in one workflow run. A duplicate name makes the upload fail.
- The check also runs without GitHub: `scripts/check.sh` needs only bash and git. See the [recipe for Bitbucket Pipelines](./recipes.md#bitbucket-pipelines).
