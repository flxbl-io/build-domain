# Build Domain

[![CI](https://github.com/flxbl-io/build-domain/actions/workflows/ci.yml/badge.svg)](https://github.com/flxbl-io/build-domain/actions/workflows/ci.yml)

A GitHub Action that builds Salesforce packages using `sfp build`, publishes artifacts using `sfp publish`, and generates a release candidate via [SFP Server](https://docs.flxbl.io/sfp-server).

**Built-in Serialization**: Automatically prevents concurrent builds for the same domain using SFP Server's resource queue. Enabled by default.

**Automatic Lock Release**: The action automatically releases the build lock when the job completes (success, failure, or cancellation).

## Features

- **Build Serialization**: Prevents concurrent builds for the same domain (based on `releaseName` in release config)
- Authenticates to DevHub via SFP Server
- Builds packages with diff-check enabled by default (only builds changed packages)
- Publishes artifacts to npm registry via SFP Server
- Generates a release candidate for deployment tracking
- Creates and pushes git tags for published artifacts

## Usage

### Basic Usage

```yaml
- name: Build and Publish
  uses: flxbl-io/build-domain@v1
  with:
    sfp-server-url: ${{ secrets.SFP_SERVER_URL }}
    sfp-server-token: ${{ secrets.SFP_SERVER_TOKEN }}
    release-config: config/release-config.yml
# Serialization enabled by default - only one build per domain at a time
# Lock auto-released when job completes!
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
        uses: flxbl-io/build-domain@v1
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

### Without Serialization

For single-threaded environments or when you want to handle concurrency yourself:

```yaml
- name: Build All Packages
  uses: flxbl-io/build-domain@v1
  with:
    sfp-server-url: ${{ secrets.SFP_SERVER_URL }}
    sfp-server-token: ${{ secrets.SFP_SERVER_TOKEN }}
    release-config: config/release-config.yml
    serialize: 'false'  # Disable serialization
```

### Without Diff-Check (Build All Packages)

```yaml
- name: Build All Packages
  uses: flxbl-io/build-domain@v1
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
| `npm` | Publish to external npm registry | No | `false` |
| `git-tag` | Create git tags for published artifacts | No | `true` |
| `push-git-tag` | Push git tags to remote repository | No | `true` |
| `serialize` | Serialize builds for this domain | No | `true` |
| `serialize-timeout` | Max seconds to wait for lock | No | `900` (15 min) |
| `serialize-lease` | Duration to hold lock | No | `1800` (30 min) |

## Outputs

| Output | Description |
|--------|-------------|
| `has-artifacts` | Whether artifacts were produced (`true`/`false`) |
| `artifact-count` | Number of artifacts produced |
| `artifacts-dir` | Path to artifacts directory (`artifacts`) |

## How It Works

### Serialization

The action uses SFP Server's resource queue to serialize builds:

```
┌─────────────────────────────────────────────────────────────┐
│                  Build A (PR #123)                          │
│  Resource: build-frameworks                                 │
│  Status: LOCKED - building packages...                      │
│  [Auto-release on completion]                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Build B (PR #124)                          │
│  Resource: build-frameworks                                 │
│  Status: WAITING... (position: 2)                           │
│         ↓                                                   │
│  [Build A completes, releases lock]                         │
│         ↓                                                   │
│  Status: LOCKED - building packages...                      │
│  [Auto-release on completion]                               │
└─────────────────────────────────────────────────────────────┘
```

The resource name is derived from the `releaseName` field in your release config file:
- `release-config-frameworks.yaml` with `releaseName: frameworks` → resource: `build-frameworks`
- `release-config-sales.yaml` with `releaseName: sales` → resource: `build-sales`

Different domains can build in parallel; only builds for the same domain are serialized.

### Build Flow

```
+-----------------------------------------------------------+
|                       build-domain                        |
+-----------------------------------------------------------+
|                                                           |
|  1. Serialize (if enabled)                                |
|     sfp server resource enqueue --resource build-{name}   |
|     sfp server resource wait --ticketid {id}              |
|                                                           |
|  2. Authenticate to DevHub                                |
|     sfp org login --server --default-devhub               |
|                                                           |
|  3. Build packages                                        |
|     sfp build -v devhub --diffcheck --releaseconfig ...   |
|                                                           |
|  4. Check for artifacts                                   |
|     +-- No artifacts -> Warning, skip remaining steps     |
|     +-- Artifacts found -> Continue                       |
|                                                           |
|  5. Publish to registry                                   |
|     sfp publish --scope @org --gittag --pushgittag        |
|                                                           |
|  6. Generate release candidate                            |
|     sfp releasecandidate generate -n {release-name}       |
|                                                           |
|  [Post Step - always runs]                                |
|  7. Release lock                                          |
|     sfp server resource dequeue --ticketid {id}           |
|                                                           |
+-----------------------------------------------------------+
```

## Prerequisites

- **SFP Server**: Active SFP Server instance with DevHub configured
- **Runtime**: `sfp` CLI must be available (use `sfops` Docker image)
- **Git History**: Use `fetch-depth: 0` in checkout for diff-check to work

## Related Actions

- [resource-queue](https://github.com/flxbl-io/resource-queue) - Standalone resource serialization
- [auth-devhub](https://github.com/flxbl-io/auth-devhub) - Standalone DevHub authentication
- [lock-environment](https://github.com/flxbl-io/lock-environment) - Lock and authenticate to environments

## License

Copyright 2025 flxbl-io. All rights reserved. See [LICENSE](LICENSE) for details.
