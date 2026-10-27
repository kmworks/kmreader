#!/bin/bash

# Bump version script for KMReader
# Usage: ./bump.sh
# Increments CURRENT_PROJECT_VERSION in project.pbxproj
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

# Refuse to bump if the version file itself already has pending changes.
cd "$PROJECT_ROOT"
if ! git diff --quiet -- "$PROJECT_REL" || ! git diff --cached --quiet -- "$PROJECT_REL"; then
	echo -e "${RED}Error: $PROJECT_REL already has uncommitted changes. Commit or stash them before bumping.${NC}"
	exit 1
fi

echo -e "${GREEN}Bumping version...${NC}"

# Extract current version
CURRENT_VERSION=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$PROJECT" | sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);/\1/p')

if [ -z "$CURRENT_VERSION" ]; then
	echo -e "${YELLOW}Error: Could not find CURRENT_PROJECT_VERSION${NC}"
	exit 1
fi

# Calculate next version
NEXT_VERSION=$((CURRENT_VERSION + 1))

echo -e "${GREEN}Current version: $CURRENT_VERSION -> Next version: $NEXT_VERSION${NC}"

# Update all occurrences of CURRENT_PROJECT_VERSION
# -i.bak (suffix attached) is accepted by both BSD and GNU sed
sed -i.bak "s/CURRENT_PROJECT_VERSION = $CURRENT_VERSION;/CURRENT_PROJECT_VERSION = $NEXT_VERSION;/g" "$PROJECT"
rm -f "$PROJECT.bak"

echo -e "${GREEN}Version bumped successfully!${NC}"

# Commit the changes
echo -e "${GREEN}Committing changes...${NC}"
git add "$PROJECT_REL"
git commit -m "chore: incr build ver to $NEXT_VERSION" -- "$PROJECT_REL"

echo -e "${GREEN}Version bump committed!${NC}"
