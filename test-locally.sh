#!/usr/bin/env bash
# Local Action Test Runner
# Runs the build action steps directly on your machine using local sfp CLI
# No Docker required - uses your locally installed sfp
#
# Usage:
#   ./test-locally.sh <project-path> release-config=<path> [options]
#
# Example:
#   ./test-locally.sh /path/to/project release-config=config/release.yaml
#   ./test-locally.sh . release-config=config/release.yaml diff-check=false

set -e

PROJECT_PATH="${1:-.}"
shift || true

cd "$PROJECT_PATH"

# Defaults
SFP_SERVER_URL="http://localhost:4392/"
SFP_SERVER_TOKEN="00000000-0000-0000-0000-000000000005"
RELEASE_CONFIG=""
REPOSITORY="${GITHUB_REPOSITORY:-$(basename $(dirname $(pwd)))/$(basename $(pwd))}"
BRANCH="${GITHUB_REF_NAME:-main}"
BUILD_NUMBER="${GITHUB_RUN_ID:-$(date +%s)}"
RELEASE_NAME=""
DIFF_CHECK="true"
NPM_SCOPE="$(echo $REPOSITORY | cut -d'/' -f1)"
GIT_TAG="false"
PUSH_GIT_TAG="false"

# Parse arguments
for arg in "$@"; do
  key="${arg%%=*}"
  val="${arg#*=}"
  case "$key" in
    sfp-server-url) SFP_SERVER_URL="$val" ;;
    sfp-server-token) SFP_SERVER_TOKEN="$val" ;;
    release-config) RELEASE_CONFIG="$val" ;;
    repository) REPOSITORY="$val" ;;
    branch) BRANCH="$val" ;;
    build-number) BUILD_NUMBER="$val" ;;
    release-name) RELEASE_NAME="$val" ;;
    diff-check) DIFF_CHECK="$val" ;;
    npm-scope) NPM_SCOPE="$val" ;;
    git-tag) GIT_TAG="$val" ;;
    push-git-tag) PUSH_GIT_TAG="$val" ;;
  esac
done

# Validate
if [[ -z "$RELEASE_CONFIG" ]]; then
  echo "Error: release-config is required"
  echo "Usage: ./test-locally.sh <project-path> release-config=path/to/config.yaml"
  exit 1
fi

if [[ ! -f "$RELEASE_CONFIG" ]]; then
  echo "Error: Release config not found: $RELEASE_CONFIG"
  exit 1
fi

export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/github_output_$$}"
> "$GITHUB_OUTPUT"

echo "------------------------------------------------------------------------------------------"
echo "flxbl-actions/build -- Local Test Runner"
echo "------------------------------------------------------------------------------------------"
echo "Project       : $(pwd)"
echo "Repository    : $REPOSITORY"
echo "Branch        : $BRANCH"
echo "Build Number  : $BUILD_NUMBER"
echo "Release Config: $RELEASE_CONFIG"
echo "Diff Check    : $DIFF_CHECK"
echo "SFP Server    : $SFP_SERVER_URL"
echo "------------------------------------------------------------------------------------------"
echo ""

# Step 1: Check git depth
echo ">>> Step 1: Check git depth"
if git rev-parse --is-shallow-repository 2>/dev/null | grep -q true; then
  echo "Warning: Shallow clone detected"
  [[ "$DIFF_CHECK" == "true" ]] && git fetch --unshallow --tags 2>/dev/null || true
fi
git fetch --tags 2>/dev/null || true

# Step 2: Authenticate to DevHub
echo ""
echo ">>> Step 2: Authenticate to DevHub"
sfp org login --server --default-devhub --alias devhub \
  --sfp-server-url "$SFP_SERVER_URL" \
  -t "$SFP_SERVER_TOKEN"

# Step 3: Build
echo ""
echo ">>> Step 3: Build packages"
BUILD_CMD="sfp build -v devhub --branch \"$BRANCH\" --buildnumber \"$BUILD_NUMBER\" --artifactdir artifacts --sfp-server-url \"$SFP_SERVER_URL\" -t \"$SFP_SERVER_TOKEN\" --repository \"$REPOSITORY\" --releaseconfig \"$RELEASE_CONFIG\""
[[ "$DIFF_CHECK" == "true" ]] && BUILD_CMD="$BUILD_CMD --diffcheck"
eval $BUILD_CMD

# Step 4: Check artifacts
echo ""
echo ">>> Step 4: Check for artifacts"
ARTIFACT_COUNT=$(find artifacts -name "*.zip" 2>/dev/null | wc -l | tr -d ' ')
echo "artifact-count=$ARTIFACT_COUNT" >> "$GITHUB_OUTPUT"

if [[ "$ARTIFACT_COUNT" -eq 0 ]]; then
  echo "Warning: No artifacts produced"
  echo "has-artifacts=false" >> "$GITHUB_OUTPUT"
  HAS_ARTIFACTS="false"
else
  echo "Found $ARTIFACT_COUNT artifact(s)"
  echo "has-artifacts=true" >> "$GITHUB_OUTPUT"
  HAS_ARTIFACTS="true"
fi

if [[ "$HAS_ARTIFACTS" == "true" ]]; then
  # Step 5: Publish
  echo ""
  echo ">>> Step 5: Publish artifacts"
  PUB_CMD="sfp publish -d artifacts --npm --scope \"@$NPM_SCOPE\" --repository \"$REPOSITORY\" --sfp-server-url \"$SFP_SERVER_URL\" -t \"$SFP_SERVER_TOKEN\""
  [[ "$GIT_TAG" == "true" ]] && PUB_CMD="$PUB_CMD --gittag"
  [[ "$PUSH_GIT_TAG" == "true" ]] && PUB_CMD="$PUB_CMD --pushgittag"
  eval $PUB_CMD || echo "Publish completed (with warnings)"

  # Step 6: Fetch tags
  echo ""
  echo ">>> Step 6: Fetch tags"
  git fetch --tags 2>/dev/null || true

  # Step 7: Generate release candidate
  echo ""
  echo ">>> Step 7: Generate release candidate"
  [[ -z "$RELEASE_NAME" ]] && RELEASE_NAME="${BRANCH}-${BUILD_NUMBER}"
  sfp releasecandidate generate -n "$RELEASE_NAME" -c HEAD -b "$BRANCH" -f "$RELEASE_CONFIG" \
    --scope "@$NPM_SCOPE" --repository "$REPOSITORY" --sfp-server-url "$SFP_SERVER_URL" -t "$SFP_SERVER_TOKEN"
fi

echo ""
echo "------------------------------------------------------------------------------------------"
echo "Summary: Artifacts=$ARTIFACT_COUNT, Release=${RELEASE_NAME:-N/A}"
echo "------------------------------------------------------------------------------------------"
