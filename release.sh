#!/bin/bash

# Exit immediatediately if a command exits with a non-zero status
set -e

# --- Colors for output ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Default Variables ---
COMMIT_MESSAGE=""
VERSION_ARG=""
DEFAULT_RELEASE_REPO="https://github.com/Bingwa-Sokoni-Automation-Toolkit/releases"
RELEASE_REPO="${RELEASE_REPO:-$DEFAULT_RELEASE_REPO}"

# --- Parse Arguments ---
while getopts "c:v:r:" opt; do
  case $opt in
    c) COMMIT_MESSAGE="$OPTARG" ;;
    v) VERSION_ARG="$OPTARG" ;;
    r) RELEASE_REPO="$OPTARG" ;;
    *) echo "Usage: $0 [-c commitMessage] [-v version] [-r releaseRepo]" >&2; exit 1 ;;
  esac
done

normalize_release_repo() {
    local repo_input="$1"

    if [[ "$repo_input" =~ ^https://github.com/([^/]+)/([^/]+)/?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$repo_input" =~ ^([^/]+)/([^/]+)$ ]]; then
        echo "$repo_input"
        return 0
    fi

    return 1
}

if ! GH_RELEASE_REPO="$(normalize_release_repo "$RELEASE_REPO")"; then
    echo -e "${RED}Invalid release repo: $RELEASE_REPO${NC}"
    echo -e "${RED}Use OWNER/REPO or https://github.com/OWNER/REPO${NC}"
    exit 1
fi

# Step 1: Read current version
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found.${NC}"
    exit 1
fi

CURRENT_VERSION_LINE=$(grep "^version:" pubspec.yaml)
CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | cut -d ':' -f 2 | xargs)

# Step 2: Parse Version
if [[ "$CURRENT_VERSION" =~ ^([0-9]+\.[0-9]+\.([0-9]+))\+?([0-9]+)?$ ]]; then
    FULL_VER=${BASH_REMATCH[1]}
    PATCH_VAL=${BASH_REMATCH[2]}
    CURRENT_BUILD=${BASH_REMATCH[3]:-0}
    IFS='.' read -r MAJOR MINOR PATCH_VAL_INTERNAL <<< "$FULL_VER"
else
    echo -e "${RED}Could not parse version string: $CURRENT_VERSION${NC}"
    exit 1
fi

# Step 3: Decide new version
if [ -n "$VERSION_ARG" ]; then
    if [[ "$VERSION_ARG" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]+)?$ ]]; then
        TARGET_VER=${BASH_REMATCH[1]}
        TARGET_BUILD=${BASH_REMATCH[2]:-$CURRENT_BUILD}
        NEW_VERSION="$TARGET_VER+$TARGET_BUILD"
        RELEASE_TAG="$TARGET_VER"
    else
        echo -e "${RED}Invalid version. Use x.y.z (e.g., 4.0.65).${NC}"
        exit 1
    fi
else
    NEW_PATCH=$((PATCH_VAL + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH+$CURRENT_BUILD"
    RELEASE_TAG="$MAJOR.$MINOR.$NEW_PATCH"
fi

# Step 4: Write new version
echo -e "Bumping version to $NEW_VERSION..."
sed -i '' "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml

# Step 5: Git operations
git add .
MSG="${COMMIT_MESSAGE:-Bump version to $NEW_VERSION}"
git commit -m "$MSG"

# Create a release branch
git checkout -b "release/v$RELEASE_TAG"
git push -u origin "release/v$RELEASE_TAG"

# Step 6: Build APKs
echo -e "${CYAN}Building APKs...${NC}"
#flutter build apk --split-per-abi

# Step 7: Rename APKs
BASE_PATH="build/app/outputs/flutter-apk"
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
UPLOAD_FILES=()

for ABI in "${ABIS[@]}"; do
    SOURCE_APK="$BASE_PATH/app-$ABI-release.apk"
    NEW_NAME="bsat-$ABI-$RELEASE_TAG.apk"

    if [ -f "$SOURCE_APK" ]; then
        mv "$SOURCE_APK" "$BASE_PATH/$NEW_NAME"
        UPLOAD_FILES+=("$BASE_PATH/$NEW_NAME")
        echo -e "${CYAN}Renamed: $NEW_NAME${NC}"
    fi
done

# --- Step 8: GitHub Release ---
echo -e "${CYAN}Creating GitHub Release $RELEASE_TAG in $GH_RELEASE_REPO...${NC}"

# Check if GH CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}GitHub CLI (gh) not found. Please install it to upload binaries.${NC}"
    exit 1
fi

# Create the release and upload the binaries
# --generate-notes automatically pulls the commit log into the release description
gh release create "$RELEASE_TAG" "${UPLOAD_FILES[@]}" \
    --repo "$GH_RELEASE_REPO" \
    --title "Version $RELEASE_TAG" \
    --notes "Automated release for version $RELEASE_TAG" \
    --latest

echo -e "${GREEN}Successfully released $RELEASE_TAG to GitHub!${NC}"