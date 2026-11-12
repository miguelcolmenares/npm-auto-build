# Security policy

This action holds a write token and runs your build command, so a security problem can change your repository. Please report it privately.

## Reporting a vulnerability

Report it with GitHub's private vulnerability reporting:

https://github.com/miguelcolmenares/npm-auto-build/security/advisories/new

Do not open a public issue or pull request for a security problem.

Include:

- The version, tag or commit that you tested, and whether it is v2 (Docker action, `entrypoint.sh`) or v3 (composite action, from `main`).
- The workflow snippet that triggers the problem. Remove any real secret or token first.
- The steps to reproduce it, with what you expected and what happened.
- The impact as you see it, for example which token scope would be exposed.
- A suggested fix, if you have one. This is optional.

The threat model in [`docs/threat-model.md`](docs/threat-model.md) lists the risks that are already known, with their status. A report that matches one of them is still welcome. It helps to say which threat it is.

## Response times

- We acknowledge a report within 7 days.
- Within 30 days we either publish a fix, or decide and tell you why the report is accepted or declined.
- A Dependabot security update is merged within 7 days when its severity is high or critical, and within 30 days for the others, once the checks pass.

## Supported versions

| Version | Status |
|---|---|
| v3, development on `main` | Supported. Not released yet, so there is no tag to use. |
| v2 (`v2` tag and `v2.x.x`) | Supported until v3.0.0 is published. From that day v2 gets no patches, and the `v2` tag stays as it is. Use v3, see the [migration guide](docs/migration-v2-to-v3.md). |
| v1 | Not supported. |

## Out of scope

- A build script in your own project that does something harmful. The action runs your build command, so what it runs is your code.
- A token that you gave more permissions than the action needs, for example a personal access token with admin scope. Give the workflow `permissions:` the least it needs, and use a token that only has access to the repository.
