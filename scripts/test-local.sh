#!/bin/bash

# Script para probar el action localmente
echo "🧪 Testing npm-auto-build action locally..."

# Configurar variables de entorno como lo haría GitHub Actions
export INPUT_COMMAND="build"
export INPUT_DIRECTORY="."
export INPUT_BUILD_DIR="dist"
export INPUT_COMMIT_MESSAGE="test: local build test"
export INPUT_GITHUB_TOKEN="fake-token-for-testing"
export INPUT_GIT_USER_NAME="Local Test User"
export INPUT_GIT_USER_EMAIL="test@local.com"
export INPUT_NODE_VERSION="18"

# Directorio del proyecto de prueba
TEST_PROJECT="/Users/miguel/Projects/npm-auto-build/test-project"

echo "📁 Testing with project: $TEST_PROJECT"
echo "🏗️ Build command: npm run $INPUT_COMMAND"
echo "📦 Expected build directory: $INPUT_BUILD_DIR"

# Ejecutar el container Docker
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