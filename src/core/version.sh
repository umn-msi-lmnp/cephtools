# ---------------------------------------------------------------------
# Version - Template for Build-Time Substitution
# ---------------------------------------------------------------------

# Semantic version (manually maintained in version.txt)
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
_git_remote_to_web_url() {
    local remote="${1:-}"
    local remote_path

    case "$remote" in
        git@github.com:*)
            remote_path="${remote#git@github.com:}"
            printf 'https://github.com/%s\n' "${remote_path%.git}"
            ;;
        git@github.umn.edu:*)
            remote_path="${remote#git@github.umn.edu:}"
            printf 'https://github.umn.edu/%s\n' "${remote_path%.git}"
            ;;
        *)
            printf '%s\n' "$remote"
            ;;
    esac
}

GIT_WEB_URL="$(_git_remote_to_web_url "$GIT_REMOTE")"
GIT_LATEST_COMMIT_LINK="${GIT_WEB_URL}/commit/${GIT_LATEST_COMMIT}"
