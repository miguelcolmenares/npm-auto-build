# 📚 NPM Auto Build Action - Documentation

Welcome to the comprehensive documentation for NPM Auto Build Action.

## 📖 Documentation Index

- **[Architecture](architecture.md)** - The two trust zones, what each script may do, and the rules the tests enforce
- **[Testing Guide](testing.md)** - Complete guide for local testing
- **[Examples](../examples/README.md)** - Complete workflow files: check and commit, monorepo, and protected branch (pr and token)
- **[Main README](../README.md)** - Getting started and basic usage
- **[Recipes](recipes.md)** - Protected branches, tag and pull request events, monorepos, private registries, pnpm and yarn, Bitbucket
- **[Migration guide](migration-v2-to-v3.md)** - From v2 to v3: renamed inputs, breaking changes, staying on `@v2`

## 🎯 Quick Links

### For Users
- [Getting Started](../README.md#quick-start)
- [The four modes](../README.md#the-four-modes)
- [Inputs](../README.md#inputs)
- [Troubleshooting](../README.md#troubleshooting)

### For Contributors
- [Local Testing](testing.md)
- [Development Scripts](../scripts/)
- [Contributing Guidelines](../README.md#contributing)

## 🔧 Advanced Configuration

The examples use `@v3`, which is available after the v3 release. Until then, use the full commit SHA of a commit on `main`, or `@main`. Complete workflows are in the [recipes](recipes.md) and in [`examples/`](../examples/README.md).

### Custom Build Environments

```yml
- name: Build with a specific Node version
  uses: miguelcolmenares/npm-auto-build@v3
  with:
    node-version: '22'
    command: 'build:prod'
```

### Monorepo Support

For projects with several packages, use one job per package, each with its own `working-directory` and `paths`. See [Matrix and monorepo](recipes.md#matrix-and-monorepo).

### Permissions

```yml
# mode: commit
permissions:
  contents: write

# mode: pr
permissions:
  contents: write
  pull-requests: write

# mode: check and mode: build
permissions:
  contents: read
```

### Protected Branches

For a branch with protection rules, use a token that may bypass the protection, or mode `pr`. See [Protected branch](recipes.md#protected-branch).

## 🛠️ Technical Details

### How It Works

1. **Validate**: checks every input and maps the v2 names to the v3 ones.
2. **Environment setup**: installs Node.js and the dependencies, without the token.
3. **Build execution**: runs the `package.json` script of `command`, without the token, and checks that every `paths` entry exists.
4. **Mode step**: `commit` commits and pushes the paths to the checked out branch, `check` compares them with `HEAD`, `pr` commits them to a bot branch and keeps one pull request up to date, and `build` does nothing more.

### Supported Package Managers

- **Detection** (`package-manager: auto`): the `packageManager` field of `package.json`, then the lockfile, then npm without a lockfile. Two lockfiles of different managers is an error. An explicit `package-manager` input wins.
- **npm**: `npm ci` with a lockfile, `npm install` without one
- **pnpm**: `pnpm install --frozen-lockfile`, set up with corepack when it is not installed
- **yarn**: classic `yarn install --frozen-lockfile`, berry `yarn install --immutable`
- **bun** is not supported. See [Testing](testing.md#package-managers-and-private-registries) for the details.

### Build Output Paths

The action does not guess the build directory. It uses the `paths` input, one path per line, relative to `working-directory`, and `dist` by default. Every path must exist after the build, or the step fails and lists the missing ones.

## 🔒 Security Considerations

- The `token` input is read only by the Commit step (mode `commit`) and the Pull request step (mode `pr`). The install and build steps never receive it.
- Mode `check` and mode `build` read no token.
- The action is composite and runs on the runner, not in a container.
- Every action that it uses is pinned by commit SHA.
- See the [threat model](threat-model.md) and the [security policy](../SECURITY.md).

## 🐛 Common Issues and Solutions

### Permission Issues
Mode `commit` needs `contents: write` and `persist-credentials: false` on the checkout, and mode `pr` also needs `pull-requests: write`. Modes `check` and `build` need only `contents: read`. See [Permissions and checkout](../README.md#permissions-and-checkout).

### Build Failures
Check that your build script works locally first.

### No Changes Detected
This is normal if your build output is identical. The action will exit successfully without making a commit.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/miguelcolmenares/npm-auto-build/issues)
- **Discussions**: [GitHub Discussions](https://github.com/miguelcolmenares/npm-auto-build/discussions)
- **Email**: me@miguelcolmenares.com