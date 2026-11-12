# Architecture

This page explains how the action is split into scripts, and which rules keep the write token away from the project's code. The rules are checked by `tests/architecture.bats`, so a change that breaks one fails CI. For what can go wrong and how the design answers it, see the [threat model](threat-model.md).

## Two trust zones

The action runs code it does not control: the install scripts of the project's dependencies and the project's own build script. It also holds a token that can write to the repository. These two things must not meet. The action is split in two zones, and the token lives only in the second one.

```
 Zone 1: no token                               Zone 2: token
 runs the project's code                        runs only this action's code

 validate-inputs.sh                             commit.sh   (mode commit)
        |                                              ^
        v                                              |
 install.sh  ->  build.sh  ->  check.sh        the build output on disk
                               (mode check)     (the `paths` entries)
        |                                              |
        +----------------------------------------------+
```

Zone 1 never reads the token. `install.sh` and `build.sh` start every package manager through `run_without_token`, which removes `GITHUB_TOKEN`, `GH_TOKEN`, `INPUT_TOKEN`, `INPUT_GITHUB_TOKEN`, `ACTIONS_RUNTIME_TOKEN` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN` from the environment of the child process. Variables that the workflow author sets on purpose for a private registry, such as `NODE_AUTH_TOKEN`, are kept.

Zone 2 runs after the build. In `action.yml` only the Commit step has the token in its `env:`, as `NAB_TOKEN`. `commit.sh` hands it to `git fetch` and `git push` only. In the same way only the Pull request step has it for the mode `pr`, and `pr.sh` uses it for `git` and for `gh`. `git-lib.sh` is the shared helper of both: it builds the credential header and runs the git commands with it.

The files that the build writes are the only thing that crosses from zone 1 to zone 2. The commit step stages the `paths` entries and nothing else.

## What each script may do

| Script | Zone | Step | What it does | May not |
|---|---|---|---|---|
| `scripts/validate-inputs.sh` | 1 | Validate inputs | Reads the `INPUT_*` variables, checks every value, writes `NAB_*` to `GITHUB_ENV` and the outputs to `GITHUB_OUTPUT`. | Read the token, run the project's code, use the network. |
| `scripts/install.sh` | 1 | Install dependencies | Installs the dependencies with the package manager, or with `install-command`. | Read the token, run git, write outside the project directory. |
| `scripts/build.sh` | 1 | Build | Runs the build script and checks that every `paths` entry exists. | Read the token, run git, guess a build directory. |
| `scripts/check.sh` | 1 | Check the build output | Compares the build output with `HEAD` and reports `stale`. Works outside GitHub too. | Read a token, run the project's code, use the network, change the repository. |
| `scripts/commit.sh` | 2 | Commit | Stages the `paths` entries, commits with the configured author and pushes to the checked out branch. | Put the token on a command line, in a URL, in a file or in the output. Force-push. Run the project's code. |
| `scripts/pr.sh` | 2 | Pull request | Commits the build output to a bot branch, pushes it with a lease and opens the pull request, or updates the one that exists. | Overwrite a branch that it did not make, push to the base branch, put the token on a command line or in a file. |
| `scripts/git-lib.sh` | 2 | none | Helpers that `commit.sh` and `pr.sh` source: the credential header, `nab_git_remote` and the classifier of push failures. | Be used by a script of zone 1. Print the token. |
| `scripts/lib.sh` | both | none | Helpers that the other scripts source: logging, env file writers, package manager detection, `run_without_token`. | Read or print a token. It only lists the variable names that `run_without_token` removes. |

## The rules the tests enforce

Each rule below has a test in `tests/architecture.bats`. A rule counts only after it was seen failing: the test was run against a script that breaks it on purpose.

| Rule | How it is checked |
|---|---|
| `install.sh` and `build.sh` never name a token variable. | The six names above, plus `NAB_TOKEN`, `ACTIONS_ID_TOKEN_REQUEST_URL` and `secrets.`, are searched in the code lines. Comments are skipped. |
| Only the allowlist scripts name a token variable. | The allowlist is at the top of the test file: `commit.sh`, `pr.sh` and the shared helper `git-lib.sh`. `lib.sh` may name the variables only on the `-u` lines of `run_without_token`. |
| Only the allowlist scripts run `git push`, `git fetch`, `git pull`, `git clone` or `git ls-remote`. | The same search, for the git commands that talk to a remote and for the `nab_git_remote` wrapper. A new script that needs the remote must be added to the allowlist, and this page must say why. |
| No script calls `curl`, `wget`, `ssh`, `npx` or another network tool, and only the allowlist scripts call `gh`. | The package manager is the only way out of the machine for zone 1. In zone 2, `pr.sh` uses `gh` for the pull request. |
| `install.sh` and `build.sh` start the project's code only through `run_without_token`, and do not run git. | A code line must not start with a package manager, a shell or `eval`. |
| No script turns off `errexit`, `nounset` or `pipefail`, and none installs a tool for the whole machine or touches the home directory or a system path. | A search for `set +e`, `npm install -g`, `git config --global`, `$HOME`, `~/` and `/etc/`. |
| No `run:` block of `action.yml` holds a `${{ }}` expression. | A block form such as `run: \|` is read too. A value reaches a script only through `env:`. |
| Every script has a header with `May do:` and `May not:`, or says it is sourced. | The comment block under the shebang. |
| Every script is named in the docs and has a row in the table above, and every script path in the docs exists. | The docs are searched for `scripts/<name>`. |

Rules that other test files already hold are not repeated: every script starts with `set -euo pipefail` (`tests/action.bats`), the token is read in one step of `action.yml` only (`tests/action.bats`), and the token never reaches an install or build script at run time (`tests/token.bats`, `tests/commit.bats`). Shellcheck runs in CI.

## Limits

The architecture tests read the scripts as text. They look for names. They do not see an indirect read such as `${!name}`, a command assembled from pieces, or what a third-party action does. `actions/setup-node` and `actions/upload-artifact` are pinned by commit SHA and sit outside these rules. The behavior tests, which print the environment of a real install and build, are the other half of the protection.
