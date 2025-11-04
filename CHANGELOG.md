# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-11-04

### Added
- **Protected branch support**: New `create-pr` parameter for handling protected branches
- **Automatic PR creation**: Creates pull requests when direct push fails due to branch protection
- **GitHub CLI integration**: Installs and configures GitHub CLI for seamless PR creation
- **Enhanced error handling**: Detailed error messages with solutions for protected branch issues

### Features
- **New Input**: `create-pr: true` - Creates PR instead of direct push
- **Smart detection**: Automatically detects protected branch push failures
- **Unique branch naming**: Creates timestamped branches for each build
- **Comprehensive logging**: Shows PR creation process and branch information

## [2.0.2] - 2025-11-04

### Fixed
- **Git configuration error**: Fixed "Author identity unknown" error when git user inputs are not provided
- **Input validation**: Added proper validation for git user name and email
- **Default values**: Added fallback default values for all input parameters
- **Debug logging**: Enhanced logging to show git configuration values for troubleshooting

## [2.0.1] - 2025-11-04

### Fixed
- **Critical .gitignore handling**: Build directories in .gitignore (like `dist/`) are now properly committed using `--force` flag
- **Enhanced logging**: Added detailed git status logging to help diagnose commit issues
- **Improved detection**: Better detection of ignored directories and files

### Technical Details
This fixes a critical issue where build files weren't committed if the build directory was in `.gitignore`. This is common practice where developers ignore `dist/` locally but want the action to commit official builds.

## [2.0.0] - 2025-11-04

> **Note**: This is the first fully functional release. Previous v1.x versions contained a critical Docker configuration issue that prevented execution.

### Added

- **🚀 NPM Auto Build GitHub Action**: Complete functional GitHub Action for automating npm build and commit workflows
- **🔧 Build-only mode**: New `build-only` input parameter for testing builds without committing changes
- **🐳 Docker-based execution**: Containerized environment with Node.js 20, Git, and Bash
- **📁 Flexible build detection**: Auto-detects build directories (dist/, build/, public/, out/, lib/)
- **📦 Package manager support**: Automatic detection and support for both npm and yarn
- **📚 Comprehensive examples**: Real-world usage patterns for different scenarios
  - Complete CI/CD workflow with PR testing and main branch deployment
  - Monorepo setup with matrix strategy for multiple packages
  - Protected branches configuration with Personal Access Token
- **🧪 Local testing scripts**: Enhanced development workflow with Docker-based test scripts
- **🏪 GitHub Marketplace compliance**: Full compliance with marketplace requirements
- **📖 Complete documentation**: Detailed README with troubleshooting and permission guides

### Core Features

- **Input parameters**:
  - `command`: NPM script to build your package (default: "build")
  - `directory`: Directory containing package.json (default: ".")
  - `commit-message`: Custom commit message (default: "chore: update build files")
  - `build-dir`: Build output directory (default: "dist", auto-detected)
  - `github-token`: GitHub token for authentication (required)
  - `git-user-name`: Git user name (default: "github-actions[bot]")
  - `git-user-email`: Git user email (default: "github-actions[bot]@users.noreply.github.com")
  - `node-version`: Node.js version (default: "18")
  - `build-only`: Test mode without committing (default: "false")

### Technical Implementation

- **Base image**: node:20-alpine with bash, git, and npm/yarn
- **Shell script**: entrypoint.sh with comprehensive error handling and logging
- **Action metadata**: Properly formatted action.yml with all input definitions
- **Docker support**: Multi-architecture container support
- **Permission handling**: Documented requirements for `contents: write`

### Breaking Changes

- **Version 2.0.0**: Complete rewrite from v1.x (which were non-functional)
- **Node.js 20**: Updated from Node.js 18 for better performance and security
- **Alpine Linux**: Switched to Alpine base image with proper bash support
- **Enhanced validation**: Stricter input validation and error reporting

## Usage

```yaml
- name: Build and Deploy
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    build-dir: dist
    commit-message: "chore: update build files [skip ci]"
```

For complete usage examples, see the [examples/](examples/) directory.