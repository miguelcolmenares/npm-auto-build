# Releasing

This page is the procedure for the release `v3.0.0` and for every release after it. It lists what to check, the commands in order, who does each step, and how to go back. Nothing here is done by itself: **no tag, no release and no Marketplace publication happens until the maintainer says go** (issue #9).

The release is tested before it is made. `scripts/release-check.sh` checks that the repository is ready. Then `.github/workflows/release.yml` checks the tagged commit again, builds a source archive with a build provenance attestation and makes a draft release.

## What a release is

| Name | What it is | Who makes it | Moves later? |
|---|---|---|---|
| `v3.0.0` | The annotated, signed tag of the release commit. | The maintainer, on their machine. | Never. A fix is a new version. |
| `v3` | The floating tag that `@v3` in a workflow follows. | The release workflow, through the API. | Yes, to each new stable `v3.x.y`. |
| `v2` and `v2.1.2` | The v2 Docker action. | Nobody. | **No. They stay as they are.** |
| The GitHub release | The notes (the CHANGELOG section), the source archive and its attestation. | The release workflow makes a draft, the maintainer publishes it. | The notes can be edited. |
| The Marketplace listing | The name and the description of `action.yml`, for the published release. | The maintainer, from the release form. | At each published release. |

`v2` and `v2.1.2` never change, so every workflow that uses `@v2` keeps working. On 2026-11-12 `v2` is the annotated tag `7257f9f` and `v2.1.2` is the annotated tag `77ae815`, and both point at the commit `8c22581`. The pre-flight check prints the current `v2` value, and step 5 compares it.

## Who does what

| Step | Who |
|---|---|
| Say go | The maintainer |
| 1. The release pull request (CHANGELOG, version, date) | Anyone, the maintainer merges it |
| 2. Pre-flight on `main` | The maintainer (or an agent that only runs the script) |
| 3. Create and push the tag | The maintainer. It needs their signing key. |
| 4. The workflow | GitHub Actions, nobody acts |
| 5. Check the draft release | The maintainer |
| 6. Publish the release and the Marketplace listing | The maintainer. It needs a browser and two-factor authentication. |
| 7. The pull request after the release | Anyone, the maintainer merges it |

## Before you start

- The maintainer said go in issue #9. Without it, stop here.
- The security audit was repeated for the release. The list is "Repeat before each major release" in [`docs/audits/2026-11-12.md`](audits/2026-11-12.md).
- `gh auth status` shows an account with write access, and `git config user.signingkey` is set. The global setting `tag.gpgsign true` makes every `git tag -a` signed, so the command needs the passphrase of the key. Without that setting, use `git tag -s` and not `git tag -a`.
- The release workflow can run: in the repository settings, Actions are enabled. Public repositories are not blocked by the billing limit that stops private ones.

## The steps

### 1. The release pull request

```bash
git switch main && git pull --ff-only
git switch -c chore/release-3.0.0
```

Change four things, and nothing else:

1. `CHANGELOG.md`: rename `## [Unreleased]` to `## [3.0.0] - YYYY-MM-DD` with the day you will push the tag, then add an empty `## [Unreleased]` above it. The intro paragraph and every section stay. Nothing may stay under the new `[Unreleased]`.
2. `package.json` and `package-lock.json`: `npm version 3.0.0 --no-git-tag-version`. The package is private, so the files only hold the version.
3. `SECURITY.md`: nothing for v3.0.0. It must have no `TBD`.
4. `action.yml`: nothing, the description is already the listing text (see [the listing](#the-marketplace-listing-text)).

Do not remove the sentences that say `@v3` is available after the release. They are true until the tag exists, and step 7 removes them.

```bash
git commit -am "Release 3.0.0"
git push -u origin chore/release-3.0.0
gh pr create --title "Release 3.0.0" --body "CHANGELOG, package.json and package-lock.json for v3.0.0. Part of #9."
gh pr checks --watch
```

When every check is green, merge with a squash (the branch needs a linear history), and delete the branch.

### 2. Pre-flight on `main`

```bash
git switch main && git pull --ff-only
bash scripts/release-check.sh 3.0.0
```

Every line must be `PASS`, apart from the `SKIP` for `dependency-review`, which runs on pull requests only, and the `TODO` lines, which are step 7. The exit code is 0. A `SKIP` for another reason is not a pass: read what it says and check it by hand.

If a required check is still `in_progress`, wait for the push checks of `main` to finish and run it again.

### 3. Create and push the tag

```bash
git tag -a v3.0.0 -m "v3.0.0"
git tag -v v3.0.0
git cat-file -t v3.0.0
git push origin refs/tags/v3.0.0
```

`git tag -v` must say `Good signature`, and `git cat-file -t` must print `tag` (an annotated tag, not a lightweight one). Push only this one tag by name. Do not use `git push --tags`, which pushes every local tag.

The push starts the release workflow. After this step the tag `v3.0.0` is not changed, moved or deleted, unless the workflow failed before it made a release (see [Rollback](#rollback)).

### 4. The workflow

```bash
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

It has three jobs, described in [the release workflow](#the-release-workflow). When one fails, read its log, do not re-tag. A failure from the network can be repeated with `gh run rerun --failed`.

### 5. Check the draft release

```bash
gh release view v3.0.0 --json isDraft,tagName,targetCommitish,assets --jq '.'
mkdir -p /tmp/npm-auto-build-release && gh release download v3.0.0 --pattern '*.tar.gz' --dir /tmp/npm-auto-build-release
gh attestation verify /tmp/npm-auto-build-release/npm-auto-build-3.0.0.tar.gz --repo miguelcolmenares/npm-auto-build
git ls-remote --tags origin | grep -E 'refs/tags/(v2|v2\.1\.2|v3|v3\.0\.0)(\^\{\})?$'
```

Check each of these:

- The release is a draft, has the archive as an asset, and the notes are the `[3.0.0]` section of the CHANGELOG.
- `gh attestation verify` says it verified the archive.
- The line `refs/tags/v3.0.0^{}` is listed, so `v3.0.0` is an annotated tag. The line is the commit of the tag. It equals the commit of `refs/tags/v3`, and both are the commit of the release pull request.
- `v2` is still `7257f9f720f912ebb7973258b1b79a9fb67e730a`, `v2.1.2` is still `77ae815cd4c6226741946ffbc766d98654491e34`, and both peel to the commit `8c22581033b30b631ff66f6c1b72fa3bdc2ea312`.

### 6. Publish the release and the Marketplace listing

```bash
gh release view v3.0.0 --web
```

In the release form, press Edit, and then:

1. Check that the title is `v3.0.0` and the notes are right. Add nothing to the tag.
2. Select "Publish this release to the GitHub Marketplace". The form checks `action.yml` and shows an error or a warning when something is wrong. Fix it before you go on: that is a change to `main` and, if it touches `action.yml`, a new tag.
3. Keep the name `NPM Auto Build` and the categories that the listing already has. The listing text is the `description` of `action.yml`, shown in [the listing](#the-marketplace-listing-text).
4. Select "Set as the latest release", and press Publish release.

The release form was not run for this procedure, because nothing is published before the go. If the form has no Marketplace box for a draft, publish the release and use the box in the edit form of the published release.

Then check the acceptance of issue #9. The Marketplace page shows `v3.0.0` and the new description. The tag `v2` still resolves to the same commit.

### 7. The pull request after the release

The docs promise `@v3` before it exists, in several places (`scripts/release-check.sh` prints each file). Once the tag exists they are false, so remove them now. The test `the docs stop saying that @v3 is not released once a v3 tag exists` fails in any clone that fetched the tag until you do.

```bash
git switch main && git pull --ff-only
git switch -c chore/after-release-3.0.0
bash scripts/release-check.sh 3.0.0   # prints the TODO lines, they are the list below
```

| File | What to change |
|---|---|
| `README.md` | Delete the "Version note" paragraph. The release badge shows the latest tag by itself. |
| `docs/README.md` | Delete `, which is available after the v3 release. Until then, use the full commit SHA of a commit on main, or @main` and keep the rest of the sentence. |
| `docs/recipes.md` | The same sentence in the first paragraph. |
| `docs/migration-v2-to-v3.md` | The sentence `The tag @v3 is available after the v3 release. Until then, ...`. |
| `examples/README.md` | The same sentence. |
| `docs/testing.md` | In the comment of the self-test step, `becomes ...@v3 after the v3 release` becomes `is ...@v3 for users`. |
| `docs/getting-started.md`, `docs/faq.md`, `docs/breaking-changes.md`, `docs/example-workflows.md` | The same sentence in each of the site pages. `scripts/release-check.sh` lists every `docs/*.md` page that still has it. |
| `site/sitekit.config.json` | Remove "in development" from `site.version` and from the home badge. |
| `SECURITY.md` | The v3 row says `Supported`, with no "Not released yet". The v2 row says that v2 support ended with the release of v3.0.0. |

Then, in this pull request, delete the section "Draft of the 3.0.0 release summary" below, which is history once the release is out. Run the whole suite and the check again:

```bash
bats tests/
bash scripts/release-check.sh --tag 3.0.0   # run only where the tag exists locally: git fetch --tags
```

The `TODO` lines are gone from `release-check.sh 3.0.0`, and `bats tests/` passes with the tag present. Merge as usual.

## The release workflow

`.github/workflows/release.yml` starts only on a push of a tag that matches `v3.*.*`. A later major version (`v4`) needs its own pattern, because the workflow moves the floating tag `v3`. A pull request, a push to a branch or a manual run does not start it.

| Job | Permissions | What it does |
|---|---|---|
| `verify` | `contents: read` | Runs `scripts/release-check.sh --tag`. It checks that the tag is the version of the CHANGELOG, `package.json` and `package-lock.json`, that the CHANGELOG section has a date and notes, that nothing is under `[Unreleased]`, that `SECURITY.md` has no `TBD`, the `action.yml` description and branding, and that every `uses:` is pinned. It also checks that the tag points at the commit and that the commit is on `main`. Then it runs `bats tests/` without the tests tagged `post-release`. |
| `provenance` | `contents: read`, `id-token: write`, `attestations: write` | Makes `npm-auto-build-<version>.tar.gz` with `git archive` and `gzip -n`, and attests its build provenance with `actions/attest-build-provenance`. The only job that has the two write permissions for the attestation. |
| `release` | `contents: write` | Makes the archive again and fails when its SHA-256 differs from the attested one. Creates the release as a **draft**, with the CHANGELOG section as the notes. Moves `v3` to the release commit. The only job that can write to the repository. |

How it behaves:

- The workflow never publishes to the Marketplace and never publishes the release. A draft keeps the Marketplace step in the hands of the maintainer.
- `v3` moves only for a stable version that is the highest `v3.x.y` tag. A pre-release such as `v3.1.0-rc.1`, or a patch for an older version, leaves `v3` where it is. The job sets the tag through the API and needs no git credentials. The tag is a lightweight tag.
- A second run for the same tag finds the release and makes nothing. It still checks `v3`.
- No `run:` block has a `${{ }}` expression. The tag name, the repository and the token reach the shell only through `env:`. The checkout does not keep credentials. Every action is pinned by a 40 character SHA.

### Moving `v3` by hand

Use this only when the workflow could not, and only for the floating tag. Replace the SHA and the old value.

```bash
git fetch --tags
git tag -fa v3 -m "v3" <commit of the release>
git push --force-with-lease=refs/tags/v3:<the old commit of v3> origin refs/tags/v3
```

`--force-with-lease` is only for `v3`. Never use it, or `--force`, for `v3.0.0` or for any exact version.

## Rollback

| Where you are | What to do |
|---|---|
| Before step 3 (no tag) | Nothing was released. Fix the cause, and run the check again. |
| Tag pushed, the workflow failed, no release exists | If the cause was the network, `gh run rerun --failed`. If the cause is in the commit, delete the tag and tag the fixed commit: `git push origin :refs/tags/v3.0.0` and `git tag -d v3.0.0`. Fix through a pull request, then repeat steps 3 to 5. |
| A draft release exists and is wrong, not published | `gh release delete v3.0.0 --yes`, then delete the tag as in the row above. If the workflow already created `v3`, delete it too: `git push origin :refs/tags/v3`. Then repeat from step 3. |
| The release is published and something is wrong | **Do not delete or move `v3.0.0`.** Workflows and people may have pinned it. Fix `main`, release `v3.0.1` with the same steps, and the workflow moves `v3`. Edit the notes of the bad release to say which version fixes it. |
| `v3` points at a bad release, and a good `v3.x.y` exists | Move `v3` back with [Moving `v3` by hand](#moving-v3-by-hand), to the commit of the good release. |
| The Marketplace listing is wrong | Edit the release, change the Marketplace box or the `description` of `action.yml`, and publish a new release. The Marketplace shows the latest published release. |
| `v2` or `v2.1.2` moved by mistake | Put them back to the values of step 5 with the command of [Moving `v3` by hand](#moving-v3-by-hand), for the tag that moved. Tell the maintainer, because workflows that use `@v2` may have run in between. |

## The Marketplace listing text

The listing text is the `description` of `action.yml`, and issue #9 asks for it. The name does not change.

```text
Build your project and commit the output, so you do not commit dist/ by hand. Can also check it is current, or open a PR.
```

It has 121 characters. `scripts/release-check.sh` fails when it has more than 125, the number that the publish form is reported to enforce. The public GitHub docs state no limit for it, so the 125 is a safe bound and not a quoted rule. `.github/ACTION_DESCRIPTION.md` is the long text for the repository and is not the listing text.

## Draft of the 3.0.0 release summary

The notes of the GitHub release are the `[3.0.0]` section of the CHANGELOG, with no change. This is the summary at the top of that section, and the list of breaking changes under it. They are the same text as the intro of `[Unreleased]` today, so a change to one is a change to the other.

```markdown
v3.0.0 is a rewrite of the action. It is a composite action that runs on the runner, on Linux, macOS and Windows, with Node.js 24 by default. Its modes are `commit` (the default, the original behavior), `check`, `pr` and `build`. Your build runs without the write token. v2 keeps working through the `v2` tag. The v2 input names still work in v3, with a warning. Read the [migration guide](https://github.com/miguelcolmenares/npm-auto-build/blob/main/docs/migration-v2-to-v3.md) before you change `@v2` to `@v3`.

Breaking changes from v2:
- The default Node.js version is 24, and `node-version` has an effect.
- The action does not guess the build directory. Set `paths`, which is `dist` by default.
- A detached HEAD (a tag push or a `pull_request` event) is an error in mode `commit`.
- The pull request branch is fixed (`auto-build/<branch>`), so a pull request is updated and not opened again.
- The action runs on the host and not in an Alpine container.
- `build-only` is `mode: build` and `create-pr` is `mode: pr`. The old names work for now, with a warning.
- Two lockfiles of different package managers are an error, and a checkout that kept its credentials is refused in modes `commit` and `pr`.
- v2 support ends with this release.
```
