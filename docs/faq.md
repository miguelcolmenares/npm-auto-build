---
order: 22
---

# FAQ

Short answers, each taken from a page of this documentation. Every answer ends with the page that has the details.

## Why does the commit step fail with a detached HEAD error?

The event was a tag push or a `pull_request`. Both check out a commit and not a branch, so HEAD is detached and there is no branch to push to. Mode `commit` fails early with a message that names the options: a branch push, mode `check`, or mode `pr`. Mode `pr` refuses a detached HEAD too. In v2 the same event broke the push. Run mode `commit` on a branch push, and use mode `check` for pull requests and tags.

Details: [Tag and pull request events](./recipes.md#tag-and-pull-request-events), [Mode commit](./mode-commit.md#limits).

## Why does the commit not start the workflow again?

The default `commit-message` ends with `[skip ci]`. A push with `GITHUB_TOKEN` does not start workflows. A push with a personal access token or a GitHub App token does, so keep `[skip ci]` in your own `commit-message` in mode `commit`, or the workflow can run again and again. The step prints a notice when it is missing.

Details: [Mode commit](./mode-commit.md#limits), [Protected branch](./recipes.md#protected-branch).

## Why do checks not run on the pull request that mode pr opened?

A pull request made with `GITHUB_TOKEN` starts no other workflows. GitHub does this so that actions cannot trigger each other without end. A required check on the base branch then never runs on the bot's pull request. Pass a personal access token or a GitHub App token as `token` when checks are required. For the same reason, the default `commit-message` has no `[skip ci]` in mode `pr`: GitHub skips the checks of a pull request whose head commit has it.

Details: [Mode pr](./mode-pr.md#limits).

## Why does the build run without the token?

The action runs code that it does not control: the install scripts of your dependencies and your build script. So the write token never reaches them. The validate, install and build steps do not receive the `token` input, and the scripts remove the known GitHub token variables from the environment of the package manager. Only the commit step (mode `commit`) and the pull request step (mode `pr`) read `token`, and mode `check` and mode `build` read no token at all.

Details: [Architecture](./architecture.md), [Security](./security.md).

## Why does the action fail when my checkout kept its credentials?

`actions/checkout` writes the token to `.git/config` by default, where the install and build scripts could read it. The action finds such a header before the install. Mode `commit` and mode `pr` fail there, and mode `check` and mode `build` print a warning. Set `persist-credentials: false` on `actions/checkout`, and do not pass a token to it.

Details: [Getting started](./getting-started.md#what-it-needs), [Breaking changes](./breaking-changes.md).

## What changed in the runner? Is it still Alpine?

No. v2 ran in a Docker container on an Alpine image. v3 is a composite action that runs on the runner itself, on Linux, macOS and Windows. Your build now sees the tools of the runner, not the ones of an Alpine image. If your build relied on something in that image, install it in a step before the action. On a self-hosted runner, the action needs bash and git, and mode `pr` also needs `gh`.

Details: [Breaking changes](./breaking-changes.md), [Migrating from v2 to v3](./migration-v2-to-v3.md#the-action-is-composite-not-docker).

## The build finished but some paths do not exist. What do I do?

The action does not guess the build directory. Set `paths` to what your build writes, one path per line, relative to `working-directory`. v2 looked for `dist`, `build`, `lib`, `public`, `out` and `.next`, and v3 does not.

Details: [Reference](./reference.md#paths), [Mode build](./mode-build.md#limits).

## The push was rejected because the branch is protected. What do I do?

Use a personal access token or a GitHub App token that may bypass the protection as `token`, or use mode `pr` and let a person merge the pull request. The default `GITHUB_TOKEN` cannot push to a protected branch.

Details: [Protected branch](./recipes.md#protected-branch), [Example workflows](./example-workflows.md#protected-branch-with-a-token).

## Nothing was committed. Is something wrong?

No. The build output did not change. The action exits successfully without making a commit, and sets `changed` to `false`.

Details: [Getting started](./getting-started.md#what-to-expect-in-the-first-run).

## Does it work with pnpm, yarn and a private registry?

It works with npm, pnpm, yarn classic and yarn berry. With `package-manager: auto` it reads the `packageManager` field of `package.json`, then the lockfile, and it sets pnpm and yarn up with corepack. Bun is not supported. A private registry needs the inputs `registry-url` and `scope`, and a `NODE_AUTH_TOKEN` in the `env:` of the job.

Details: [pnpm and yarn](./recipes.md#pnpm-and-yarn), [Private registry](./recipes.md#private-registry).

## Can I run the check outside GitHub?

Yes. `scripts/check.sh` needs only bash and git, so any CI can run it. It does not install dependencies, does not run the build, and does not set up Node.js, so run those yourself before it.

Details: [Bitbucket Pipelines](./recipes.md#bitbucket-pipelines).

## Which tag do I use?

The tag `@v3` is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`. For a workflow that has a write token, pin the action to a full commit SHA with the version in a comment, because a tag can move.

Details: [Getting started](./getting-started.md), [Security](./security.md).

## Where do I report a security problem?

Privately, with GitHub's private vulnerability reporting. Do not open a public issue.

Details: [Security](./security.md#reporting-a-vulnerability).
