---
order: 12
---

# Mode pr

Builds, then commits the output to a branch of its own and keeps one pull request up to date.

Use it when the default branch does not accept direct pushes. The action commits the build output to its own branch, `auto-build/<checked out branch>` by default, and opens a pull request from it. A second run updates that same pull request and does not open another. A person merges it.

## Example

<!-- example: examples/protected-branch-pr.yml -->
```yaml
# A branch that does not accept direct pushes: mode pr.
#
# The action commits the build output to its own branch (auto-build/main by default) and
# keeps one pull request up to date, so main is never written to. A person merges it.
#
# With the default GITHUB_TOKEN, turn on "Allow GitHub Actions to create and approve pull
# requests" in the repository settings (Settings, Actions, General). A pull request made
# with that token starts no other workflows. When you require checks on main, pass a
# personal access token or a GitHub App token as `token` (see protected-branch-token.yml).
# The bot branch is rewritten on every run, so exclude it from branch protection.
name: Build pull request

on:
  push:
    branches: [main]

permissions:
  contents: write # the push of the bot branch
  pull-requests: write # open and update the pull request

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
        run: echo "Build pull request $PR_URL"
```

## Outputs

| Output | Value |
|---|---|
| `pull-request-url` | URL of the pull request. Empty when nothing changed. |
| `pull-request-number` | Number of the pull request. Empty when nothing changed. |

The other outputs are empty in this mode.

## What it does, in order

It stages the `paths` (also when `.gitignore` ignores them), makes one commit on top of the base with `git commit-tree` (the base branch and the working tree do not move), and force-pushes it to the bot branch with `--force-with-lease=<branch>:<tip it looked at>`. Then it looks for an open pull request from that branch to the base. It opens one when there is none, and it sets the title again and adds the labels when there is one. A second run never opens another pull request.

When the build output is the same as on the base, the step pushes nothing, opens nothing and leaves both outputs empty.

## The repository setting

With the default `GITHUB_TOKEN`, the repository setting **Settings, Actions, General, "Allow GitHub Actions to create and approve pull requests"** must be on. Without it `gh pr create` fails and the error says so. A personal access token or a GitHub App token as `token` does not need it.

## Limits

- **A pull request made with `GITHUB_TOKEN` starts no other workflows.** GitHub does this so that actions cannot trigger each other without end. A required check on the base branch then never runs on the bot's pull request, so the pull request cannot merge. Pass a personal access token (fine-grained, with Contents and Pull requests set to read and write) or a GitHub App token as `token` when checks are required. See the [recipe](./recipes.md#protected-branch).
- **The bot branch is rewritten on every run.** The action refuses to write to one that is not its own: the base branch, the default branch of the remote, a reserved name (`main`, `master`, `develop` and similar, in any case), and a branch that exists but whose tip commit does not have the line `Generated-by: npm-auto-build`. A bot branch cannot be protected against force-pushes: exclude it from the protection rules.
- **A lease, never a plain force.** If a person or another run moves the branch between the look and the push, git refuses. The step looks again and tries again, up to three attempts, and fails when the branch is still moving. Use a `concurrency` group so runs go one at a time.
- **Several jobs need several branches.** In a matrix, all jobs would use the same bot branch and overwrite each other. Give each job its own `branch`, or build all packages in one job.
- **`auto-merge: "true"`** runs `gh pr merge --auto` with the first merge method that the repository allows (squash, merge, rebase). The repository needs "Allow auto-merge" and a protection rule with required checks on the base branch, or the step fails with a message that says so.
- **Labels.** `pr-labels` is a comma separated list. The labels must exist in the repository. They are added on every run and never removed.
- **A branch push only.** Like mode `commit`, it needs a branch checkout.
- **The commit message.** The default `commit-message` has no `[skip ci]` in this mode, because GitHub skips the checks of a pull request whose head commit has it.

The job needs `contents: write` and `pull-requests: write`, and `persist-credentials: false` on the checkout. The pr step is the only other step that receives the token, and it gives it to `git ls-remote`, `git fetch`, `git push` and, as `GH_TOKEN`, to `gh` for one command at a time.
