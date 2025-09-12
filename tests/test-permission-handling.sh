#!/usr/bin/env bash
###############################################################################
# Permission Handling Tests for cephtools
# Tests that plugins properly detect and handle file permission issues
###############################################################################

set -euo pipefail

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source the test framework
source "$SCRIPT_DIR/test-framework.sh"

###############################################################################
# Test Setup
###############################################################################

init_permission_tests() {
    init_tests "Permission Handling Tests"
    
    # Set up mock commands
    create_logging_mock_command "s3info" "test-access-key test-secret-key"
    create_logging_mock_command "rclone" "OK"
    create_logging_mock_command "module" ""
    
    # Create cephtools binary if it doesn't exist
    if [[ ! -f "$PROJECT_ROOT/build/bin/cephtools" ]]; then
        echo "Building cephtools for permission tests..."
        make -C "$PROJECT_ROOT" >/dev/null 2>&1
    fi
    
    export CEPHTOOLS_BIN="$PROJECT_ROOT/build/bin/cephtools"
}

###############################################################################
# Test Data Creation Functions
###############################################################################

# Create a test directory structure with permission issues
create_test_directory_with_permission_issues() {
    local test_dir="$1"
    
    # Create base directory structure
    mkdir -p "$test_dir"/{readable,unreadable,mixed}
    
    # Create readable files
    echo "Content 1" > "$test_dir/readable/file1.txt"
    echo "Content 2" > "$test_dir/readable/file2.txt"
    chmod 644 "$test_dir/readable"/*.txt
    
    # Create files that will become unreadable
    echo "Secret content 1" > "$test_dir/unreadable/secret1.txt"
    echo "Secret content 2" > "$test_dir/unreadable/secret2.txt"
    
    # Create mixed permissions directory
    echo "Normal file" > "$test_dir/mixed/normal.txt"
    echo "Restricted file" > "$test_dir/mixed/restricted.txt"
    chmod 644 "$test_dir/mixed/normal.txt"
    
    # Make some files/directories unreadable
    chmod 000 "$test_dir/unreadable/secret1.txt"
    chmod 000 "$test_dir/unreadable/secret2.txt" 
    chmod 000 "$test_dir/mixed/restricted.txt"
    
    # Also make the unreadable directory itself hard to access
    chmod 700 "$test_dir/unreadable"  # Only owner can access
    
    echo "$test_dir"
}

# Create a test directory with no permission issues
create_clean_test_directory() {
    local test_dir="$1"
    
    mkdir -p "$test_dir/subdir"
    echo "Clean content 1" > "$test_dir/file1.txt"
    echo "Clean content 2" > "$test_dir/subdir/file2.txt"
    chmod -R 644 "$test_dir"/*.txt "$test_dir"/subdir/*.txt
    
    echo "$test_dir"
}

# Create a completely inaccessible directory
create_inaccessible_directory() {
    local test_dir="$1"
    
    mkdir -p "$test_dir"
    echo "Cannot read this" > "$test_dir/secret.txt"
    
    # Make entire directory inaccessible
    chmod 000 "$test_dir"
    
    echo "$test_dir"
}

###############################################################################
# Permission Detection Tests
###############################################################################

test_permission_check_function_directly() {
    start_test "Permission check function with readable files"
    
    local test_dir="$TEST_OUTPUT_DIR/clean_test"
    create_clean_test_directory "$test_dir"
    
    # Source the panfs2ceph plugin to get access to the _check_path_permissions function
    source "$PROJECT_ROOT/build/share/plugins/panfs2ceph/plugin.sh"
    
    # Test should pass for clean directory
    if _check_path_permissions "$test_dir" >/dev/null 2>&1; then
        pass_test "Permission check passed for clean directory"
    else
        fail_test "Permission check failed unexpectedly for clean directory"
    fi
}

test_permission_check_with_issues() {
    start_test "Permission check function with unreadable files"
    
    local test_dir="$TEST_OUTPUT_DIR/problem_test"
    create_test_directory_with_permission_issues "$test_dir"
    
    # Source the panfs2ceph plugin to get access to the _check_path_permissions function
    source "$PROJECT_ROOT/build/share/plugins/panfs2ceph/plugin.sh"
    
    # Test should fail for directory with permission issues
    if ! _check_path_permissions "$test_dir" >/dev/null 2>&1; then
        pass_test "Permission check correctly failed for directory with issues"
    else
        fail_test "Permission check should have failed for directory with permission issues"
    fi
}

test_permission_check_nonexistent_path() {
    start_test "Permission check with nonexistent path"
    
    local nonexistent_path="$TEST_OUTPUT_DIR/does_not_exist"
    
    # Source the panfs2ceph plugin to get access to the _check_path_permissions function  
    source "$PROJECT_ROOT/build/share/plugins/panfs2ceph/plugin.sh"
    
    # Test should fail for nonexistent path
    if ! _check_path_permissions "$nonexistent_path" >/dev/null 2>&1; then
        pass_test "Permission check correctly failed for nonexistent path"
    else
        fail_test "Permission check should have failed for nonexistent path"
    fi
}

###############################################################################
# Full Plugin Integration Tests
###############################################################################

test_panfs2ceph_fails_with_permission_issues() {
    start_test "panfs2ceph plugin fails on permission issues"
    
    local test_dir="$TEST_OUTPUT_DIR/panfs2ceph_perm_test"
    create_test_directory_with_permission_issues "$test_dir"
    
    # Run panfs2ceph and expect it to fail due to permission issues
    local exit_code=0
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        pass_test "panfs2ceph correctly failed when permission issues detected"
    else
        fail_test "panfs2ceph should have failed due to permission issues"
    fi
}

test_panfs2ceph_succeeds_with_dry_run() {
    start_test "panfs2ceph plugin continues with --dry_run despite permission issues"
    
    local test_dir="$TEST_OUTPUT_DIR/panfs2ceph_dry_run_test"
    create_test_directory_with_permission_issues "$test_dir"
    
    # Run panfs2ceph with --dry_run and expect it to continue despite permission issues
    local exit_code=0
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" --dry_run >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        pass_test "panfs2ceph correctly continued with --dry_run despite permission issues"
    else
        fail_test "panfs2ceph should have continued with --dry_run despite permission issues"
    fi
}

test_panfs2ceph_succeeds_with_clean_directory() {
    start_test "panfs2ceph plugin succeeds with clean directory"
    
    local test_dir="$TEST_OUTPUT_DIR/panfs2ceph_clean_test"
    create_clean_test_directory "$test_dir"
    
    # Mock rclone to avoid actual network calls
    create_logging_mock_command "rclone" "Success"
    
    # Run panfs2ceph and expect it to succeed
    local exit_code=0
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" --dry_run >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        pass_test "panfs2ceph succeeded with clean directory"
    else
        fail_test "panfs2ceph should have succeeded with clean directory"
    fi
}

test_panfs2ceph_fails_with_inaccessible_directory() {
    start_test "panfs2ceph plugin fails with completely inaccessible directory"
    
    local test_dir="$TEST_OUTPUT_DIR/inaccessible_test"
    create_inaccessible_directory "$test_dir"
    
    # Run panfs2ceph and expect it to fail immediately
    local exit_code=0
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        pass_test "panfs2ceph correctly failed with inaccessible directory"
    else
        fail_test "panfs2ceph should have failed with inaccessible directory"
    fi
    
    # Clean up the inaccessible directory (need to fix permissions first)
    chmod 755 "$test_dir" 2>/dev/null || true
}

###############################################################################
# Permission Message Tests
###############################################################################

test_permission_error_messages() {
    start_test "Permission error messages are informative"
    
    local test_dir="$TEST_OUTPUT_DIR/message_test"
    create_test_directory_with_permission_issues "$test_dir"
    
    # Capture the error output
    local output_file="$TEST_OUTPUT_DIR/error_output.txt"
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" >"$output_file" 2>&1 || true
    
    # Check that the output contains informative error messages
    if grep -i "permission" "$output_file" >/dev/null; then
        pass_test "Error output contains permission-related messages"
    else
        fail_test "Error output should contain permission-related messages"
    fi
    
    if grep -i "unreadable" "$output_file" >/dev/null; then
        pass_test "Error output mentions unreadable files"
    else
        fail_test "Error output should mention unreadable files"  
    fi
}

test_permission_counts_reported() {
    start_test "Permission scan reports file counts"
    
    local test_dir="$TEST_OUTPUT_DIR/count_test"
    create_test_directory_with_permission_issues "$test_dir"
    
    # Capture the output
    local output_file="$TEST_OUTPUT_DIR/count_output.txt"
    "$CEPHTOOLS_BIN" panfs2ceph -b test-bucket -p "$test_dir" >"$output_file" 2>&1 || true
    
    # Check that counts are reported
    if grep -E "(Total items|Readable|Unreadable):" "$output_file" >/dev/null; then
        pass_test "Permission scan reports file counts"
    else
        fail_test "Permission scan should report file counts"
    fi
}

###############################################################################
# Edge Case Tests
###############################################################################

test_empty_directory_permissions() {
    start_test "Permission check handles empty directory"
    
    local empty_dir="$TEST_OUTPUT_DIR/empty_dir"
    mkdir -p "$empty_dir"
    
    # Source the panfs2ceph plugin
    source "$PROJECT_ROOT/build/share/plugins/panfs2ceph/plugin.sh"
    
    # Should succeed with empty directory
    if _check_path_permissions "$empty_dir" >/dev/null 2>&1; then
        pass_test "Permission check handles empty directory correctly"
    else
        fail_test "Permission check should handle empty directory"
    fi
}

test_single_file_permissions() {
    start_test "Permission check handles single file"
    
    local test_file="$TEST_OUTPUT_DIR/single_file.txt"
    echo "Single file content" > "$test_file"
    
    # Source the panfs2ceph plugin
    source "$PROJECT_ROOT/build/share/plugins/panfs2ceph/plugin.sh"
    
    # Should succeed with readable single file
    if _check_path_permissions "$test_file" >/dev/null 2>&1; then
        pass_test "Permission check handles single file correctly"
    else
        fail_test "Permission check should handle single file"
    fi
}

###############################################################################
# Test Suite Execution
###############################################################################

run_permission_tests() {
    echo "Running Permission Handling Tests..."
    
    init_permission_tests
    
    # Direct function tests
    test_permission_check_function_directly
    test_permission_check_with_issues  
    test_permission_check_nonexistent_path
    
    # Full plugin integration tests
    test_panfs2ceph_fails_with_permission_issues
    test_panfs2ceph_succeeds_with_dry_run
    test_panfs2ceph_succeeds_with_clean_directory
    test_panfs2ceph_fails_with_inaccessible_directory
    
    # Message and reporting tests
    test_permission_error_messages
    test_permission_counts_reported
    
    # Edge case tests
    test_empty_directory_permissions
    test_single_file_permissions
    
    print_test_summary
}

###############################################################################
# Main Execution
###############################################################################

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_permission_tests
fi