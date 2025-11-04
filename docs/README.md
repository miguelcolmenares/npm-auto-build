# 📚 NPM Auto Build Action - Documentation

Welcome to the comprehensive documentation for NPM Auto Build Action.

## 📖 Documentation Index

- **[Testing Guide](testing.md)** - Complete guide for local testing
- **[Examples](../examples/README.md)** - Usage examples for different frameworks
- **[Main README](../README.md)** - Getting started and basic usage

## 🎯 Quick Links

### For Users
- [Getting Started](../README.md#-quick-start)
- [Configuration Options](../README.md#-inputs)
- [Use Cases](../README.md#-use-cases)
- [Troubleshooting](../README.md#-troubleshooting)

### For Contributors
- [Local Testing](testing.md)
- [Development Scripts](../scripts/)
- [Contributing Guidelines](../README.md#-contributing)

## 🔧 Advanced Configuration

### Custom Build Environments

The action supports various Node.js environments and package managers:

```yml
- name: Build with specific Node version
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    node-version: '20'
    command: 'build:prod'
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Monorepo Support

For projects with multiple packages:

```yml
- name: Build Frontend
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    directory: './packages/frontend'
    build-dir: 'dist'
    commit-message: 'chore: update frontend build'
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### CI/CD Integration

Best practices for integrating with different CI/CD systems:

```yml
# Standard workflow - Direct push
permissions:
  contents: write

# Protected branches - Pull request creation
permissions:
  contents: write
  pull-requests: write
```

### Protected Branches

For repositories with branch protection rules, use the pull request approach:

```yml
- name: Build and Create PR
  uses: miguelcolmenares/npm-auto-build@v2
  with:
    create-pr: true  # Creates PR instead of direct push
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 🛠️ Technical Details

### How It Works

1. **Environment Setup**: Installs Node.js and dependencies
2. **Build Execution**: Runs the specified npm script
3. **Change Detection**: Compares build output with git history
4. **Git Operations**: Commits and pushes changes if detected

### Supported Package Managers

- **npm**: Uses `npm ci` for faster installs with lockfile
- **yarn**: Automatically detected via `yarn.lock`
- **pnpm**: Future support planned

### Build Directory Detection

The action automatically detects common build directories:
- `dist/` (default)
- `build/`
- `lib/`
- `public/`
- `out/`
- `.next/`

## 🔒 Security Considerations

- Uses GitHub's built-in `GITHUB_TOKEN` for authentication
- No sensitive data is logged or exposed
- Runs in isolated Docker container
- Follows GitHub Actions security best practices
- **Pull Request Mode**: `create-pr: true` works with standard GitHub permissions, no PAT required
- **Protected Branches**: Automatically handles branch protection by creating reviewable PRs

## 🐛 Common Issues and Solutions

### Permission Issues
Ensure your workflow has `contents: write` permission.

### Build Failures
Check that your build script works locally first.

### No Changes Detected
This is normal if your build output is identical. The action will exit successfully without making a commit.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/miguelcolmenares/npm-auto-build/issues)
- **Discussions**: [GitHub Discussions](https://github.com/miguelcolmenares/npm-auto-build/discussions)
- **Email**: me@miguelcolmenares.com