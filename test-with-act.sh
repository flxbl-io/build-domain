#!/usr/bin/env bash
# Test runner using nektos/act (requires Docker)
# Runs the actual action.yml in a container, simulating GitHub Actions
#
# Prerequisites:
#   - Docker running
#   - act installed: brew install act
#   - Local sfp-pro compose stack running (auto-detected per workspace)
#
# Usage:
#   ./test-with-act.sh <project-path> release-config=<path> [options]
#
# Options:
#   sfp-server-url=<url>      Override SFP Server URL (default: auto-detect from compose stack)
#   sfp-server-token=<token>  Override SFP Server token (default: dev token)
#   sfp-workspace=<path>      Path to sfp-pro workspace (default: auto-detect)
#   release-config=<path>     Path to release config (required)
#   repository=<owner/repo>   Repository identifier (default: derived from project path)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-.}"
shift || true

cd "$PROJECT_PATH"
PROJECT_PATH="$(pwd)"

# Check prerequisites
command -v act &>/dev/null || { echo "Error: act not installed. Run: brew install act"; exit 1; }

# Source shared detection script first (loads .env and auto-detects stack)
FLXBL_ACTIONS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$FLXBL_ACTIONS_ROOT/scripts/detect-sfp-stack.sh"

# Defaults (after sourcing, so .env values are available)
RELEASE_CONFIG=""
REPOSITORY="$(basename $(dirname $PROJECT_PATH))/$(basename $PROJECT_PATH)"

# Parse arguments (override .env / auto-detected values)
for arg in "$@"; do
  key="${arg%%=*}"
  val="${arg#*=}"
  case "$key" in
    sfp-server-url) SFP_SERVER_URL="$val" ;;
    sfp-server-token) SFP_SERVER_TOKEN="$val" ;;
    sfp-workspace) SFP_WORKSPACE="$val" ;;
    release-config) RELEASE_CONFIG="$val" ;;
    repository) REPOSITORY="$val" ;;
  esac
done

[[ -z "$RELEASE_CONFIG" ]] && { echo "Error: release-config required"; exit 1; }

# Run detection (uses values from .env or args if set)
detect_sfp_stack || exit 1

# Setup
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $PROJECT_PATH/.github/actions/build" EXIT

mkdir -p "$PROJECT_PATH/.github/actions"
cp -r "$SCRIPT_DIR" "$PROJECT_PATH/.github/actions/build"

# Create workflow using local cli-lite-dev image
cat > "$TEMP_DIR/test.yml" << EOF
name: Test
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    container: $CLI_IMAGE
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

echo ""
echo "Running with act (Docker)..."
echo "  Image: $CLI_IMAGE"
echo "  Server: $SFP_SERVER_URL"
echo ""
act push -W "$TEMP_DIR/test.yml" --secret-file "$TEMP_DIR/.secrets" -b
