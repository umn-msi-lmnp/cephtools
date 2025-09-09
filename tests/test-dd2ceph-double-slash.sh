#!/usr/bin/env bash
###############################################################################
# Test for Double Slash Issue in dd2ceph --log_dir
# Issue: When --log_dir contains double slashes (//), it can cause issues
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

test_dd2ceph_double_slash_reproducer() {
    start_test "Reproduce dd2ceph double slash issue"
    
    setup_mock_cephtools "$PROJECT_ROOT"
    
    # Create test data_delivery directory
    local test_data_delivery="$MSIPROJECT/data_delivery"
    mkdir -p "$test_data_delivery"
    echo "test content" > "$test_data_delivery/test-file.txt"
    
    # Create problematic log directory with double slash (like the reported issue)
    local problematic_log_dir="$MSIPROJECT/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"
    
    # Mock required commands
    create_mock_command "rclone" "rclone v1.71.0" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "module" "" 0
    create_logging_mock_command "rclone"
    
    echo "Testing with problematic log_dir: $problematic_log_dir"
    
    # Try to run dd2ceph with the problematic path
    if "$CEPHTOOLS_BIN" dd2ceph --bucket test-bucket --log_dir "$problematic_log_dir" --dry_run; then
        echo "dd2ceph ran successfully with double slash"
        
        # Check what directories were created
        echo "Created directories:"
        find "$MSIPROJECT/shared/ceph" -name "*dd2ceph*" -type d 2>/dev/null || echo "No dd2ceph directories found"
        
        # Check if double slashes persist in paths
        if find "$MSIPROJECT/shared/ceph" -path "*//\*" 2>/dev/null | grep -q "//"; then
            fail_test "Double slashes persist in created directory paths"
        else
            pass_test "dd2ceph handled double slash without creating problematic paths"
        fi
    else
        fail_test "dd2ceph failed with double slash in --log_dir (reproduces reported issue)"
    fi
}

# Run the test
echo "=== Testing dd2ceph Double Slash Issue ==="
test_dd2ceph_double_slash_reproducer
print_test_summary