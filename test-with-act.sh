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
docker info &>/dev/null || { echo "Error: Docker not running"; exit 1; }

# Defaults
SFP_SERVER_URL=""
SFP_SERVER_TOKEN="00000000-0000-0000-0000-000000000005"
SFP_WORKSPACE=""
RELEASE_CONFIG=""
REPOSITORY="$(basename $(dirname $PROJECT_PATH))/$(basename $PROJECT_PATH)"

# Parse arguments
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

# Auto-detect sfp workspace if not provided
if [[ -z "$SFP_WORKSPACE" ]]; then
  # Look for common sfp-pro locations
  for candidate in \
    "$HOME/projects/flxbl-io/sfp-pro/release-V3" \
    "$HOME/projects/flxbl-io/sfp-pro/main" \
    "$HOME/projects/flxbl-io/sfp-pro"; do
    if [[ -d "$candidate" ]] && docker ps --filter "name=$(basename $candidate | tr '[:upper:]' '[:lower:]')-server-dev" --format '{{.Names}}' | grep -q .; then
      SFP_WORKSPACE="$candidate"
      break
    fi
  done
fi

if [[ -z "$SFP_WORKSPACE" ]]; then
  echo "Error: Could not auto-detect sfp-pro workspace. Specify with sfp-workspace=<path>"
  exit 1
fi

# Get workspace name (lowercased directory name)
WORKSPACE_NAME=$(basename "$SFP_WORKSPACE" | tr '[:upper:]' '[:lower:]')
echo "Using sfp workspace: $SFP_WORKSPACE ($WORKSPACE_NAME)"

# Get the cli-lite-dev image from the compose stack
CLI_IMAGE="${WORKSPACE_NAME}-cli-lite-dev"
if ! docker images --format '{{.Repository}}' | grep -q "^${CLI_IMAGE}$"; then
  echo "Error: Docker image '$CLI_IMAGE' not found. Is the compose stack running?"
  echo "Available images: $(docker images --format '{{.Repository}}' | grep cli-lite || echo 'none')"
  exit 1
fi
echo "Using Docker image: $CLI_IMAGE"

# Auto-detect SFP Server URL if not provided
if [[ -z "$SFP_SERVER_URL" ]]; then
  SERVER_PORT=$(docker ps --filter "name=${WORKSPACE_NAME}-server-dev" --format '{{.Ports}}' | grep -oE '0\.0\.0\.0:([0-9]+)->3029' | grep -oE '[0-9]+' | head -1)
  if [[ -z "$SERVER_PORT" ]]; then
    echo "Error: Could not detect SFP Server port. Is the compose stack running?"
    exit 1
  fi
  SFP_SERVER_URL="http://host.docker.internal:${SERVER_PORT}/"
  echo "Auto-detected SFP Server URL: $SFP_SERVER_URL"
fi

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
