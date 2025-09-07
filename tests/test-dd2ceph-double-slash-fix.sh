#!/usr/bin/env bash
###############################################################################
# Test for Double Slash Issue in dd2ceph --log_dir
# 
# Issue: When --log_dir contains double slashes (//), it can cause bucket access
# errors due to malformed paths in variable expansion and string processing.
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

test_dd2ceph_double_slash_issue() {
    start_test "dd2ceph double slash issue reproduction and fix"
    
    setup_mock_cephtools "$PROJECT_ROOT"
    
    # Create test environment
    local test_root="$PWD/double_slash_test"
    mkdir -p "$test_root"
    cd "$test_root"
    
    # Set up MSIPROJECT for test
    export MSIPROJECT="$test_root"
    
    # Create test data_delivery directory
    mkdir -p "$MSIPROJECT/data_delivery"
    echo "test content" > "$MSIPROJECT/data_delivery/test-file.txt"
    
    # Create problematic log directory path with double slash (mimics user's issue)
    local problematic_log_dir="$MSIPROJECT/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"
    
    # Mock required commands to avoid actual rclone/s3 calls
    create_mock_command "rclone" "" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "module" "" 0
    create_mock_command "s3cmd" "" 0
    
    # Mock rclone commands specifically
    create_logging_mock_command "rclone" "dummy output" 0
    
    echo "Testing with problematic log_dir: $problematic_log_dir"
    
    # Capture the output to analyze the issue
    local output
    if output=$("$CEPHTOOLS_BIN" dd2ceph --bucket test-bucket --log_dir "$problematic_log_dir" --dry_run 2>&1); then
        echo "SUCCESS: dd2ceph completed without fatal errors"
        
        # Check what directories were actually created
        echo "Created directories under shared/ceph/:"
        if [[ -d "$MSIPROJECT/shared/ceph" ]]; then
            find "$MSIPROJECT/shared/ceph" -type d -name "*dd2ceph*" 2>/dev/null | head -5
            
            # Check if any working directories were created
            local work_dirs=("$problematic_log_dir"/test-bucket___dd2ceph_*)
            if [[ -d "${work_dirs[0]}" ]] 2>/dev/null; then
                echo "Working directory created: ${work_dirs[0]}"
                
                # Check for any generated scripts
                local scripts=("${work_dirs[0]}"/*.slurm)
                if [[ -f "${scripts[0]}" ]]; then
                    echo "SLURM script generated successfully"
                    pass_test "dd2ceph handled double slash without breaking"
                else
                    echo "No SLURM scripts found in working directory"
                    fail_test "dd2ceph did not generate expected scripts"
                fi
            else
                echo "No working directory found at expected location"
                fail_test "dd2ceph did not create expected working directory"
            fi
        else
            fail_test "No shared/ceph directory was created"
        fi
    else
        echo "FAILURE: dd2ceph failed with double slash"
        echo "Output: $output"
        
        # Check if this is the bucket access error mentioned in the issue
        if echo "$output" | grep -q "Errors occured when accessing bucket"; then
            fail_test "REPRODUCED: Double slash caused bucket access error (original issue)"
        else
            fail_test "dd2ceph failed for different reason: $output"
        fi
    fi
    
    cd "$PROJECT_ROOT"
    rm -rf "$test_root"
}

test_path_normalization_solution() {
    start_test "Path normalization fixes double slash issues"
    
    # Test a simple path normalization function (potential fix)
    normalize_path() {
        local path="$1"
        # Remove duplicate slashes and clean up path
        echo "$path" | sed 's|//*|/|g' | sed 's|/$||' | sed 's|^$|/|'
    }
    
    # Test cases that would fix the reported issue
    local test_cases=(
        "/panfs/jay/groups/13/dehms/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"
        "//leading/double/slash"
        "/middle//double//slash/path"
        "/trailing/double/slash//"
        "///multiple///slashes///"
    )
    
    local expected=(
        "/panfs/jay/groups/13/dehms/shared/ceph/shrestha-70-mcrpc-biopsy-samples-atac-seq"
        "/leading/double/slash"
        "/middle/double/slash/path"
        "/trailing/double/slash"
        "/multiple/slashes"
    )
    
    local failed=0
    for i in "${!test_cases[@]}"; do
        local result=$(normalize_path "${test_cases[$i]}")
        local expected_result="${expected[$i]}"
        
        if [[ "$result" == "$expected_result" ]]; then
            echo "✓ '${test_cases[$i]}' → '$result'"
        else
            echo "✗ '${test_cases[$i]}' → '$result' (expected '$expected_result')"
            ((failed++))
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        pass_test "Path normalization function works correctly"
    else
        fail_test "$failed path normalization cases failed"
    fi
}

echo "=== Testing dd2ceph Double Slash Issue ==="
test_dd2ceph_double_slash_issue
test_path_normalization_solution
print_test_summary