#!/usr/bin/env bash
# Test runner using nektos/act (requires Docker)
# Runs the actual action.yml in a container, simulating GitHub Actions
#
# Prerequisites:
#   - Docker running
#   - act installed: brew install act
#
# Usage:
#   ./test-with-act.sh <project-path> release-config=<path> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-.}"
shift || true

cd "$PROJECT_PATH"
PROJECT_PATH="$(pwd)"

# Check prerequisites
command -v act &>/dev/null || { echo "Error: act not installed. Run: brew install act"; exit 1; }
docker info &>/dev/null || { echo "Error: Docker not running"; exit 1; }

# Defaults
SFP_SERVER_URL="http://host.docker.internal:4392/"
SFP_SERVER_TOKEN="00000000-0000-0000-0000-000000000005"
RELEASE_CONFIG=""
REPOSITORY="$(basename $(dirname $PROJECT_PATH))/$(basename $PROJECT_PATH)"

# Parse arguments
for arg in "$@"; do
  key="${arg%%=*}"
  val="${arg#*=}"
  case "$key" in
    sfp-server-url) SFP_SERVER_URL="$val" ;;
    sfp-server-token) SFP_SERVER_TOKEN="$val" ;;
    release-config) RELEASE_CONFIG="$val" ;;
    repository) REPOSITORY="$val" ;;
  esac
done

[[ -z "$RELEASE_CONFIG" ]] && { echo "Error: release-config required"; exit 1; }

# Setup
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $PROJECT_PATH/.github/actions/build" EXIT

mkdir -p "$PROJECT_PATH/.github/actions"
cp -r "$SCRIPT_DIR" "$PROJECT_PATH/.github/actions/build"

# Create workflow
cat > "$TEMP_DIR/test.yml" << EOF
name: Test
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/flxbl-io/sfops:latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: ./.github/actions/build
        with:
          sfp-server-url: \${{ secrets.SFP_SERVER_URL }}
          sfp-server-token: \${{ secrets.SFP_SERVER_TOKEN }}
          release-config: "$RELEASE_CONFIG"
          repository: "$REPOSITORY"
          git-tag: "false"
          push-git-tag: "false"
EOF

cat > "$TEMP_DIR/.secrets" << EOF
SFP_SERVER_URL=$SFP_SERVER_URL
SFP_SERVER_TOKEN=$SFP_SERVER_TOKEN
EOF

echo "Running with act (Docker)..."
act push -W "$TEMP_DIR/test.yml" --secret-file "$TEMP_DIR/.secrets" -b
