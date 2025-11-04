# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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