# Build Action

[![CI](https://github.com/flxbl-io/build/actions/workflows/ci.yml/badge.svg)](https://github.com/flxbl-io/build/actions/workflows/ci.yml)

A GitHub Action that builds Salesforce packages using `sfp build`, publishes artifacts using `sfp publish`, and generates a release candidate via [SFP Server](https://docs.flxbl.io/sfp-server).

## Features

- Authenticates to DevHub via SFP Server
- Builds packages with diff-check enabled by default (only builds changed packages)
- Publishes artifacts to npm registry via SFP Server
- Generates a release candidate for deployment tracking
- Creates and pushes git tags for published artifacts

## Usage

### Basic Usage

```yaml
- name: Build and Publish
  uses: flxbl-io/build@v1
  with:
    sfp-server-url: ${{ secrets.SFP_SERVER_URL }}
    sfp-server-token: ${{ secrets.SFP_SERVER_TOKEN }}
    release-config: config/release-config.yml
```

### Full Example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/flxbl-io/sfops:latest

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for diff-check

      - name: Build and Publish
        id: build
        uses: flxbl-io/build@v1
        with:
          sfp-server-url: ${{ secrets.SFP_SERVER_URL }}
          sfp-server-token: ${{ secrets.SFP_SERVER_TOKEN }}
          release-config: config/release-config.yml
          branch: ${{ github.ref_name }}
          release-name: release-${{ github.run_id }}

      - name: Check build result
        run: |
          echo "Artifacts built: ${{ steps.build.outputs.artifact-count }}"
          echo "Has artifacts: ${{ steps.build.outputs.has-artifacts }}"
```

### Without Diff-Check (Build All Packages)

```yaml
- name: Build All Packages
  uses: flxbl-io/build@v1
  with:
    sfp-server-url: ${{ secrets.SFP_SERVER_URL }}
    sfp-server-token: ${{ secrets.SFP_SERVER_TOKEN }}
    release-config: config/release-config.yml
    diff-check: 'false'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `sfp-server-url` | URL to SFP Server (e.g., `https://your-org.flxbl.io`) | **Yes** | - |
| `sfp-server-token` | SFP Server authentication token | **Yes** | - |
| `release-config` | Path to release config file | **Yes** | - |
| `repository` | Repository name (`owner/repo` format) | No | Current repository |
| `branch` | Branch name for build identification | No | Current branch |
| `build-number` | Build number for source packages | No | GitHub run ID |
| `release-name` | Name for the release candidate | No | `{branch}-{build-number}` |
| `diff-check` | Only build packages that have changed | No | `true` |
| `npm-scope` | NPM scope for publishing (without @) | No | Repository owner |
| `git-tag` | Create git tags for published artifacts | No | `true` |
| `push-git-tag` | Push git tags to remote repository | No | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `has-artifacts` | Whether artifacts were produced (`true`/`false`) |
| `artifact-count` | Number of artifacts produced |
| `artifacts-dir` | Path to artifacts directory (`artifacts`) |

## How It Works

```
+-----------------------------------------------------------+
|                         build                             |
+-----------------------------------------------------------+
|                                                           |
|  1. Authenticate to DevHub                                |
|     sfp org login --server --default-devhub               |
|                                                           |
|  2. Build packages                                        |
|     sfp build -v devhub --diffcheck --releaseconfig ...   |
|                                                           |
|  3. Check for artifacts                                   |
|     +-- No artifacts -> Warning, skip remaining steps     |
|     +-- Artifacts found -> Continue                       |
|                                                           |
|  4. Publish to registry                                   |
|     sfp publish --npm --scope @org --gittag --pushgittag  |
|                                                           |
|  5. Generate release candidate                            |
|     sfp releasecandidate generate -n {release-name}       |
|                                                           |
+-----------------------------------------------------------+
```

## Prerequisites

- **SFP Server**: Active SFP Server instance with DevHub configured
- **Runtime**: `sfp` CLI must be available (use `sfops` Docker image)
- **Git History**: Use `fetch-depth: 0` in checkout for diff-check to work

## Related Actions

- [auth-devhub](https://github.com/flxbl-io/auth-devhub) - Standalone DevHub authentication
- [auth-environment-with-lock](https://github.com/flxbl-io/auth-environment-with-lock) - Lock and authenticate to environments

## License

Copyright 2025 flxbl-io. All rights reserved. See [LICENSE](LICENSE) for details.
