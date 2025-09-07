#!/usr/bin/env bash
###############################################################################
# Test Case for Reported Issue: Double Slash in --log_dir Causes Bucket Access Error
#
# ISSUE DESCRIPTION:
# When running dd2ceph with --log_dir containing double slashes (//), 
# such as: --log_dir /panfs/jay/groups/13/dehms/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq
# 
# The tool triggers an error about not being able to access the tier2 bucket,
# possibly due to malformed path handling during variable expansion.
#
# ERROR MESSAGE:
# "Errors occured when accessing bucket: 'bucket-name'
#  Does the bucket exist?
#  Do you have access rights to the bucket?"
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

###############################################################################
# Test Functions
###############################################################################

test_issue_reproduction() {
    start_test "Reproduce reported double slash issue"
    
    # Set up isolated test environment
    local test_root="$PWD/issue_test_$$"
    mkdir -p "$test_root"
    cd "$test_root"
    
    # Create test data structure
    export MSIPROJECT="$test_root"
    mkdir -p "$MSIPROJECT/data_delivery"
    echo "test file content" > "$MSIPROJECT/data_delivery/sample.txt"
    
    # Create the exact problematic path from the reported issue
    local problematic_log_dir="$MSIPROJECT/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"
    
    echo "Testing with problematic log_dir: $problematic_log_dir"
    echo "(Note: This reproduces the exact issue reported by the user)"
    
    # Run dd2ceph with the problematic path
    local output
    local exit_code=0
    if ! output=$(timeout 10 "$CEPHTOOLS_BIN" dd2ceph --bucket test-bucket --log_dir "$problematic_log_dir" --dry_run 2>&1); then
        exit_code=$?
    fi
    
    echo "Exit code: $exit_code"
    echo "Output:"
    echo "$output"
    
    # Check if we reproduced the exact error from the issue report
    if echo "$output" | grep -q "Errors occured when accessing bucket"; then
        echo "✓ REPRODUCED: The exact bucket access error from the issue report"
        pass_test "Successfully reproduced the reported issue"
    else
        echo "✗ Different error occurred (may still be related to double slash)"
        fail_test "Could not reproduce exact issue, but double slash still problematic"
    fi
    
    # Check what directories were created with double slashes
    if [[ -d "$MSIPROJECT/shared/ceph" ]]; then
        echo ""
        echo "Created directory structure:"
        find "$MSIPROJECT/shared/ceph" -type d 2>/dev/null | sed 's/^/  /'
        
        # Check if double slashes were preserved in directory names
        if find "$MSIPROJECT/shared/ceph" -type d 2>/dev/null | grep -q "//"; then
            echo "WARNING: Double slashes were preserved in directory structure"
        fi
    fi
    
    # Cleanup
    cd "$PROJECT_ROOT"
    rm -rf "$test_root"
}

test_path_validation_approach() {
    start_test "Demonstrate path validation approach (instead of normalization)"
    
    # This function would be added to dd2ceph plugin to validate paths
    validate_path() {
        local path="$1"
        local path_name="${2:-path}"
        
        # Check for problematic patterns that could cause issues
        if [[ "$path" =~ // ]]; then
            echo "ERROR: $path_name contains double slashes (//): '$path'"
            echo "Please provide a clean path without double slashes."
            echo "Example: instead of '/path//to/dir', use '/path/to/dir'"
            return 1
        fi
        
        if [[ "$path" =~ /$ ]] && [[ "$path" != "/" ]]; then
            echo "WARNING: $path_name ends with trailing slash: '$path'"
            echo "Consider removing the trailing slash for consistency."
        fi
        
        if [[ "$path" =~ ^// ]]; then
            echo "ERROR: $path_name starts with double slashes: '$path'"
            echo "Please provide a path starting with single slash."
            return 1
        fi
        
        return 0
    }
    
    echo "Path validation examples (proposed approach):"
    echo ""
    
    # Test cases based on the actual reported issue
    local test_paths=(
        "/panfs/jay/groups/13/dehms/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"
        "/normal/path/without/issues"
        "//leading/double/slash"
        "/middle//double//slashes/path"
        "/trailing/path/"
        "///multiple///consecutive///slashes///"
        "/clean/path/example"
    )
    
    local validation_passed=0
    local validation_failed=0
    
    for path in "${test_paths[@]}"; do
        echo "Testing path: '$path'"
        if validate_path "$path" "log_dir"; then
            echo "✓ VALID path"
            ((validation_passed++))
        else
            echo "✗ INVALID path (would be rejected)"
            ((validation_failed++))
        fi
        echo ""
    done
    
    echo "Summary: $validation_passed valid paths, $validation_failed invalid paths"
    
    if [[ $validation_failed -gt 0 ]]; then
        pass_test "Path validation correctly identifies problematic paths"
    else
        fail_test "Path validation should have caught some problematic paths"
    fi
}

test_proposed_integration() {
    start_test "Show how to integrate path validation into dd2ceph"
    
    echo "PROPOSED FIX for dd2ceph plugin (validation approach):"
    echo ""
    echo "In src/plugins/dd2ceph/plugin.sh, add path validation function:"
    echo ""
    cat << 'EOF'
# Add this function near the other helper functions
__validate_log_dir_path() {
    local path="$1"
    
    # Check for double slashes that can cause path issues
    if [[ "$path" =~ // ]]; then
        _exit_1 printf "Invalid --log_dir path contains double slashes: '%s'\\n" "$path"
        printf "Double slashes in paths can cause unexpected behavior.\\n"
        printf "Please provide a clean path without double slashes.\\n"
        printf "Example: instead of '/path//to/dir', use '/path/to/dir'\\n"
    fi
    
    # Check for leading double slashes
    if [[ "$path" =~ ^// ]]; then
        _exit_1 printf "Invalid --log_dir path starts with double slashes: '%s'\\n" "$path"
        printf "Please provide a path starting with a single slash.\\n"
    fi
    
    # Warn about trailing slashes (non-fatal)
    if [[ "$path" =~ /$ ]] && [[ "$path" != "/" ]]; then
        _warn printf "log_dir path ends with trailing slash: '%s'\\n" "$path"
        printf "Consider removing trailing slashes for consistency.\\n"
    fi
    
    return 0
}
EOF
    echo ""
    echo "Then modify the --log_dir option processing around line 159:"
    echo ""
    cat << 'EOF'
        -l|--log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            __validate_log_dir_path "$_log_dir"
            shift
            ;;
EOF
    echo ""
    echo "This approach:"
    echo "- Catches problematic paths early with clear error messages"  
    echo "- Preserves user intent by not modifying their paths"
    echo "- Prevents the bucket access issues caused by malformed paths"
    echo "- Provides helpful guidance on how to fix the path"
    
    pass_test "Path validation integration approach documented"
}

###############################################################################
# Main Test Runner
###############################################################################

echo "=== Testing Issue: Double Slash in --log_dir Causes Bucket Access Error ==="
echo "Issue URL: [Add GitHub issue URL when created]"
echo ""

test_issue_reproduction
test_path_validation_approach  
test_proposed_integration

echo ""
echo "=== SUMMARY ==="
echo "This test reproduces the reported issue where double slashes in --log_dir"
echo "cause dd2ceph to fail with bucket access errors. The fix involves adding"
echo "path validation to detect and reject problematic paths with helpful error messages."
echo "This approach preserves user intent while preventing malformed path issues."
echo ""

print_test_summary