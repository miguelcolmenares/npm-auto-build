# NPM Auto Build - Workflow Examples

This directory contains real-world examples of how to use the NPM Auto Build GitHub Action in different scenarios.

## 📁 Available Examples

### [`complete-workflow.yml`](./complete-workflow.yml)
**Complete CI/CD Setup** - Shows how to use both build-only mode for PR testing and build+commit for main branch deployments.

- ✅ **PR Testing**: Uses `build-only: true` to validate builds without committing
- ✅ **Main Branch**: Builds and commits to repository when changes are merged
- ✅ **No Permissions**: PR builds don't need special permissions
- ✅ **Smart Conditions**: Uses GitHub context to determine which mode to use

### [`monorepo.yml`](./monorepo.yml)
**Monorepo Multi-Package Build** - Perfect for workspaces with multiple npm packages that need individual builds.

- 🏗️ **Matrix Strategy**: Builds multiple packages in parallel
- 📁 **Custom Directories**: Each package has its own directory and build settings
- 🎯 **Targeted Commits**: Commit messages indicate which package was updated
- ⚡ **Efficient**: Only builds what's needed

### [`protected-branches.yml`](./protected-branches.yml)
**Protected Branches Setup** - Shows two approaches for working with branch protection rules.

- 🔄 **Pull Request Mode**: Uses `create-pr: true` to create PRs instead of direct push (Recommended)
- 🔒 **Personal Access Token**: Alternative approach using PAT for direct push to protected branches
- 🤖 **Custom Bot Identity**: Sets up branded bot user for commits
- 🚀 **Auto Releases**: Creates releases after successful builds
- 🎯 **Production Ready**: Designed for production environments

## 🚀 How to Use These Examples
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto Build React App
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build'
          build-dir: 'build'
          commit-message: 'chore: update React production build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## TypeScript Library Example

```yml
name: Build TypeScript Library
on:
  push:
    branches: [ main ]
  release:
    types: [ published ]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Library
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build'
          build-dir: 'lib'
          commit-message: 'chore: compile TypeScript to JavaScript'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Monorepo Example

```yml
name: Build Multiple Packages
on:
  push:
    branches: [ main ]

jobs:
  build-frontend:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Frontend Package
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          directory: './packages/frontend'
          command: 'build:prod'
          build-dir: 'dist'
          commit-message: 'chore: update frontend build'
          github-token: ${{ secrets.GITHUB_TOKEN }}

  build-admin:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    needs: build-frontend
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Admin Package
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          directory: './packages/admin'
          command: 'build:prod'
          build-dir: 'dist'
          commit-message: 'chore: update admin build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```