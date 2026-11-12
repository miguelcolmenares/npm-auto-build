#!/bin/bash

# NPM Auto Build Action - Local Testing Script
# This script allows you to test the action locally using Docker

set -e

echo "🧪 Testing NPM Auto Build Action locally..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Default values
COMMAND=${1:-"build"}
BUILD_DIR=${2:-"dist"}
TEST_PROJECT=${3:-"./test-project"}

# Create a simple test project if it doesn't exist
if [ ! -d "$TEST_PROJECT" ]; then
    echo "📁 Creating test project at $TEST_PROJECT..."
    mkdir -p "$TEST_PROJECT"

    # Run in a subshell so the current directory does not change
    (
        cd "$TEST_PROJECT" || exit 1

        # Create package.json with build script
        cat > package.json << EOF
{
  "name": "npm-auto-build-test",
  "version": "1.0.0",
  "scripts": {
    "build": "mkdir -p $BUILD_DIR && echo '// Built at: '\\$(date) > $BUILD_DIR/main.js && echo 'console.log(\"Hello from build!\");' >> $BUILD_DIR/main.js"
  }
}
EOF

        # Initialize git
        git init
        git config user.name "Test User" 2>/dev/null || true
        git config user.email "test@example.com" 2>/dev/null || true
        git add .
        git commit -m "Initial test project" 2>/dev/null || true
    )
fi

# Build Docker image from the repository root
echo "🐳 Building Docker image..."
docker build -t npm-auto-build-local "$SCRIPT_DIR" > /dev/null

# Run the action
echo "🚀 Running action with:"
echo "   Command: npm run $COMMAND"
echo "   Build dir: $BUILD_DIR"
echo "   Project: $TEST_PROJECT"
echo ""

docker run --rm \
  -v "$(pwd)/$TEST_PROJECT:/github/workspace" \
  -e INPUT_COMMAND="$COMMAND" \
  -e INPUT_DIRECTORY="." \
  -e INPUT_BUILD_DIR="$BUILD_DIR" \
  -e INPUT_COMMIT_MESSAGE="test: automated build" \
  -e INPUT_GITHUB_TOKEN="" \
  -e INPUT_GIT_USER_NAME="Test User" \
  -e INPUT_GIT_USER_EMAIL="test@example.com" \
  npm-auto-build-local

echo ""
echo "✅ Test completed!"
echo "💡 Usage: ./test.sh [command] [build-dir] [project-path]"