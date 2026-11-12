#!/bin/bash

# Run the action locally in Docker, against the test project
echo "🧪 Testing npm-auto-build action locally..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set the inputs the same way GitHub Actions does
export INPUT_COMMAND="build"
export INPUT_DIRECTORY="."
export INPUT_BUILD_DIR="dist"
export INPUT_COMMIT_MESSAGE="test: local build test"
export INPUT_GITHUB_TOKEN="fake-token-for-testing"
export INPUT_GIT_USER_NAME="Local Test User"
export INPUT_GIT_USER_EMAIL="test@local.com"
export INPUT_NODE_VERSION="18"

# Test project directory, inside the repository
TEST_PROJECT="$PROJECT_ROOT/test-project"

echo "📁 Testing with project: $TEST_PROJECT"
echo "🏗️ Build command: npm run $INPUT_COMMAND"
echo "📦 Expected build directory: $INPUT_BUILD_DIR"

# Run the Docker container
docker run --rm \
  -v "$TEST_PROJECT:/github/workspace" \
  -e INPUT_COMMAND \
  -e INPUT_DIRECTORY \
  -e INPUT_BUILD_DIR \
  -e INPUT_COMMIT_MESSAGE \
  -e INPUT_GITHUB_TOKEN \
  -e INPUT_GIT_USER_NAME \
  -e INPUT_GIT_USER_EMAIL \
  -e INPUT_NODE_VERSION \
  npm-auto-build-test

echo "✅ Test completed!"
