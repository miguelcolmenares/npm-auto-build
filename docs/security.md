---
order: 40
---

# Security

This action holds a write token and runs your build command, so a security problem can change your repository. This page says how the token is handled, links the documents that go deeper, and says how to report a problem.

## The token

The action runs code that it does not control: the install scripts of your dependencies and your build script. So the write token never reaches them. The validate, install and build steps do not receive the `token` input, and the scripts remove the known GitHub token variables from the environment of the package manager. The `token` input is read only in the Commit step (mode `commit`) and the Pull request step (mode `pr`), and mode `check` and mode `build` read no token at all.

Those two steps give the token to `git fetch`, `git push` and, in mode `pr`, `gh`, for that one command. It goes through an `http.extraheader` in `GIT_CONFIG_*` variables and through `GH_TOKEN`. It is never in a command line, a URL, `.git/config` or a file, and it is masked in the log.

What the workflow must do:

- Set `persist-credentials: false` on `actions/checkout`. A checkout that kept its credentials leaves the token in `.git/config`, where install and build code can read it. The action looks for it before the install. Mode `commit` and mode `pr` fail, and mode `check` and mode `build` print a warning.
- Pin the action to a full commit SHA, with the version in a comment (`uses: miguelcolmenares/npm-auto-build@<40-character SHA> # vX.Y.Z`), in a workflow that has a write token, because a tag can move.
- Give a registry token that you set yourself, such as `NODE_AUTH_TOKEN`, read access only. The action cannot hide a variable that you set on purpose. See the [recipe](./recipes.md#private-registry).

## The documents

| Document | What it has |
|---|---|
| [Architecture](./architecture.md) | The two trust zones, what each script may do, and the rules that `tests/architecture.bats` enforces. |
| [Threat model](./threat-model.md) | The assets, actors and trust boundaries, the threats T1 to T12 with the control and the test for each, and the known v2 findings with the v3 fix. T12 is a checkout that kept its credentials. |
| [Security audit, 2026-11-12](./audits/2026-11-12.md) | The first written audit. Each statement is labeled observed, measured, estimated or proposed, and the limits of the audit are listed. |
| [Security policy](../SECURITY.md) | How to report a vulnerability, the response times and the supported versions. |

The accepted-risk column of the threat model is a proposal for the maintainer to confirm. It is not a decision yet.

## Reporting a vulnerability

Report it with GitHub's private vulnerability reporting:

https://github.com/miguelcolmenares/npm-auto-build/security/advisories/new

Do not open a public issue or pull request for a security problem. Say which version, tag or commit you tested, include the workflow snippet that triggers the problem (with any real secret or token removed) and the steps to reproduce it. The full list is in the [security policy](../SECURITY.md).

## Response times

- We acknowledge a report within 7 days.
- Within 30 days we either publish a fix, or decide and tell you why the report is accepted or declined.
- A Dependabot security update is merged within 7 days when its severity is high or critical, and within 30 days for the others, once the checks pass.

## Supported versions

| Version | Status |
|---|---|
| v3 (`v3` tag and `v3.x.x`) | Supported. |
| v2 (`v2` tag and `v2.x.x`) | Not supported since v3.0.0 was published. v2 gets no patches, and the `v2` tag stays as it is. Use v3, see the [migration guide](./migration-v2-to-v3.md). |
| v1 | Not supported. |

## Out of scope

- A build script in your own project that does something harmful. The action runs your build command, so what it runs is your code.
- A token that you gave more permissions than the action needs, for example a personal access token with admin scope. Give the workflow `permissions:` the least it needs, and use a token that only has access to the repository.
