# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2025-11-03

### Fixed
- **Action YAML formatting**: Corrected indentation for `build-only` parameter in action.yml
- **GitHub Marketplace compliance**: Ensured proper YAML structure for marketplace validation

## [1.1.0] - 2024-11-02

### Added
- **Build-only mode**: New `build-only` input parameter for testing builds without committing changes
- **Enhanced documentation**: Comprehensive permission requirements and troubleshooting guides
- **Real-world examples**: Complete workflow examples for different use cases
  - Complete CI/CD workflow with PR testing and main branch deployment
  - Monorepo setup with matrix strategy for multiple packages
  - Protected branches configuration with Personal Access Token
- **Local testing scripts**: Enhanced test-build-only.sh for development workflow
- **GitHub Marketplace compliance**: Full compliance with marketplace requirements

### Changed
- **Updated to checkout@v5**: All examples and documentation now use actions/checkout@v5
  - Improved performance with Node.js 24 runtime
  - Enhanced security with updated dependencies
  - Requires Actions Runner v2.327.1+ for self-hosted runners
- **Fixed action.yml indentation**: Corrected build-only input placement under inputs section
- **Enhanced README.md**: Added compatibility section and comprehensive usage examples
- **Improved entrypoint.sh**: Added build-only logic with early exit functionality

### Removed
- **CI badge**: Removed non-functional workflow status badge
- **Workflow files**: Removed .github/workflows/ directory for GitHub Marketplace compliance
- **Temporary documentation files**: Consolidated information into CHANGELOG.md

### Technical Details
- **Permissions**: Documented `contents: write` requirement for commit operations
- **Authentication**: Added guidance for GITHUB_TOKEN vs Personal Access Token usage
- **Compatibility**: Node.js 24 runtime support with Actions Runner requirements
- **Testing**: Local Docker-based testing without requiring GitHub workflows

### Migration Guide
For existing users updating from v1.0.x to v1.1.0:

1. **Update checkout version** (recommended):
   ```yml
   - uses: actions/checkout@v4  # Old
   + uses: actions/checkout@v5  # New
   ```

2. **Add build-only for PR testing** (optional):
   ```yml
   - name: Test Build (PR only)
     uses: miguelcolmenares/npm-auto-build@v1.1.0
     with:
       build-only: true
   ```

3. **Verify permissions** for commit operations:
   ```yml
   permissions:
     contents: write
   ```

### Dependabot and Automated Updates

#### For Dependabot Users
Dependabot will automatically detect and suggest updates for both:
- **This action**: `miguelcolmenares/npm-auto-build@v1.0.x` → `@v1.1.0`
- **Checkout action**: `actions/checkout@v4` → `@v5` (if configured)

To ensure Dependabot monitors GitHub Actions:
```yml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

#### Action Deprecation Strategy
When we release v2.0.0, we will:
1. **Add deprecation notice** to v1.x README
2. **Create GitHub Advisory** for security/compatibility updates
3. **Add workflow warnings** when checkout@v4 is detected
4. **Provide automated PR template** for easy migration

#### Compatibility Detection
Future versions will detect outdated checkout versions and warn users:
```yml
# Future feature - automatic compatibility checking
- name: Build and Deploy
  uses: miguelcolmenares/npm-auto-build@v2
  # Will warn: "checkout@v4 detected, recommend upgrading to @v5"
```

## [1.0.0] - 2024-11-01

### Added
- Initial release of NPM Auto Build GitHub Action
- **Core functionality**: Automatic build and commit of npm project build files
- **Configurable build command**: Support for any npm script (defaults to 'build')
- **Smart build directory detection**: Automatically finds common build directories (dist, build, public, out)
- **Multiple package managers**: Works with both npm and yarn
- **Docker-based execution**: Containerized action for consistent environment
- **Git automation**: Automatic Git configuration and commit handling
- **Zero configuration**: Works out of the box with sensible defaults
- **Detailed logging**: Clear feedback about the build process

### Features
- **Input parameters**:
  - `build-command`: Custom npm script to run (default: "build")
  - `commit-message`: Custom commit message for build files
  - `github-token`: GitHub token for authentication (default: GITHUB_TOKEN)
- **Automatic detection**:
  - Package manager (npm/yarn)
  - Build output directory
  - Git configuration setup
- **Docker support**: Node.js 18 based container with npm and yarn pre-installed
- **Example workflows**: Basic usage examples in README.md

### Technical Implementation
- **Base image**: node:18-slim for lightweight container
- **Shell script**: entrypoint.sh for core build and commit logic
- **Action metadata**: action.yml with comprehensive input definitions
- **Documentation**: Complete setup and usage guide

For more detailed information about specific changes, see the commit history and pull request discussions.