#!/bin/bash

# Bump marketing version script for KMReader
# Usage: ./bump-version.sh [major|minor]
# Increments MARKETING_VERSION in project.pbxproj (two-digit version: major.minor)
# Allows unrelated working tree changes, but commits only the version file

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
PROJECT_REL="KMReader.xcodeproj/project.pbxproj"
PROJECT="$PROJECT_ROOT/$PROJECT_REL"

# Check argument
if [ -z "$1" ]; then
	echo -e "${RED}Error: Version type is required${NC}"
	echo "Usage: $0 [major|minor]"
	exit 1
fi

VERSION_TYPE="$1"

if [ "$VERSION_TYPE" != "major" ] && [ "$VERSION_TYPE" != "minor" ]; then
	echo -e "${RED}Error: Version type must be 'major' or 'minor'${NC}"
	exit 1
fi

# Refuse to bump if the version file itself already has pending changes.
cd "$PROJECT_ROOT"
if ! git diff --quiet -- "$PROJECT_REL" || ! git diff --cached --quiet -- "$PROJECT_REL"; then
	echo -e "${RED}Error: $PROJECT_REL already has uncommitted changes. Commit or stash them before bumping.${NC}"
	exit 1
fi

echo -e "${GREEN}Bumping $VERSION_TYPE version...${NC}"

# Extract current version
CURRENT_VERSION=$(grep -m 1 "MARKETING_VERSION = " "$PROJECT" | sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' | tr -d '"')
CURRENT_BUILD=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$PROJECT" | sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' | tr -d '"')

if [ -z "$CURRENT_VERSION" ]; then
	echo -e "${YELLOW}Error: Could not find MARKETING_VERSION${NC}"
	exit 1
fi
if [ -z "$CURRENT_BUILD" ]; then
	echo -e "${YELLOW}Error: Could not find CURRENT_PROJECT_VERSION${NC}"
	exit 1
fi

# Parse version components (two-digit format: major.minor)
IFS='.' read -ra VERSION_PARTS <<<"$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"

# Calculate next version
if [ "$VERSION_TYPE" == "major" ]; then
	MAJOR=$((MAJOR + 1))
	MINOR=0
elif [ "$VERSION_TYPE" == "minor" ]; then
	MINOR=$((MINOR + 1))
fi

NEXT_VERSION="$MAJOR.$MINOR"
NEXT_BUILD=$((CURRENT_BUILD + 1))

echo -e "${GREEN}Current version: $CURRENT_VERSION -> Next version: $NEXT_VERSION${NC}"
echo -e "${GREEN}Current build: $CURRENT_BUILD -> Next build: $NEXT_BUILD${NC}"

# Update all occurrences of MARKETING_VERSION
# -i.bak (suffix attached) is accepted by both BSD and GNU sed
sed -i.bak \
	-e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $NEXT_VERSION;/g" \
	-e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" \
	"$PROJECT"
rm -f "$PROJECT.bak"

echo -e "${GREEN}Version bumped successfully!${NC}"

# Commit the changes
echo -e "${GREEN}Committing changes...${NC}"
git add "$PROJECT_REL"
git commit -m "chore: bump version to $NEXT_VERSION" -- "$PROJECT_REL"

echo -e "${GREEN}Version bump committed!${NC}"
