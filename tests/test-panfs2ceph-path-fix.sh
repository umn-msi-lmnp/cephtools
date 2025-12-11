#!/usr/bin/env bash
###############################################################################
# Integration test for panfs2ceph path construction fix
# Tests the fix for BucketAlreadyExists error caused by incorrect path concatenation
###############################################################################

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Set paths
export CEPHTOOLS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CEPHTOOLS_BIN="${CEPHTOOLS_ROOT}/build/bin/cephtools"

# Test configuration
TEST_NAME="panfs2ceph-path-fix"
TEST_BUCKET="cephtools-test-panfs2ceph-paths"

# Use standard test framework for output directory management
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Initialize test framework (this sets up TEST_OUTPUT_DIR automatically)
init_tests "panfs2ceph-path-fix"

test_path_construction_fix() {
    start_test "panfs2ceph path construction generates correct rclone destinations"
    
    # Create test directory structure with absolute path in test outputs
    local test_source_dir="${TEST_OUTPUT_DIR}/test_data/home/user/project/data"
    mkdir -p "${test_source_dir}/subdir"
    echo "Test file content" > "${test_source_dir}/test.txt"
    echo "Subdir file content" > "${test_source_dir}/subdir/sub.txt"
    
    # Create mock s3cmd
    create_mock_command "s3cmd" "Bucket exists" 0
    
    # Create mock s3info
    create_mock_command "s3info" "test_access_key test_secret_key" 0
    
    # Set MSIPROJECT to our test output directory to control where logs go
    export MSIPROJECT="${TEST_OUTPUT_DIR}"
    
    # Run panfs2ceph with absolute path and dry run, specifying log directory
    local output
    if output=$(timeout 30 "${CEPHTOOLS_BIN}" panfs2ceph \
        --bucket "${TEST_BUCKET}" \
        --path "${test_source_dir}" \
        --log_dir "${TEST_OUTPUT_DIR}/logs" \
        --dry_run 2>&1); then
        
        # Extract script directory from output
        local script_dir
        script_dir=$(echo "$output" | grep -A1 "Archive dir transfer scripts:" | tail -1)
        
        if [[ -n "$script_dir" && -d "$script_dir" ]]; then
            local copy_script="${script_dir}/data.1_copy_and_verify.slurm"
            
            if [[ -f "$copy_script" ]]; then
                # Check that the rclone destination has proper bucket/path separation
                if grep -q "rclone copy.*${TEST_BUCKET}/.*test_data/home/user/project/data" "$copy_script"; then
                    pass_test "rclone copy destination correctly formatted with proper bucket/path separation"
                else
                    fail_test "rclone copy destination incorrectly formatted"
                    echo "Expected pattern: ${TEST_BUCKET}/test_data/home/user/project/data"
                    echo "Found in script:"
                    grep "rclone copy" "$copy_script" || true
                    return 1
                fi
                
                # Check that rclone check also has correct format
                if grep -q "rclone check.*${TEST_BUCKET}/.*test_data/home/user/project/data" "$copy_script"; then
                    pass_test "rclone check destination correctly formatted"
                else
                    fail_test "rclone check destination incorrectly formatted"
                    grep "rclone check" "$copy_script" || true
                    return 1
                fi
                
                # Verify old buggy concatenation is NOT present (would be bucket name without slash)
                # The old bug would create: "myremote:bucket/full/path" as bucket name
                # The fix creates: "myremote:bucket/full/path" as bucket + object path
                # We can verify the fix by ensuring there's a slash after the bucket name
                if grep -q "myremote:${TEST_BUCKET}/" "$copy_script"; then
                    pass_test "Path construction fixed: bucket and object path properly separated with slash"
                else
                    fail_test "Path construction not fixed: missing slash separator after bucket name"
                    grep "myremote:" "$copy_script" | head -1 || true
                    return 1
                fi
                
            else
                fail_test "Copy script not generated: $copy_script"
                return 1
            fi
        else
            fail_test "Script directory not found or empty: '$script_dir'"
            return 1
        fi
    else
        fail_test "panfs2ceph command failed"
        echo "Output: $output"
        return 1
    fi
}

test_multiple_path_formats() {
    start_test "panfs2ceph handles various absolute path formats correctly"
    
    local test_paths=(
        "/tmp/test"
        "/home/user/data"  
        "/very/deep/nested/path/structure"
    )
    
    for test_path in "${test_paths[@]}"; do
        # Create test directory in our test outputs area
        local full_test_path="${TEST_OUTPUT_DIR}/multi_test${test_path}"
        mkdir -p "$full_test_path"
        echo "test content for $test_path" > "${full_test_path}/test.txt"
        
        # Run panfs2ceph with explicit log directory
        local output
        if output=$(timeout 20 "${CEPHTOOLS_BIN}" panfs2ceph \
            --bucket "${TEST_BUCKET}" \
            --path "$full_test_path" \
            --log_dir "${TEST_OUTPUT_DIR}/logs_$(basename "$test_path")" \
            --dry_run 2>&1); then
            
            # Extract and check script
            local script_dir
            script_dir=$(echo "$output" | grep -A1 "Archive dir transfer scripts:" | tail -1)
            
            if [[ -n "$script_dir" && -d "$script_dir" ]]; then
                local copy_script="${script_dir}/$(basename "$test_path").1_copy_and_verify.slurm"
                
                if [[ -f "$copy_script" ]]; then
                    # Expected destination: bucket/path/with/multi_test prefix
                    if grep -q "${TEST_BUCKET}/.*multi_test${test_path}" "$copy_script"; then
                        pass_test "Path '$test_path' correctly processed with bucket/path separation"
                    else
                        fail_test "Path '$test_path' not correctly processed"
                        echo "Expected pattern: ${TEST_BUCKET}/${expected_path}"
                        grep "rclone copy" "$copy_script" | head -1 || true
                        return 1
                    fi
                else
                    fail_test "Script not created for path: $test_path"
                    return 1
                fi
            else
                fail_test "Script directory not found for path: $test_path"
                return 1
            fi
        else
            fail_test "panfs2ceph failed for path: $test_path"
            return 1
        fi
    done
}

test_restore_script_fix() {
    start_test "panfs2ceph restore script also has correct path construction"
    
    # Create test directory in our test outputs area
    local test_source_dir="${TEST_OUTPUT_DIR}/restore_test/test/path"
    mkdir -p "${test_source_dir}"
    echo "restore test content" > "${test_source_dir}/restore.txt"
    
    # Run panfs2ceph with explicit log directory
    local output
    if output=$(timeout 30 "${CEPHTOOLS_BIN}" panfs2ceph \
        --bucket "${TEST_BUCKET}" \
        --path "${test_source_dir}" \
        --log_dir "${TEST_OUTPUT_DIR}/logs_restore" \
        --dry_run 2>&1); then
        
        local script_dir
        script_dir=$(echo "$output" | grep -A1 "Archive dir transfer scripts:" | tail -1)
        
        if [[ -n "$script_dir" && -d "$script_dir" ]]; then
            local restore_script="${script_dir}/path.3_restore.slurm"
            
            if [[ -f "$restore_script" ]]; then
                # Check that restore script uses correct source path format
                if grep -q "rclone copy.*${TEST_BUCKET}/.*restore_test/test/path.*${test_source_dir}" "$restore_script"; then
                    pass_test "Restore script has correct path construction"
                else
                    fail_test "Restore script path construction incorrect"
                    echo "Expected to find: ${TEST_BUCKET}/restore_test/test/path"
                    grep "rclone copy" "$restore_script" || true
                    return 1
                fi
            else
                fail_test "Restore script not found: $restore_script"
                return 1
            fi
        else
            fail_test "Script directory not found"
            return 1
        fi
    else
        fail_test "panfs2ceph failed"
        return 1
    fi
}

cleanup_test_outputs() {
    # Test framework cleanup is handled by cleanup_tests
    # This function exists for backward compatibility but doesn't need to do anything
    :
}

# Main test execution
main() {
    echo "Starting panfs2ceph path construction fix integration test"
    echo "Test outputs will be isolated in test framework directory"
    
    # Check for real execution request
    if [[ "${1:-}" == "--real" ]] || [[ "${1:-}" == "--e2e" ]]; then
        echo
        echo "🔄 Real execution requested - delegating to E2E test..."
        exec "${SCRIPT_DIR}/test-panfs2ceph-e2e-real.sh"
    fi
    
    # Initialize tests with framework (this sets up TEST_OUTPUT_DIR)
    init_tests "$TEST_NAME"
    
    # Create mock s3info command
    create_mock_command "s3info" "test_access_key test_secret_key" 0
    
    # Run all tests
    test_path_construction_fix
    test_multiple_path_formats  
    test_restore_script_fix
    
    # Print results
    print_test_summary
    local exit_code=$?
    
    # Clean up framework test environment
    cleanup_tests
    
    if [[ $exit_code -eq 0 ]]; then
        echo
        echo "✅ All panfs2ceph path construction tests passed!"
        echo "📋 Summary: The fix properly separates bucket names from object paths"
        echo "🎯 Result: rclone destinations are now 'remote:bucket/object/path' instead of 'remote:bucket+object+path'"
        echo "📁 All test artifacts are contained in: ${TEST_OUTPUT_DIR}"
        echo
        echo "💡 To run end-to-end tests with real buckets:"
        echo "   ${SCRIPT_DIR}/test-panfs2ceph-e2e-real.sh"
        echo "   OR"
        echo "   $0 --real"
    fi
    
    # Handle test output cleanup
    cleanup_test_outputs
    
    return $exit_code
}

# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [options]"
    echo
    echo "panfs2ceph path construction fix integration test"
    echo "Tests the fix for BucketAlreadyExists error caused by incorrect path concatenation"
    echo
    echo "Options:"
    echo "  --real, --e2e     Run end-to-end tests with real S3 buckets"
    echo "  -h, --help        Show this help"
    echo
    echo "Test modes:"
    echo "  Mock tests        Fast validation using mocked dependencies (default)"
    echo "  Real tests        End-to-end validation using actual S3 buckets"
    echo
    echo "Prerequisites for real tests:"
    echo "  - s3cmd configured for MSI S3 service"
    echo "  - rclone available and working"
    echo "  - s3info for credential access"
    echo "  - Network access to s3.msi.umn.edu"
    echo
    echo "Examples:"
    echo "  $0                # Run mock tests (safe, fast)"
    echo "  $0 --real         # Run real S3 tests (requires setup)"
    exit 0
fi

# Run the test if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi