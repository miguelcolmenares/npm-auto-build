#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Set default values
WORKSPACE_DIR="/github/workspace"
PROJECT_DIR="$WORKSPACE_DIR/$INPUT_DIRECTORY"
BUILD_COMMAND="$INPUT_COMMAND"
COMMIT_MESSAGE="$INPUT_COMMIT_MESSAGE"
BUILD_DIR="$INPUT_BUILD_DIR"
GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"
GIT_USER_NAME="$INPUT_GIT_USER_NAME"
GIT_USER_EMAIL="$INPUT_GIT_USER_EMAIL"
NODE_VERSION="$INPUT_NODE_VERSION"
BUILD_ONLY="$INPUT_BUILD_ONLY"

log_info "Starting NPM Auto Build Action"
log_info "Project directory: $PROJECT_DIR"
log_info "Build command: npm run $BUILD_COMMAND"
log_info "Build directory: $BUILD_DIR"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "Project directory $PROJECT_DIR does not exist"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    log_error "package.json not found in $PROJECT_DIR"
    exit 1
fi

log_info "Found package.json, proceeding with build"

# Install dependencies
log_info "Installing dependencies..."
if [ -f "package-lock.json" ]; then
    npm ci
elif [ -f "yarn.lock" ]; then
    log_info "Detected yarn.lock, using yarn"
    yarn install --frozen-lockfile
else
    npm install
fi

# Check if build script exists in package.json
if ! npm run | grep -q "^  $BUILD_COMMAND$"; then
    log_error "Build script '$BUILD_COMMAND' not found in package.json"
    log_info "Available scripts:"
    npm run
    exit 1
fi

# Run the build command
log_info "Running build command: npm run $BUILD_COMMAND"
npm run "$BUILD_COMMAND"

# Check if build directory was created
if [ ! -d "$BUILD_DIR" ]; then
    log_warn "Build directory '$BUILD_DIR' not found. Checking for common build directories..."
    
    # Check for common build directories
    for dir in "dist" "build" "lib" "public" "out" ".next"; do
        if [ -d "$dir" ]; then
            BUILD_DIR="$dir"
            log_info "Found build directory: $BUILD_DIR"
            break
        fi
    done
    
    if [ ! -d "$BUILD_DIR" ]; then
        log_error "No build directory found. Please specify the correct build-dir parameter."
        exit 1
    fi
fi

# Check if build-only mode is enabled
if [ "$BUILD_ONLY" = "true" ]; then
    log_info "✅ Build completed successfully in build-only mode!"
    log_info "Build directory '$BUILD_DIR' has been created but not committed."
    log_info "Use this mode for testing builds without modifying the repository."
    exit 0
fi

# Configure Git
log_info "Configuring Git..."
git config --global --add safe.directory "$WORKSPACE_DIR"
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Set up authentication
if [ -n "$GITHUB_TOKEN" ]; then
    git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

# Check if there are changes to commit
log_info "Checking for changes in build directory..."
log_info "Build directory contents:"
ls -la "$BUILD_DIR" || log_warn "Could not list build directory contents"

# Show git status for debugging
log_info "Git status before adding files:"
git status --porcelain

# Check if build directory is in .gitignore
if git check-ignore "$BUILD_DIR" >/dev/null 2>&1; then
    log_info "Build directory '$BUILD_DIR' is in .gitignore - will force add files"
    FORCE_ADD=true
else
    FORCE_ADD=false
fi

# Try to add build files first (with --force if needed)
log_info "Adding build files to Git..."
if [ "$FORCE_ADD" = true ]; then
    git add "$BUILD_DIR" --force
    log_info "Used --force to add ignored files"
else
    git add "$BUILD_DIR"
fi

# Show git status after adding
log_info "Git status after adding build files:"
git status --porcelain

# Check if there are staged changes
if git diff --cached --quiet; then
    log_info "No staged changes found after adding build files."
    
    # Check if files exist but are identical
    if [ -d "$BUILD_DIR" ] && [ "$(find "$BUILD_DIR" -type f | wc -l)" -gt 0 ]; then
        log_info "Build files exist but are identical to repository version."
        log_info "No changes to commit."
    else
        log_warn "Build directory is empty or contains no files."
    fi
    exit 0
fi

log_info "Found staged changes. Proceeding to commit..."

# Commit changes
log_info "Committing changes..."
git commit -m "$COMMIT_MESSAGE"

# Push changes
log_info "Pushing changes to repository..."
if git push; then
    log_info "✅ Build completed and committed successfully!"
    log_info "Build directory '$BUILD_DIR' has been updated and pushed to the repository."
    
    # Show final commit info
    log_info "Latest commit:"
    git log --oneline -1
else
    log_error "Failed to push changes to repository!"
    log_error "Check your GitHub token permissions and branch protection rules."
    exit 1
fi