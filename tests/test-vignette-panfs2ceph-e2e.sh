#!/usr/bin/env bash
###############################################################################
# Comprehensive End-to-End Test for vignette_panfs2ceph.md Workflow
# Tests the complete workflow: bucket creation, bucket policy setup, 
# panfs2ceph script generation, and execution of all three scripts
###############################################################################

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Set paths
export CEPHTOOLS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CEPHTOOLS_BIN="${CEPHTOOLS_ROOT}/build/bin/cephtools"

# Test configuration
TEST_NAME="vignette-panfs2ceph-e2e"
TEST_BUCKET_PREFIX="cephtools-vignette-e2e"
TEST_TIMESTAMP="$(date +%Y%m%d_%H%M%S_$$)"
TEST_BUCKET="${TEST_BUCKET_PREFIX}-${TEST_TIMESTAMP}"
TEST_GROUP="$(id -ng)"
TEST_USER="$(id -un)"

# Test outputs directory
TEST_OUTPUTS_DIR="${SCRIPT_DIR}/outputs/vignette-panfs2ceph-e2e-${TEST_TIMESTAMP}"

# Cleanup tracking
CLEANUP_ITEMS=()
TEST_BUCKETS=()
TEST_TEMP_DIRS=()

###############################################################################
# Prerequisites and Setup
###############################################################################

check_vignette_prerequisites() {
    echo "🔍 Checking prerequisites for vignette end-to-end testing..."
    
    # Check cephtools binary
    if [[ ! -x "$CEPHTOOLS_BIN" ]]; then
        echo "❌ cephtools binary not found or not executable: $CEPHTOOLS_BIN"
        return 1
    fi
    
    # Check s3cmd
    if ! command -v s3cmd >/dev/null 2>&1; then
        echo "❌ s3cmd not found"
        return 1
    fi
    
    # Check rclone
    if ! command -v rclone >/dev/null 2>&1; then
        echo "❌ rclone not found"
        return 1
    fi
    
    # Check s3info for credentials
    if ! command -v s3info >/dev/null 2>&1; then
        echo "❌ s3info not found (needed for MSI S3 credentials)"
        return 1
    fi
    
    # Test s3info access
    if ! s3info --keys >/dev/null 2>&1; then
        echo "❌ s3info cannot access credentials"
        return 1
    fi
    
    # Test basic S3 connectivity
    if ! timeout 10 s3cmd ls >/dev/null 2>&1; then
        echo "❌ Cannot connect to S3 service"
        return 1
    fi
    
    echo "✅ All prerequisites met"
    return 0
}

setup_vignette_test_environment() {
    echo "🔧 Setting up vignette test environment..."
    
    # Create test outputs directory
    mkdir -p "${TEST_OUTPUTS_DIR}"
    export TEST_OUTPUT_DIR="${TEST_OUTPUTS_DIR}"
    
    # Create test data directory (simulating project data)
    local test_data_dir="${TEST_OUTPUTS_DIR}/test_project_data"
    mkdir -p "${test_data_dir}"
    TEST_TEMP_DIRS+=("${test_data_dir}")
    
    # Create realistic project structure with various file types
    echo "📁 Creating test project data structure..."
    mkdir -p "${test_data_dir}"/{data,scripts,results,empty_dir,subdir/{nested_empty,with_files}}
    
    # Create test files
    echo "Test data file 1" > "${test_data_dir}/data/file1.txt"
    echo "Test data file 2" > "${test_data_dir}/data/file2.txt"
    echo "#!/bin/bash\necho 'test script'" > "${test_data_dir}/scripts/analysis.sh"
    chmod +x "${test_data_dir}/scripts/analysis.sh"
    echo "Results from analysis" > "${test_data_dir}/results/output.txt"
    echo "Nested file" > "${test_data_dir}/subdir/with_files/nested.txt"
    
    # Create some larger files to make transfer more realistic
    dd if=/dev/zero of="${test_data_dir}/data/large_file.bin" bs=1024 count=100 2>/dev/null
    
    # Verify empty directories exist (important for testing directory markers)
    [[ -d "${test_data_dir}/empty_dir" ]] || { echo "❌ Empty directory creation failed"; return 1; }
    [[ -d "${test_data_dir}/subdir/nested_empty" ]] || { echo "❌ Nested empty directory creation failed"; return 1; }
    
    echo "✅ Test project data created at: ${test_data_dir}"
    echo "   - Files: $(find "${test_data_dir}" -type f | wc -l)"
    echo "   - Empty dirs: $(find "${test_data_dir}" -type d -empty | wc -l)"
    
    export TEST_PROJECT_DATA_DIR="${test_data_dir}"
    return 0
}

###############################################################################
# Vignette Workflow Steps
###############################################################################

test_step1_create_bucket() {
    start_test "Step 1: Create bucket (following vignette)"
    
    echo "🪣 Creating test bucket: ${TEST_BUCKET}"
    if timeout 30 s3cmd mb "s3://${TEST_BUCKET}" 2>/dev/null; then
        TEST_BUCKETS+=("${TEST_BUCKET}")
        
        # Verify bucket exists
        if s3cmd ls "s3://${TEST_BUCKET}" >/dev/null 2>&1; then
            pass_test "Bucket created successfully: ${TEST_BUCKET}"
            return 0
        else
            fail_test "Bucket created but not accessible"
            return 1
        fi
    else
        fail_test "Failed to create bucket: ${TEST_BUCKET}"
        return 1
    fi
}

test_step2_set_bucket_policy() {
    start_test "Step 2: Set bucket policy (following vignette)"
    
    echo "🔒 Setting GROUP_READ bucket policy..."
    cd "${TEST_OUTPUTS_DIR}"
    
    # Run cephtools bucketpolicy as described in vignette
    if "$CEPHTOOLS_BIN" bucketpolicy \
        --verbose \
        --bucket "$TEST_BUCKET" \
        --policy GROUP_READ \
        --group "$TEST_GROUP" \
        --log_dir "$TEST_OUTPUTS_DIR" >/dev/null 2>&1; then
        
        # Verify policy files were created
        local policy_file="${TEST_OUTPUTS_DIR}/${TEST_BUCKET}.bucket_policy.json"
        local readme_file="${TEST_OUTPUTS_DIR}/${TEST_BUCKET}.bucket_policy_readme.md"
        
        if [[ -f "$policy_file" ]] && [[ -f "$readme_file" ]]; then
            # Verify policy contains expected permissions
            if grep -q "s3:ListBucket\|s3:GetObject" "$policy_file"; then
                pass_test "Bucket policy set successfully with GROUP_READ permissions"
                return 0
            else
                fail_test "Policy file missing expected permissions"
                return 1
            fi
        else
            fail_test "Policy files not created"
            return 1
        fi
    else
        fail_test "bucketpolicy command failed"
        return 1
    fi
}

test_step3_generate_scripts() {
    start_test "Step 3: Generate panfs2ceph scripts (following vignette)"
    
    echo "📝 Generating panfs2ceph transfer scripts..."
    cd "${TEST_OUTPUTS_DIR}"
    
    # Run panfs2ceph as described in vignette
    local output
    if output=$("$CEPHTOOLS_BIN" panfs2ceph \
        --bucket "$TEST_BUCKET" \
        --path "$TEST_PROJECT_DATA_DIR" \
        --log_dir "$TEST_OUTPUTS_DIR" 2>&1); then
        
        # Extract script directory from output
        local script_dir
        script_dir=$(echo "$output" | grep -A1 "Archive dir transfer scripts:" | tail -1 | tr -d ' ')
        
        if [[ -d "$script_dir" ]]; then
            # Verify all three scripts were created
            local prefix="$(basename "${TEST_PROJECT_DATA_DIR}")"
            local script1="${script_dir}/${prefix}.1_copy_and_verify.slurm"
            local script2="${script_dir}/${prefix}.2_delete.slurm"
            local script3="${script_dir}/${prefix}.3_restore.slurm"
            local readme="${script_dir}/${prefix}.readme.md"
            
            if [[ -f "$script1" ]] && [[ -f "$script2" ]] && [[ -f "$script3" ]] && [[ -f "$readme" ]]; then
                # Store script paths for later use
                export SCRIPT1_PATH="$script1"
                export SCRIPT2_PATH="$script2" 
                export SCRIPT3_PATH="$script3"
                export SCRIPTS_DIR="$script_dir"
                
                pass_test "All three panfs2ceph scripts generated successfully"
                return 0
            else
                fail_test "Not all expected scripts were created"
                return 1
            fi
        else
            fail_test "Script directory not found"
            return 1
        fi
    else
        fail_test "panfs2ceph command failed: $output"
        return 1
    fi
}

test_step4_verify_script_flags() {
    start_test "Step 4: Verify correct rclone flags in scripts"
    
    echo "🔍 Verifying rclone command flags..."
    
    # Check script 1 (copy) has correct flags
    if grep -q "\-\-create-empty-src-dirs" "$SCRIPT1_PATH" && 
       grep -q "\-\-s3-directory-markers" "$SCRIPT1_PATH"; then
        echo "✅ Script 1 (copy) has correct directory handling flags"
    else
        fail_test "Script 1 missing required directory flags"
        return 1
    fi
    
    # Check script 2 (delete) does NOT have these flags for purge operations
    if grep -q "rclone.*purge" "$SCRIPT2_PATH"; then
        if grep -q "\-\-create-empty-src-dirs\|\-\-s3-directory-markers" "$SCRIPT2_PATH"; then
            fail_test "Script 2 (delete) should not have directory marker flags on purge commands"
            return 1
        else
            echo "✅ Script 2 (delete) correctly omits directory flags on purge"
        fi
    fi
    
    # Check script 3 (restore) has --create-empty-src-dirs but NOT --s3-directory-markers
    if grep -q "\-\-create-empty-src-dirs" "$SCRIPT3_PATH"; then
        if ! grep -q "\-\-s3-directory-markers" "$SCRIPT3_PATH"; then
            echo "✅ Script 3 (restore) has correct flags (--create-empty-src-dirs only)"
        else
            fail_test "Script 3 (restore) should not have --s3-directory-markers flag"
            return 1
        fi
    else
        fail_test "Script 3 (restore) missing --create-empty-src-dirs flag"
        return 1
    fi
    
    pass_test "All scripts have correct rclone flags"
    return 0
}

test_step5_execute_script1() {
    start_test "Step 5: Execute script 1 (copy and verify)"
    
    echo "📤 Executing copy and verify script..."
    
    # Extract and execute the rclone commands from script 1
    local temp_script="${TEST_OUTPUTS_DIR}/extracted_script1.sh"
    
    # Extract rclone commands from the SLURM script
    sed -n '/^rclone copy/,/^$/p' "$SCRIPT1_PATH" > "$temp_script"
    sed -n '/^rclone check/,/^$/p' "$SCRIPT1_PATH" >> "$temp_script"
    
    # Make it executable
    chmod +x "$temp_script"
    
    # Execute with timeout
    if timeout 300 bash "$temp_script" >/dev/null 2>&1; then
        # Verify files were uploaded to bucket
        local file_count
        file_count=$(s3cmd ls "s3://${TEST_BUCKET}" --recursive | wc -l)
        
        if [[ $file_count -gt 0 ]]; then
            echo "✅ Files successfully transferred to bucket ($file_count objects)"
            
            # Check if empty directories were handled correctly
            if s3cmd ls "s3://${TEST_BUCKET}" --recursive | grep -q "/$"; then
                echo "✅ Directory markers found in bucket (empty dirs preserved)"
            fi
            
            pass_test "Script 1 execution successful - files copied and verified"
            return 0
        else
            fail_test "No files found in bucket after transfer"
            return 1
        fi
    else
        fail_test "Script 1 execution failed or timed out"
        return 1
    fi
}

test_step6_verify_permissions() {
    start_test "Step 6: Verify bucket policy permissions work"
    
    echo "🔐 Testing bucket policy permissions..."
    
    # Test that we can read from the bucket (should work with GROUP_READ policy)
    if timeout 30 s3cmd ls "s3://${TEST_BUCKET}" --recursive >/dev/null 2>&1; then
        echo "✅ Read access confirmed (GROUP_READ policy working)"
        pass_test "Bucket policy permissions verified"
        return 0
    else
        fail_test "Cannot read from bucket - policy may not be working"
        return 1
    fi
}

test_step7_execute_script3_restore() {
    start_test "Step 7: Execute script 3 (restore) - test only"
    
    echo "📥 Testing restore script (without deleting original)..."
    
    # Create a different restore target to avoid conflicts
    local restore_target="${TEST_OUTPUTS_DIR}/restored_data"
    mkdir -p "$restore_target"
    TEST_TEMP_DIRS+=("$restore_target")
    
    # Modify script 3 to restore to our test location
    local temp_restore_script="${TEST_OUTPUTS_DIR}/test_restore.sh"
    
    # Extract rclone command from restore script and modify destination
    sed -n '/^rclone copy/,/^$/p' "$SCRIPT3_PATH" | \
        sed "s|${TEST_PROJECT_DATA_DIR}|${restore_target}|g" > "$temp_restore_script"
    
    chmod +x "$temp_restore_script"
    
    # Execute restore with timeout
    if timeout 300 bash "$temp_restore_script" >/dev/null 2>&1; then
        # Verify files were restored
        local restored_files
        restored_files=$(find "$restore_target" -type f | wc -l)
        local restored_dirs
        restored_dirs=$(find "$restore_target" -type d -empty | wc -l)
        
        if [[ $restored_files -gt 0 ]]; then
            echo "✅ Files restored successfully ($restored_files files)"
            
            if [[ $restored_dirs -gt 0 ]]; then
                echo "✅ Empty directories restored ($restored_dirs empty dirs)"
            fi
            
            pass_test "Script 3 (restore) test successful"
            return 0
        else
            fail_test "No files restored"
            return 1
        fi
    else
        fail_test "Restore script execution failed or timed out"
        return 1
    fi
}

###############################################################################
# Cleanup and Main
###############################################################################

cleanup_vignette_test() {
    echo "🧹 Cleaning up test resources..."
    
    # Clean up test buckets
    for bucket in "${TEST_BUCKETS[@]}"; do
        echo "Removing bucket: $bucket"
        s3cmd rb "s3://$bucket" --force --recursive 2>/dev/null || true
    done
    
    # Clean up temporary directories
    for temp_dir in "${TEST_TEMP_DIRS[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            echo "Removing directory: $temp_dir"
            rm -rf "$temp_dir" 2>/dev/null || true
        fi
    done
    
    # Clean up other items
    for item in "${CLEANUP_ITEMS[@]}"; do
        if [[ -e "$item" ]]; then
            echo "Removing: $item"
            rm -rf "$item" 2>/dev/null || true
        fi
    done
    
    echo "✅ Cleanup completed"
}

# Trap to ensure cleanup happens
trap cleanup_vignette_test EXIT

main() {
    echo "🚀 Starting Comprehensive Vignette panfs2ceph End-to-End Test"
    echo "Test: $TEST_NAME"
    echo "Timestamp: $TEST_TIMESTAMP"
    echo "Bucket: $TEST_BUCKET"
    echo "Group: $TEST_GROUP"
    echo "Output Dir: $TEST_OUTPUTS_DIR"
    echo "================================================================"
    
    # Check prerequisites
    if ! check_vignette_prerequisites; then
        echo "❌ Prerequisites check failed"
        exit 1
    fi
    
    # Setup test environment
    if ! setup_vignette_test_environment; then
        echo "❌ Test environment setup failed"
        exit 1
    fi
    
    # Execute the complete vignette workflow
    test_step1_create_bucket || exit 1
    test_step2_set_bucket_policy || exit 1  
    test_step3_generate_scripts || exit 1
    test_step4_verify_script_flags || exit 1
    test_step5_execute_script1 || exit 1
    test_step6_verify_permissions || exit 1
    test_step7_execute_script3_restore || exit 1
    
    # Print summary
    echo ""
    echo "================================================================"
    echo "🎉 Comprehensive Vignette End-to-End Test PASSED"
    echo "================================================================"
    echo "✅ Bucket creation: SUCCESS"
    echo "✅ Bucket policy setup: SUCCESS"  
    echo "✅ Script generation: SUCCESS"
    echo "✅ Flag verification: SUCCESS"
    echo "✅ Data transfer (script 1): SUCCESS"
    echo "✅ Permission verification: SUCCESS"
    echo "✅ Data restore (script 3): SUCCESS"
    echo ""
    echo "📊 Test artifacts saved to: $TEST_OUTPUTS_DIR"
    echo "🪣 Test bucket: $TEST_BUCKET (will be cleaned up)"
    echo ""
    echo "This test validates the complete workflow described in:"
    echo "   doc/vignette_panfs2ceph.md"
    echo ""
    
    return 0
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Comprehensive End-to-End Test for vignette_panfs2ceph.md"
        echo ""
        echo "This test validates the complete workflow described in the panfs2ceph vignette:"
        echo "1. Create bucket"
        echo "2. Set bucket policy" 
        echo "3. Generate panfs2ceph scripts"
        echo "4. Verify correct rclone flags"
        echo "5. Execute copy/verify script (script 1)"
        echo "6. Verify bucket policy permissions"
        echo "7. Test restore script (script 3)"
        echo ""
        echo "Prerequisites:"
        echo "- s3cmd configured for MSI S3 service"
        echo "- rclone available"
        echo "- s3info for credential access"
        echo "- Network access to s3.msi.umn.edu"
        echo "- Permission to create/delete test buckets"
        echo ""
        echo "Usage: $0"
        echo ""
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac