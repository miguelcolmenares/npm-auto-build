# Example Usage of NPM Auto Build Action

This folder contains example workflows for different use cases.

## React App Example

```yml
name: Build and Deploy React App
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
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto Build React App
        uses: miguelcolmenares/npm-auto-build@v1
        with:
          command: 'build'
          build-dir: 'build'
          commit-message: 'chore: update React production build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## TypeScript Library Example

```yml
name: Build TypeScript Library
on:
  push:
    branches: [ main ]
  release:
    types: [ published ]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Library
        uses: miguelcolmenares/npm-auto-build@v1
        with:
          command: 'build'
          build-dir: 'lib'
          commit-message: 'chore: compile TypeScript to JavaScript'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Monorepo Example

```yml
name: Build Multiple Packages
on:
  push:
    branches: [ main ]

jobs:
  build-frontend:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Frontend Package
        uses: miguelcolmenares/npm-auto-build@v1
        with:
          directory: './packages/frontend'
          command: 'build:prod'
          build-dir: 'dist'
          commit-message: 'chore: update frontend build'
          github-token: ${{ secrets.GITHUB_TOKEN }}

  build-admin:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    needs: build-frontend
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Admin Package
        uses: miguelcolmenares/npm-auto-build@v1
        with:
          directory: './packages/admin'
          command: 'build:prod'
          build-dir: 'dist'
          commit-message: 'chore: update admin build'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```