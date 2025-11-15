# NPM Auto Build GitHub Action

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/miguelcolmenares/npm-auto-build)](https://github.com/miguelcolmenares/npm-auto-build/releases)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-NPM%20Auto%20Build-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/npm-auto-build)
[![GitHub](https://img.shields.io/github/license/miguelcolmenares/npm-auto-build)](LICENSE)

🚀 **Automatically build and commit your npm project's build files to your repository**

This GitHub Action runs your npm build script and automatically commits the generated build files to your repository. Perfect for keeping your source code clean while maintaining compiled assets for deployment or distribution.

## ✨ Features

- 🔧 **Configurable build command** - Use any npm script (defaults to `build`)
- 📁 **Smart build directory detection** - Automatically finds common build directories
- 🤖 **Automatic Git handling** - Configures Git and commits changes with proper authentication
- 📦 **Multiple package managers** - Works with npm and yarn
- 🎯 **Zero configuration** - Works out of the box with sensible defaults
- 🔍 **Detailed logging** - Clear feedback about the build process

## 🚀 Quick Start

### Basic Usage (Build + Commit)

```yml
name: Auto Build and Deploy
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    # 🔑 Required permissions for committing build files
    permissions:
      contents: write  # Allows the action to commit and push changes
    
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      # Test build on PRs (no commit)
      - name: Test Build (PR only)
        if: github.event_name == 'pull_request'
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          build-only: true

      # Build and commit on main branch  
      - name: Build and Deploy (Main)
        if: github.event_name == 'push'
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          build-dir: dist
          commit-message: "chore: update build files [skip ci]"
```

### Simple One-Step Build

```yml
- name: Auto Build & Commit
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### For Protected Branches

```yml
- name: Auto Build & Create PR
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    create-pr: true  # Creates PR instead of direct push
```

### Build-Only Usage (Testing/CI)

```yml
name: Test Build
on:
  pull_request:
    branches: [ main ]

jobs:
  test-build:
    runs-on: ubuntu-latest
    
    # 🧪 No special permissions needed for build-only mode
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Test Build
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          build-only: true  # Only build, don't commit
```

### Advanced Usage with Custom Settings

```yml
name: Advanced Auto Build
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    permissions:
      contents: write
    
    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Advanced Auto Build
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build:prod'
          directory: './frontend'
          build-dir: 'dist'
          commit-message: 'chore: update production build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
          git-user-name: 'Build Bot'
          git-user-email: 'bot@mycompany.com'
          node-version: '18'
```

### Protected Branches Setup

#### Option 1: Create Pull Request (Recommended)

```yml
name: Protected Branch Build with PR
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    permissions:
      contents: write
      pull-requests: write
    
    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto Build & Create PR
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          create-pr: true  # Creates PR instead of direct push
```

#### Option 2: Direct Push with PAT

```yml
name: Protected Branch Build with PAT
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    permissions:
      contents: write
    
    steps:
      - name: Checkout with PAT
        uses: actions/checkout@v5
        with:
          token: ${{ secrets.PAT }}  # Personal Access Token for protected branches

      - name: Auto Build
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          github-token: ${{ secrets.PAT }}  # Same PAT for pushing
```

## 📖 Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `command` | NPM script to run | No | `build` |
| `directory` | Directory containing package.json | No | `.` |
| `build-dir` | Directory where build files are generated | No | `dist` |
| `commit-message` | Commit message for build changes | No | `chore: update build files` |
| `github-token` | GitHub token for authentication | **Yes*** | - |
| `git-user-name` | Git user name for commits | No | `github-actions[bot]` |
| `git-user-email` | Git user email for commits | No | `github-actions[bot]@users.noreply.github.com` |
| `node-version` | Node.js version to use | No | `18` |
| `build-only` | Only build without committing changes | No | `false` |
| `create-pr` | Create pull request instead of direct push | No | `false` |

> **\*** Required only when committing changes. Not needed in `build-only` mode.

## 🔐 Authentication & Permissions

### Standard Workflow (Recommended)

- Use `${{ secrets.GITHUB_TOKEN }}` - GitHub's built-in token
- Add `permissions: contents: write` to your job
- Works for most use cases on public repositories
- **Checkout@v5**: Uses Node.js 24 runtime (requires Actions Runner v2.327.1+)

```yml
permissions:
  contents: write  # Required for committing changes
  actions: read    # Required for checkout action (default)
```

### Protected Branches

- Create a Personal Access Token (PAT) with `repo` scope
- Store as repository secret (e.g., `secrets.PAT`)
- Use in both checkout and action steps

### Build-Only Mode

- No token or permissions required
- Perfect for testing builds in CI/PR workflows  
- Set `build-only: true` to skip Git operations
- Only requires `contents: read` (default checkout permission)

## 🎯 Use Cases

### 1. **Frontend Deployment**
Perfect for React, Vue, Angular, or any frontend framework that generates static files for deployment.

### 2. **Library Distribution**
Build and commit transpiled JavaScript for npm package distribution without including source build in your development workflow.

### 3. **Documentation Sites**
Generate and deploy documentation sites (like with VuePress, GitBook, etc.) automatically.

### 4. **Static Site Generation**
Build and commit static sites generated by tools like Gatsby, Next.js, Nuxt.js, etc.

## 🔧 Real-World Examples

### 1. Testing Build in PR (Build-Only Mode)

```yml
name: PR Build Test
on:
  pull_request:
    branches: [ main ]

jobs:
  test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      
      - name: Test Build
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          build-only: true  # Only test, don't commit
          command: 'build:prod'
```

### 2. Deploy to GitHub Pages

```yml
name: Deploy to GitHub Pages
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pages: write
    
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build for GitHub Pages
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build'
          build-dir: 'dist'
          commit-message: '🚀 Deploy to GitHub Pages'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Library Distribution (NPM Package)

```yml
name: Build Library
on:
  push:
    tags: [ 'v*' ]

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build TypeScript Library
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build:lib'
          build-dir: 'lib'
          commit-message: 'chore: update compiled library'
          github-token: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Publish to NPM
        run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### 4. Monorepo Multi-Package Build

```yml
name: Monorepo Build
on:
  push:
    branches: [ main ]

jobs:
  build-packages:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    
    strategy:
      matrix:
        package:
          - { name: 'frontend', dir: './packages/web', build-dir: 'dist' }
          - { name: 'admin', dir: './packages/admin', build-dir: 'build' }
          - { name: 'mobile-web', dir: './packages/mobile', build-dir: 'dist' }
    
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build ${{ matrix.package.name }}
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          directory: ${{ matrix.package.dir }}
          build-dir: ${{ matrix.package.build-dir }}
          commit-message: 'chore: update ${{ matrix.package.name }} build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 5. Protected Branch with Custom Bot

```yml
name: Production Build
on:
  push:
    branches: [ main ]

jobs:
  protected-build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ secrets.BOT_PAT }}  # Custom bot token
      
      - name: Production Build
        uses: miguelcolmenares/npm-auto-build@v2
        with:
          command: 'build:production'
          build-dir: 'dist'
          commit-message: '🏗️ Production build update'
          github-token: ${{ secrets.BOT_PAT }}
          git-user-name: 'Production Bot'
          git-user-email: 'bot@mycompany.com'
```

## 📁 More Examples

Check out the [`examples/`](./examples/) directory for complete workflow files:

- **[`complete-workflow.yml`](./examples/complete-workflow.yml)** - Build-only for PRs, build+commit for main
- **[`monorepo.yml`](./examples/monorepo.yml)** - Multi-package monorepo setup  
- **[`protected-branches.yml`](./examples/protected-branches.yml)** - Working with protected branches

## ⚡ GitHub Actions Compatibility

### Checkout Action v5

This action is fully compatible with **actions/checkout@v5**, the latest version which includes:

- **Node.js 24 Runtime**: Improved performance and security
- **Minimum Runner Version**: Requires Actions Runner v2.327.1 or higher
- **Same API**: All existing configurations work unchanged
- **Enhanced Security**: Updated dependencies and security improvements

```yml
# ✅ Recommended - Latest version
- uses: actions/checkout@v5
  with:
    token: ${{ secrets.GITHUB_TOKEN }}

# ⚠️ Still supported but older
- uses: actions/checkout@v4
```

> **Note**: If you encounter issues with checkout@v5, ensure your GitHub-hosted runners are up to date. Self-hosted runners need to be updated to v2.327.1 or higher.

## 🛠️ How It Works

1. **Checkout** - The action starts in your repository workspace
2. **Dependency Installation** - Automatically detects and installs npm/yarn dependencies
3. **Build Execution** - Runs your specified npm build command
4. **Build Detection** - Finds the build directory (auto-detects common locations)
5. **Git Configuration** - Sets up Git with provided credentials
6. **Change Detection** - Checks if build files have changed
7. **Commit & Push** - Commits and pushes changes if any are found

## 🤔 Why Use This Action?

### Problems It Solves:
- ❌ **Large repositories** due to committed build files
- ❌ **Merge conflicts** in build files
- ❌ **Inconsistent builds** across different environments
- ❌ **Forgotten builds** when making releases

### Benefits:
- ✅ **Clean repository** - Keep source and build separate
- ✅ **Automated builds** - Never forget to build before release
- ✅ **Consistent environment** - Builds always happen in CI
- ✅ **Reduced conflicts** - No more build file merge conflicts

## 📝 Requirements

- Repository with `package.json`
- npm build script defined in `package.json`
- GitHub token with write permissions

## 🐛 Troubleshooting


### Build Directory in .gitignore

**This is automatically handled!**

If your build directory (e.g., `dist/`, `build/`) is in `.gitignore`, the action will automatically detect this and use `git add --force` to commit the files.

**Common scenario:**
```gitignore
# .gitignore
node_modules/
dist/          # Build directory ignored locally
coverage/
```

The action will:
1. Detect that `dist/` is in `.gitignore`
2. Automatically use `--force` flag when adding files
3. Commit build files successfully

**Why this works:** Developers often ignore build directories locally to keep their working tree clean, but CI/CD should commit official builds. This action handles both scenarios seamlessly.

**No configuration needed** - the action automatically detects multiple `.gitignore` patterns:
- `dist`
- `dist/`
- `dist/*`

### Build Directory Not Found
If you get "No build directory found", specify the correct `build-dir`:
```yml
with:
  build-dir: 'public'  # or 'out', 'lib', etc.
```

### Permission Denied
Make sure your token has the `contents:write` permission:
```yml
permissions:
  contents: write
```

### No Changes to Commit
This is normal if your build output hasn't changed. The action will exit successfully without making a commit.

## � Testing Locally

You can test this action locally using Docker:

```bash
# Quick test with defaults
./test.sh

# Test with custom parameters
./test.sh "build:prod" "build" "./my-project"
```

For more testing options, see [docs/testing.md](docs/testing.md).

## 🔄 Automatic Updates with Dependabot

To keep your GitHub Actions automatically updated, add this to your repository:

```yml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
```

**What Dependabot will detect:**
- ✅ **This action**: `miguelcolmenares/npm-auto-build@v2.0.x` → `@v2.x.x`
- ✅ **Checkout updates**: `actions/checkout@v4` → `@v5` 
- ✅ **Other action dependencies**

### ⚠️ Important: Migration to v2.0.0

**v1.x versions contained critical Docker issues and are non-functional.**

#### For New Users
- Use `@v2` (auto-updating) or `@v2.0.0` (specific version)
- Use `actions/checkout@v5` (recommended)

#### Migrating from v1.x
1. **Replace version**: `@v1` → `@v2` (or `@v2.0.0`)
2. **Update checkout**: `@v4` → `@v5` (recommended)  
3. **Test thoroughly**: v2.0.0 is a complete rewrite

#### Self-hosted Runners
If using checkout@v5, ensure your Actions Runner is v2.327.1 or higher.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Miguel Colmenares**
- GitHub: [@miguelcolmenares](https://github.com/miguelcolmenares)
- Email: me@miguelcolmenares.com
