# ---------------------------------------------------------------------
# Version - Template for Build-Time Substitution
# ---------------------------------------------------------------------

# Semantic version (manually maintained in src/version.txt)
SEMANTIC_VERSION=""

# Build-time information (populated by makefile)
BUILD_DATE=""
GIT_CURRENT_BRANCH=""
GIT_LATEST_COMMIT=""
GIT_LATEST_COMMIT_SHORT=""
GIT_LATEST_COMMIT_DIRTY=""
GIT_LATEST_COMMIT_DATETIME=""
GIT_REMOTE=""
VERSION_SHORT=""

# Computed values
if [[ $GIT_REMOTE == git@github.com:* ]]; then
  GIT_WEB_URL="https://github.com/$(echo $GIT_REMOTE | sed 's|git@github.com:||;s|.git||')"
elif [[ $GIT_REMOTE == git@github.umn.edu:* ]]; then
  GIT_WEB_URL="https://github.umn.edu/$(echo $GIT_REMOTE | sed 's|git@github.umn.edu:||;s|.git||')"
else
  GIT_WEB_URL=$GIT_REMOTE
fi
GIT_LATEST_COMMIT_LINK="${GIT_WEB_URL}/commit/${GIT_LATEST_COMMIT}"
