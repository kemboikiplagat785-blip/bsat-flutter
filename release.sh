#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Colors for output ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Default Variables ---
COMMIT_MESSAGE=""
VERSION_ARG=""

# --- Parse Arguments ---
while getopts "c:v:" opt; do
  case $opt in
    c) COMMIT_MESSAGE="$OPTARG" ;;
    v) VERSION_ARG="$OPTARG" ;;
    *) echo "Usage: $0 [-c commitMessage] [-v version]" >&2; exit 1 ;;
  esac
done

# Step 1: Read current version from pubspec.yaml
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found in current directory.${NC}"
    exit 1
fi

CURRENT_VERSION_LINE=$(grep "^version:" pubspec.yaml)
# Extract version string (e.g., 1.0.0+1)
CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | cut -d ':' -f 2 | xargs)

# Step 2: Split version and build number using Regex
# Bash regex capture groups go into BASH_REMATCH
if [[ "$CURRENT_VERSION" =~ ^([0-9]+\.[0-9]+\.([0-9]+))\+?([0-9]+)?$ ]]; then
    FULL_VER=${BASH_REMATCH[1]}  # x.y.z
    PATCH=${BASH_REMATCH[2]}     # z
    CURRENT_BUILD=${BASH_REMATCH[3]:-0} # build number or 0

    # Split x.y.z for parts
    IFS='.' read -r MAJOR MINOR PATCH_VAL <<< "$FULL_VER"
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
    else
        echo -e "${RED}Invalid version value. Use x.y.z or x.y.z+build (e.g., 3.7.0 or 3.7.0+2).${NC}"
        exit 1
    fi
else
    # Auto-increment patch
    NEW_PATCH=$((PATCH_VAL + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH+$CURRENT_BUILD"
fi

# Uncomment the line below if you want to hardcode to 4.0.0 as in your ps1 logic
# NEW_VERSION="4.0.0+$CURRENT_BUILD"

# Step 4: Write new version to pubspec.yaml
echo -e "Bumping version from $CURRENT_VERSION to $NEW_VERSION in pubspec.yaml..."

# macOS sed requires an empty string argument for -i to work correctly without creating backups
sed -i '' "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml

# Step 5: Git operations
git add .
if [ -n "$COMMIT_MESSAGE" ]; then
    git commit -m "$COMMIT_MESSAGE"
else
    git commit -m "Bump version to $NEW_VERSION"
fi

git checkout -b "release/v$NEW_VERSION"
git push -u origin "release/v$NEW_VERSION"

# Step 6: Build APKs (split by architecture)
echo -e "${CYAN}Building APKs for all architectures...${NC}"
flutter build apk --split-per-abi

# Step 7: Rename all generated APKs
# Using relative pathing for macOS
BASE_PATH="build/app/outputs/flutter-apk"
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

for ABI in "${ABIS[@]}"; do
    SOURCE_APK="$BASE_PATH/app-$ABI-release.apk"
    NEW_NAME="bsat-$ABI-$NEW_VERSION.apk"

    if [ -f "$SOURCE_APK" ]; then
        mv "$SOURCE_APK" "$BASE_PATH/$NEW_NAME"
        echo -e "${CYAN}APK renamed to $NEW_NAME${NC}"
    else
        echo -e "${RED}APK not found at $SOURCE_APK${NC}"
    fi
done

echo -e "${GREEN}Version bumped to $NEW_VERSION, pushed to git, and all APKs built!${NC}"