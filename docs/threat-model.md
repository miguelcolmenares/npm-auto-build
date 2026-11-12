# Threat model

This file describes what can go wrong with the action, what protects against it today (v2), and how the v3 design (#10) changes it.

- **v2** is the Docker action on `main` at commit `f82047c`. Line references such as `entrypoint.sh:30`, and the `README.md` references such as `README.md:551`, point to that commit (`README.md` at `f82047c`, not the current file). Re-check them when the files change.
- **v3 design** names the issue that builds the control. Nothing here is released.
- The **accepted risk** column is a proposal for the maintainer to confirm. It is not a decision yet.

## Assets

| Asset | Where it lives in v2 | Why it matters |
|---|---|---|
| The write token | Read from `INPUT_GITHUB_TOKEN` (`entrypoint.sh:30`), written to the global git config (`:141`) and to the `gh` login (`:144`) | It has whatever scopes the workflow grants (`action.yml:23-25`). With `contents: write` it can push to any branch the workflow allows. |
| The repository history | Commits (`entrypoint.sh:215`), pushes (`:258`), and PR branches (`:206`, `:224`) | A bad commit lands on the branch that the workflow runs on. |
| The built output | `BUILD_DIR` (`:97-113`), staged at `:173` or `:176` | Users run or deploy this output (for example `dist/`). |

## Actors

| Actor | Trust | What it can do | Control in v2 |
|---|---|---|---|
| Repository owner | Trusted | Chooses the workflow, the token and its `permissions:` | Workflow `permissions:` (README.md:36-37, 223). Misuse of scopes is out of scope (SECURITY.md). |
| Contributor with a pull request, same repository | Partly trusted | Changes the code that `npm ci` and `npm run build` run, with the workflow's token | None in v2. The token is in the process from the start (`:30`). |
| Fork | Untrusted | Changes the code that runs on `pull_request` | GitHub withholds secrets and gives a read-only token to workflows run from forks (GitHub platform rule, not a line in this repo). |
| Compromised dependency | Untrusted | Runs install scripts during `npm ci` (`:76`) | Lock file and `npm ci` (`:75-76`). No lock file means `npm install` (`:81`) takes the newest versions. |
| Compromised action | Untrusted | Runs in the user's workflow with the user's token | Users pin `@v2`, a moving tag (README.md:551). This repo's own workflows are pinned by SHA (`ci.yml:18`). |

## Trust boundaries

The boundary that matters is between the code that runs the project (install and build) and the code that holds the token (commit and push).

| Phase | Code that runs | Token in the environment | v2 lines |
|---|---|---|---|
| 1. Install | `npm ci`, `yarn install`, `npm install`, and their lifecycle scripts | Yes (`INPUT_GITHUB_TOKEN`, read at `:30`) | `:73-82` |
| 2. Build | The project's `npm run <command>` | Yes | `:92-94` |
| 3. Commit and push | Action code: git config, `gh auth`, `git add`, `git commit`, `git push`, `gh pr create` | Yes | `:135-145`, `:172-177`, `:215`, `:224`, `:231`, `:258` |

**In v2 there is no boundary.** All three phases run in one process inside one container, with the token in the environment. The v3 design (#2, #3) puts phases 1 and 2 on a runner step with no token, and only phase 3 reads it.

## Threats

| ID | Threat | How it works | Control in v2 (status) | v3 design | Accepted risk (proposed) |
|---|---|---|---|---|---|
| T1 | Install or build code reads the token | `INPUT_GITHUB_TOKEN` is in the environment from the start (`:30`). `npm ci` (`:76`) and `npm run` (`:94`) are child processes and inherit it. A build script can print or send it. | None (open) | #2: install and build run without the token. #3: only the commit step reads it. | Yes, for v2 until v3 ships. |
| T2 | A compromised dependency runs a script during install | `npm ci` runs the install scripts of every locked package (`:76`). Its code has the same access as T1. | Lock file used (`:75-76`, `:79`). Partial: with no lock file, `npm install` (`:81`) resolves new versions at build time. | #2 removes the token from install. #10 proposes an `ignore-scripts` input (default off). | Yes, for scripts of packages the owner chose. |
| T3 | A pull request runs code with the token | On `pull_request`, a branch from the same repository gets the workflow token. Its build runs with T1 access. A fork's pull request gets no secrets (platform rule). | Partial: fork rule from GitHub. Same-repository pull requests: none. A push from a `pull_request` run fails on a detached HEAD (`:258`), but the build still runs. | #3 refuses a detached HEAD with a clear error. #2 as T1. | Yes, for same-repository pull requests, in v2. |
| T4 | A bad action version reaches the user | Users write `@v2` (README.md:551), a tag that moves. A bad release or a moved tag runs in their workflow with their token. | None for users (open). This repo's workflows are pinned by SHA (`ci.yml:18`), and `workflow-security.yml` checks it. | #7: the README recommends a SHA pin for a workflow with a write token. #2: `setup-node` is pinned by SHA. | Yes, `@v2` is the documented way to use v2. |
| T5 | A compromised base image or package | `FROM node:20-alpine` (`Dockerfile:1`) and `apk add` without versions (`Dockerfile:4`) take whatever the tag points to today. | None (open). Planned for v2 in #11: pin the base image by digest and scan with Trivy. | #2 removes the image. | No. |
| T6 | Push loop | `:215` commits with `COMMIT_MESSAGE`, whose default has no `[skip ci]` (`:28`). A push made with a PAT starts the workflow again (README.md:188, 193). A build that is not reproducible commits again on every run. A push made with `GITHUB_TOKEN` does not start new runs (GitHub rule), so the loop needs a PAT or app token. | None (open). An unchanged build stops the loop by exiting 0 at `:194`. | #3: default message ends with `[skip ci]`, and the PAT loop is documented. | No. |
| T7 | Detached HEAD: the push fails after the commit | On a tag push or a `pull_request` run, HEAD is detached. The commit is made (`:215`), then `git push` (`:258`) fails with "You are not currently on a branch" (checked with git locally). The action exits 1 (`:289`) and leaves the commit in the workspace. | None (open). The message says "Failed to push changes" (`:286`) and does not name the cause. | #3: refuses before the commit, with a message that names `mode: check` or `mode: pr`. | No. |
| T8 | A directory is committed that the owner did not choose | If `BUILD_DIR` is missing, `:101-107` picks the first of `dist`, `build`, `lib`, `public`, `out`, `.next`. `:173` force-adds it. `:215` commits the whole index, so files that earlier steps staged are committed too. | Partial: only `BUILD_DIR` is staged (`:173`, `:176`). The commit still takes the whole index. | #2: no guessing, a missing path is an error. #3: only the configured `paths` are added, with `--force` on those paths. | No. |
| T9 | Push goes to a branch the owner did not intend, or rewrites history | `:258` pushes the current branch, with no refspec. No force push is used. The only `--force` is on `git add` (`:173`). | Partial: no force push. The branch is whatever the workflow runs on. | #3: pushes the current branch, rebases and retries, never force-pushes. #5: a fixed branch for `mode: pr`. | Yes, by design: the commit goes to the branch the workflow runs on. |
| T10 | Parallel runs lose their push | Two runs on one branch race. A push that is not a fast-forward fails and is not retried (`:258`). | None (open). | #3: rebase and retry, and a `concurrency` group in the docs. | No. |
| T11 | Build files are owned by the container user | The Dockerfile has no `USER` line (`Dockerfile:1-12`). Issue #2 records that the action runs as root, so files it writes can be root-owned in the workspace. | None (open). | #2: a composite action runs on the runner. | No. |

## Known v2 findings and the v3 fix

| Finding | Where in v2 | Threat | v3 fix |
|---|---|---|---|
| The token is visible to `npm ci` and build scripts | `entrypoint.sh:30`, `:76`, `:94` | T1 | #2 (no token during install and build), #3 (only commit reads it) |
| A detached HEAD breaks the push | `entrypoint.sh:215`, `:258` (tested locally) | T7 | #3 (refuses with a clear message), #5 (fixed branch) |
| Push loops with a PAT, or on every unchanged build | `entrypoint.sh:28`, `:215`; README.md:188, 193 | T6 | #3 (`[skip ci]` default, PAT loop documented) |
| A PR with a timestamp branch, and checks that never start with `GITHUB_TOKEN` | `entrypoint.sh:206`, `:224`, `:231`; the default token does not start workflows | T3, T6 | #5 (one PR on a fixed branch, updated in place, PAT or app token documented for checks) |
| The base image is not pinned by digest | `Dockerfile:1`, `:4` | T5 | #2 (no image). v2 until then: #11 pins by digest and scans with Trivy. |
| A directory is force-added after a guess | `entrypoint.sh:101-107`, `:173` | T8 | #2 (no guessing), #3 (`--force` only on configured paths) |
| Parallel runs collide on push, and there is no retry | `entrypoint.sh:258` | T10 | #3 (rebase and retry) |
| No lock file means `npm install` resolves new versions | `entrypoint.sh:81` | T2 | Not closed by #2 or #3. No issue requires a lock file yet. Open decision for the maintainer. |

## Scorecard alerts that are accepted or open

OpenSSF Scorecard runs on `main` and reports to the code scanning page. Dismissed on 2026-11-12, with the reason written on each alert:

| Check | Why it is accepted |
|---|---|
| Code-Review | This repository has one maintainer, so nobody else can approve a pull request. The risk is a change that nobody else read. It is reduced by the required checks and the protection of `main` (no force push, linear history, and the tests described in `docs/architecture.md`). It would be closed by a second maintainer. |
| Fuzzing | The action is shell scripts with no parser and no binary input, and Scorecard does not detect fuzzing for bash. The inputs are tested with hostile values (spaces, quotes, `$()`, a leading `-`, newlines and long strings) in `tests/validate-inputs.bats` and `tests/failure-paths.bats`. |

CII-Best-Practices stays open. It is closed by registering the project at bestpractices.dev and answering its questionnaire.

## Threat added after the first audit

| ID | Threat | Control in v3 | Test |
|---|---|---|---|
| T12 | A checkout that kept its credentials leaves the token in `.git/config`, where install and build code can read it | `validate-inputs.sh` refuses it in mode `commit` and mode `pr`, and warns in mode `check` and mode `build`, before the install | `tests/validate-inputs.bats`, the tests that name `persisted checkout credentials` |
