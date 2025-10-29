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
if git diff --quiet HEAD -- "$BUILD_DIR" 2>/dev/null; then
    log_info "No changes detected in build directory. Nothing to commit."
    exit 0
fi

# Add build files to git
log_info "Adding build files to Git..."
git add "$BUILD_DIR"

# Check if there are staged changes
if git diff --cached --quiet; then
    log_info "No staged changes found. Nothing to commit."
    exit 0
fi

# Commit changes
log_info "Committing changes..."
git commit -m "$COMMIT_MESSAGE"

# Push changes
log_info "Pushing changes to repository..."
git push

log_info "✅ Build completed and committed successfully!"
log_info "Build directory '$BUILD_DIR' has been updated and pushed to the repository."