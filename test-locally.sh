#!/bin/bash
# Local Action Test Runner for flxbl-io/build
# Runs the build action steps directly on your machine using local sfp CLI
#
# Usage:
#   ./test-locally.sh <project-path> [options]
#
# Example:
#   ./test-locally.sh /path/to/salesforce-project
#   ./test-locally.sh /path/to/project sfp-server-url=http://localhost:4392/
#   ./test-locally.sh . release-config=config/my-release.yaml diff-check=false

set -e

PROJECT_PATH="${1:-.}"
shift || true

# Change to project directory
cd "$PROJECT_PATH"

# Default GitHub context variables
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$(basename $(dirname $(pwd)))/$(basename $(pwd))}"
export GITHUB_REF_NAME="${GITHUB_REF_NAME:-main}"
export GITHUB_RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/github_output_$$}"

# Create output file
> "$GITHUB_OUTPUT"

# Parse inputs from command line (format: input-name=value)
for arg in "$@"; do
  name="${arg%%=*}"
  value="${arg#*=}"
  env_name="INPUT_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
  export "$env_name"="$value"
done

# Set default inputs
export INPUT_SFP_SERVER_URL="${INPUT_SFP_SERVER_URL:-http://localhost:4392/}"
export INPUT_SFP_SERVER_TOKEN="${INPUT_SFP_SERVER_TOKEN:-00000000-0000-0000-0000-000000000005}"
export INPUT_RELEASE_CONFIG="${INPUT_RELEASE_CONFIG:-}"
export INPUT_REPOSITORY="${INPUT_REPOSITORY:-$GITHUB_REPOSITORY}"
export INPUT_BRANCH="${INPUT_BRANCH:-$GITHUB_REF_NAME}"
export INPUT_BUILD_NUMBER="${INPUT_BUILD_NUMBER:-$GITHUB_RUN_ID}"
export INPUT_RELEASE_NAME="${INPUT_RELEASE_NAME:-}"
export INPUT_DIFF_CHECK="${INPUT_DIFF_CHECK:-true}"
export INPUT_NPM_SCOPE="${INPUT_NPM_SCOPE:-$(echo $GITHUB_REPOSITORY | cut -d'/' -f1)}"
export INPUT_GIT_TAG="${INPUT_GIT_TAG:-false}"
export INPUT_PUSH_GIT_TAG="${INPUT_PUSH_GIT_TAG:-false}"

# Validate required inputs
if [[ -z "$INPUT_RELEASE_CONFIG" ]]; then
  echo "Error: release-config is required"
  echo "Usage: ./test-locally.sh <project-path> release-config=path/to/config.yaml"
  exit 1
fi

if [[ ! -f "$INPUT_RELEASE_CONFIG" ]]; then
  echo "Error: Release config file not found: $INPUT_RELEASE_CONFIG"
  exit 1
fi

echo "------------------------------------------------------------------------------------------"
echo "flxbl-actions/build -- Local Test Runner"
echo "------------------------------------------------------------------------------------------"
echo "Project       : $(pwd)"
echo "Repository    : $INPUT_REPOSITORY"
echo "Branch        : $INPUT_BRANCH"
echo "Build Number  : $INPUT_BUILD_NUMBER"
echo "Release Config: $INPUT_RELEASE_CONFIG"
echo "Diff Check    : $INPUT_DIFF_CHECK"
echo "SFP Server    : $INPUT_SFP_SERVER_URL"
echo "------------------------------------------------------------------------------------------"
echo ""

# Step 1: Check git depth
echo ">>> Step 1: Check git depth"
if git rev-parse --is-shallow-repository 2>/dev/null | grep -q true; then
  echo "::warning::Shallow clone detected."
  if [[ "$INPUT_DIFF_CHECK" == "true" ]]; then
    echo "Fetching full history for diff-check..."
    git fetch --unshallow --tags 2>/dev/null || true
  fi
fi
git fetch --tags 2>/dev/null || true
echo ""

# Step 2: Authenticate to DevHub
echo ">>> Step 2: Authenticate to DevHub"
sfp org login --server --default-devhub --alias devhub \
  --sfp-server-url "$INPUT_SFP_SERVER_URL" \
  -t "$INPUT_SFP_SERVER_TOKEN"
echo ""

# Step 3: Build packages
echo ">>> Step 3: Build packages"
CMD="sfp build -v devhub \
  --branch \"$INPUT_BRANCH\" \
  --buildnumber \"$INPUT_BUILD_NUMBER\" \
  --artifactdir artifacts \
  --sfp-server-url \"$INPUT_SFP_SERVER_URL\" \
  -t \"$INPUT_SFP_SERVER_TOKEN\" \
  --repository \"$INPUT_REPOSITORY\" \
  --releaseconfig \"$INPUT_RELEASE_CONFIG\""

if [[ "$INPUT_DIFF_CHECK" == "true" ]]; then
  CMD="$CMD --diffcheck"
fi
eval $CMD
echo ""

# Step 4: Check for artifacts
echo ">>> Step 4: Check for artifacts"
ARTIFACT_COUNT=$(find artifacts -name "*.zip" 2>/dev/null | wc -l | tr -d ' ')
echo "artifact-count=$ARTIFACT_COUNT" >> "$GITHUB_OUTPUT"

if [[ "$ARTIFACT_COUNT" -eq 0 ]]; then
  echo "::warning::No artifacts were produced by the build"
  echo "has-artifacts=false" >> "$GITHUB_OUTPUT"
  HAS_ARTIFACTS="false"
else
  echo "Found $ARTIFACT_COUNT artifact(s)"
  echo "has-artifacts=true" >> "$GITHUB_OUTPUT"
  HAS_ARTIFACTS="true"
fi
echo ""

if [[ "$HAS_ARTIFACTS" == "true" ]]; then
  # Step 5: Publish artifacts
  echo ">>> Step 5: Publish artifacts"
  CMD="sfp publish -d artifacts \
    --npm \
    --scope \"@$INPUT_NPM_SCOPE\" \
    --repository \"$INPUT_REPOSITORY\" \
    --sfp-server-url \"$INPUT_SFP_SERVER_URL\" \
    -t \"$INPUT_SFP_SERVER_TOKEN\""

  if [[ "$INPUT_GIT_TAG" == "true" ]]; then
    CMD="$CMD --gittag"
  fi
  if [[ "$INPUT_PUSH_GIT_TAG" == "true" ]]; then
    CMD="$CMD --pushgittag"
  fi
  eval $CMD || echo "Publish completed (with warnings)"
  echo ""

  # Step 6: Fetch tags
  echo ">>> Step 6: Fetch tags after publish"
  git fetch --tags 2>/dev/null || true
  echo ""

  # Step 7: Generate release candidate
  echo ">>> Step 7: Generate release candidate"
  RELEASE_NAME="$INPUT_RELEASE_NAME"
  if [[ -z "$RELEASE_NAME" ]]; then
    RELEASE_NAME="${INPUT_BRANCH}-${INPUT_BUILD_NUMBER}"
  fi

  sfp releasecandidate generate \
    -n "$RELEASE_NAME" \
    -c HEAD \
    -b "$INPUT_BRANCH" \
    -f "$INPUT_RELEASE_CONFIG" \
    --scope "@$INPUT_NPM_SCOPE" \
    --repository "$INPUT_REPOSITORY" \
    --sfp-server-url "$INPUT_SFP_SERVER_URL" \
    -t "$INPUT_SFP_SERVER_TOKEN"
  echo ""
fi

# Summary
echo "------------------------------------------------------------------------------------------"
echo "Build Summary"
echo "------------------------------------------------------------------------------------------"
if [[ "$HAS_ARTIFACTS" == "true" ]]; then
  echo "Artifacts        : $ARTIFACT_COUNT package(s)"
  echo "Published        : Yes"
  echo "Release Candidate: ${RELEASE_NAME:-N/A}"
else
  echo "Artifacts        : None (no changes detected)"
  echo "Published        : Skipped"
  echo "Release Candidate: Skipped"
fi
echo "------------------------------------------------------------------------------------------"
echo ""
echo "Outputs: $GITHUB_OUTPUT"
cat "$GITHUB_OUTPUT"
