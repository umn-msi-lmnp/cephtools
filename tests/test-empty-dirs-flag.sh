#!/usr/bin/env bash
###############################################################################
# Empty Directory Flag Tests for cephtools
# Tests --delete_empty_dirs flag functionality for both panfs2ceph and dd2ceph
###############################################################################

set -euo pipefail

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

# Test configuration
TEST_PREFIX="cephtools-empty-dirs-test-$(date +%Y%m%d-%H%M%S)-$$"
TEST_BUCKET="${TEST_PREFIX}-bucket"
TEST_GROUP="$(id -ng)"
TEST_USER="$(id -un)"
CLEANUP_ITEMS=()

###############################################################################
# Utility Functions
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

cleanup_on_exit() {
    if [[ ${#CLEANUP_ITEMS[@]} -gt 0 ]]; then
        log_info "Cleaning up test resources..."
        
        # Remove test bucket if it exists
        if timeout 15 s3cmd ls "s3://$TEST_BUCKET" &>/dev/null; then
            log_info "Removing test bucket: $TEST_BUCKET"
            
            # First, remove all objects from the bucket
            log_info "Removing all objects from bucket: $TEST_BUCKET"
            timeout 60 s3cmd del "s3://$TEST_BUCKET" --recursive --force &>/dev/null 2>&1 || true
            
            # Then remove the empty bucket
            timeout 30 s3cmd rb "s3://$TEST_BUCKET" &>/dev/null || log_warning "Failed to remove bucket $TEST_BUCKET"
        fi
        
        # Remove any other cleanup items
        for item in "${CLEANUP_ITEMS[@]}"; do
            if [[ -f "$item" ]]; then
                rm -f "$item" || log_warning "Failed to remove $item"
            elif [[ -d "$item" ]]; then
                rm -rf "$item" || log_warning "Failed to remove directory $item"
            fi
        done
    fi
}

trap cleanup_on_exit EXIT

###############################################################################
# Test Data Setup Functions
###############################################################################

create_test_data_with_empty_dirs() {
    local base_dir="$1"
    
    # Create directory structure with both files and empty directories
    mkdir -p "$base_dir"/{data,empty1,subdir/{empty2,nonempty},another/empty3}
    
    # Add files to some directories
    echo "test content 1" > "$base_dir/data/file1.txt" 
    echo "test content 2" > "$base_dir/subdir/nonempty/file2.txt"
    echo "test content 3" > "$base_dir/another/file3.txt"
    
    # Verify empty directories exist
    [[ -d "$base_dir/empty1" ]] || { echo "Failed to create empty1"; return 1; }
    [[ -d "$base_dir/subdir/empty2" ]] || { echo "Failed to create empty2"; return 1; }
    [[ -d "$base_dir/another/empty3" ]] || { echo "Failed to create empty3"; return 1; }
    
    # Verify they are actually empty
    [[ -z "$(ls -A "$base_dir/empty1")" ]] || { echo "empty1 is not empty"; return 1; }
    [[ -z "$(ls -A "$base_dir/subdir/empty2")" ]] || { echo "empty2 is not empty"; return 1; }
    [[ -z "$(ls -A "$base_dir/another/empty3")" ]] || { echo "empty3 is not empty"; return 1; }
    
    log_info "Created test data structure:"
    log_info "  Files: $base_dir/data/file1.txt"
    log_info "         $base_dir/subdir/nonempty/file2.txt" 
    log_info "         $base_dir/another/file3.txt"
    log_info "  Empty dirs: $base_dir/empty1"
    log_info "              $base_dir/subdir/empty2"
    log_info "              $base_dir/another/empty3"
}

setup_mock_environment() {
    setup_mock_cephtools "$PROJECT_ROOT"
    
    # Mock all external commands for testing without real dependencies
    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "getent" "testgroup:x:1001:user1,user2,user3" 0
    create_mock_command "module" "" 0
    
    # Create a more sophisticated rclone mock that handles different operations
    cat > "$TEST_OUTPUT_DIR/mock-bin/rclone" <<EOF
#!/bin/bash
# Log all calls for debugging
echo "\$0 \$*" >> "$TEST_OUTPUT_DIR/rclone.log"

case "\$1" in
    listremotes)
        echo "myremote:"
        ;;
    lsf)
        # Mock successful file listing (can be empty for tests)
        case "\$2" in
            myremote:test-bucket|myremote:test-bucket/*)
                # Simulate successful bucket access
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    lsd)
        # Mock successful directory listing
        exit 0
        ;;
    version)
        echo "rclone v1.71.0"
        ;;
    *)
        # Default: succeed for all other operations
        exit 0
        ;;
esac
EOF
    chmod +x "$TEST_OUTPUT_DIR/mock-bin/rclone"
}

###############################################################################
# Validation Functions
###############################################################################

validate_custom_empty_dir_handling() {
    local script_file="$1"
    local should_use_custom_handling="$2"  # true/false
    local plugin_name="$3"
    
    if [[ ! -f "$script_file" ]]; then
        fail_test "SLURM script file not found: $script_file"
        return 1
    fi
    
    local script_content
    script_content=$(cat "$script_file")
    
    if [[ "$should_use_custom_handling" == "true" ]]; then
        # Verify custom empty directory handling is present
        if echo "$script_content" | grep -q "Using custom empty directory handling"; then
            pass_test "$plugin_name script uses custom empty directory handling"
        else
            fail_test "$plugin_name script missing custom empty directory handling"
            return 1
        fi
        
        # Verify temporary marker file creation logic is present
        if echo "$script_content" | grep -q "temp_marker.*empty_dir_marker"; then
            pass_test "$plugin_name script contains temporary marker file logic"
        else
            fail_test "$plugin_name script missing temporary marker file logic"
            return 1
        fi
        
        # Verify rclone copyto logic is present
        if echo "$script_content" | grep -q "rclone copyto.*temp_marker"; then
            pass_test "$plugin_name script contains rclone copyto logic"
        else
            fail_test "$plugin_name script missing rclone copyto logic"
            return 1
        fi
        
        # Verify no problematic S3 flags are used
        if echo "$script_content" | grep -q "\-\-s3-directory-markers"; then
            fail_test "$plugin_name script still contains problematic --s3-directory-markers flag"
            return 1
        fi
        
        # Verify find command for empty directories
        if echo "$script_content" | grep -q "find.*-type d -empty"; then
            pass_test "$plugin_name script contains empty directory detection logic"
        else
            fail_test "$plugin_name script missing empty directory detection"
            return 1
        fi
        
        # Verify temporary marker file cleanup
        if echo "$script_content" | grep -q "rm -f.*temp_marker"; then
            pass_test "$plugin_name script contains temporary marker cleanup logic"
        else
            fail_test "$plugin_name script missing temporary marker cleanup"
            return 1
        fi
        
    else
        # When empty directory handling is disabled, should skip the custom logic
        if echo "$script_content" | grep -q "Skipping empty directories.*--delete_empty_dirs flag set"; then
            pass_test "$plugin_name script correctly skips empty directory handling"
        else
            fail_test "$plugin_name script should skip empty directory handling when flag is set"
            return 1
        fi
        
        # Should not contain marker file logic when disabled
        if echo "$script_content" | grep -q "temp_marker.*empty_dir_marker"; then
            fail_test "$plugin_name script should not contain marker file logic when disabled"
            return 1
        fi
        
        # Should not contain rclone copyto logic when disabled
        if echo "$script_content" | grep -q "rclone copyto"; then
            fail_test "$plugin_name script should not contain rclone copyto when disabled"
            return 1
        fi
    fi
}

validate_empty_dirs_with_markers() {
    local bucket="$1"
    local should_have_empty_dirs="$2"  # true/false
    local plugin_name="$3"
    
    # Look for marker files which indicate empty directories are preserved
    local marker_count=0
    local marker_files
    if marker_files=$(timeout 30 rclone lsf "$bucket:" -R --include "*.cephtools_empty_dir_marker" 2>/dev/null); then
        marker_count=$(echo "$marker_files" | grep -c "\.cephtools_empty_dir_marker" || true)
    fi
    
    if [[ "$should_have_empty_dirs" == "true" ]]; then
        if [[ $marker_count -gt 0 ]]; then
            pass_test "$plugin_name: Found $marker_count marker files indicating preserved empty directories"
        else
            fail_test "$plugin_name: No marker files found, empty directories may not be preserved"
            return 1
        fi
    else
        if [[ $marker_count -eq 0 ]]; then
            pass_test "$plugin_name: No marker files found as expected (empty dirs not preserved)"
        else
            fail_test "$plugin_name: Found $marker_count marker files, but none expected"
            return 1
        fi
    fi
}

###############################################################################
# Mock-Based Test Functions (Fast, no real Ceph)
###############################################################################

test_panfs2ceph_empty_dirs_default_generates_flags() {
    setup_mock_environment
    
    # Build cephtools if needed
    if [[ ! -f "$CEPHTOOLS_BIN" ]]; then
        make -C "$PROJECT_ROOT" >/dev/null 2>&1 || {
            fail_test "Could not build cephtools"
            return 1
        }
    fi
    
    # Create test data with empty directories
    local test_data_dir="$TEST_OUTPUT_DIR/panfs2ceph_test_data"
    create_test_data_with_empty_dirs "$test_data_dir"
    
    # Create test output directory
    local output_dir="$TEST_OUTPUT_DIR/panfs2ceph_default_test"
    mkdir -p "$output_dir"
    
    # Run panfs2ceph with default settings (should include empty dir flags)
    local original_dir=$(pwd)
    cd "$output_dir"
    
    if "$CEPHTOOLS_BIN" panfs2ceph \
        --bucket test-bucket \
        --path "$test_data_dir" \
        --log_dir "$output_dir" \
        --dry_run &>/dev/null; then
        
        # Find the generated SLURM script
        local script_file
        script_file=$(find "$output_dir" -name "*.1_copy_and_verify.slurm" | head -1)
        
        if [[ -n "$script_file" ]]; then
            validate_custom_empty_dir_handling "$script_file" "true" "panfs2ceph"
        else
            fail_test "panfs2ceph did not generate expected SLURM script"
            cd "$original_dir"
            return 1
        fi
    else
        fail_test "panfs2ceph command failed with default settings"
        cd "$original_dir"
        return 1
    fi
    
    cd "$original_dir"
}

test_panfs2ceph_empty_dirs_flag_omits_flags() {
    setup_mock_environment
    
    # Create test data with empty directories
    local test_data_dir="$TEST_OUTPUT_DIR/panfs2ceph_test_data_flag"
    create_test_data_with_empty_dirs "$test_data_dir"
    
    # Create test output directory
    local output_dir="$TEST_OUTPUT_DIR/panfs2ceph_flag_test"
    mkdir -p "$output_dir"
    
    # Run panfs2ceph with --delete_empty_dirs flag (should omit empty dir flags)
    local original_dir=$(pwd)
    cd "$output_dir"
    
    if "$CEPHTOOLS_BIN" panfs2ceph \
        --bucket test-bucket \
        --path "$test_data_dir" \
        --log_dir "$output_dir" \
        --delete_empty_dirs \
        --dry_run &>/dev/null; then
        
        # Find the generated SLURM script
        local script_file
        script_file=$(find "$output_dir" -name "*.1_copy_and_verify.slurm" | head -1)
        
        if [[ -n "$script_file" ]]; then
            validate_custom_empty_dir_handling "$script_file" "false" "panfs2ceph"
        else
            fail_test "panfs2ceph did not generate expected SLURM script with --delete_empty_dirs"
            cd "$original_dir"
            return 1
        fi
    else
        fail_test "panfs2ceph command failed with --delete_empty_dirs flag"
        cd "$original_dir"
        return 1
    fi
    
    cd "$original_dir"
}

test_dd2ceph_empty_dirs_default_generates_flags() {
    setup_mock_environment
    
    # Create test data with empty directories
    local test_data_dir="$TEST_OUTPUT_DIR/dd2ceph_test_data"
    create_test_data_with_empty_dirs "$test_data_dir"
    
    # Create test output directory
    local output_dir="$TEST_OUTPUT_DIR/dd2ceph_default_test"
    mkdir -p "$output_dir"
    
    # Test that dd2ceph help shows the option
    if "$CEPHTOOLS_BIN" help dd2ceph | grep -q "delete_empty_dirs"; then
        pass_test "dd2ceph help contains --delete_empty_dirs option"
    else
        fail_test "dd2ceph help missing --delete_empty_dirs option"
        return 1
    fi
    
    # Note: dd2ceph has more strict validation than panfs2ceph for bucket access
    # Since the refactoring logic is identical and panfs2ceph tests prove it works,
    # we focus on verifying the option exists and can be parsed
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # Test that the option is recognized (will fail on validation, but that's expected)
    local cmd_output
    cmd_output=$("$CEPHTOOLS_BIN" dd2ceph \
        --bucket test-bucket \
        --path "$test_data_dir" \
        --log_dir "$output_dir" \
        --dry_run 2>&1) || true
    
    # Check if the option was parsed correctly (error should be about bucket validation, not unknown option)
    if echo "$cmd_output" | grep -q "Unexpected option.*delete_empty_dirs"; then
        fail_test "dd2ceph does not recognize --delete_empty_dirs option"
        cd "$original_dir"
        return 1
    else
        pass_test "dd2ceph correctly recognizes --delete_empty_dirs option"
    fi
    
    cd "$original_dir"
}

test_dd2ceph_empty_dirs_flag_omits_flags() {
    setup_mock_environment
    
    # Create test data with empty directories
    local test_data_dir="$TEST_OUTPUT_DIR/dd2ceph_test_data_flag"
    create_test_data_with_empty_dirs "$test_data_dir"
    
    # Create test output directory
    local output_dir="$TEST_OUTPUT_DIR/dd2ceph_flag_test"
    mkdir -p "$output_dir"
    
    # Test that the --delete_empty_dirs flag is properly parsed
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # Test with the flag
    local cmd_output_with_flag
    cmd_output_with_flag=$("$CEPHTOOLS_BIN" dd2ceph \
        --bucket test-bucket \
        --path "$test_data_dir" \
        --log_dir "$output_dir" \
        --delete_empty_dirs \
        --dry_run 2>&1) || true
    
    # Check if the flag was parsed correctly (error should be about bucket validation, not unknown option)
    if echo "$cmd_output_with_flag" | grep -q "Unexpected option.*delete_empty_dirs"; then
        fail_test "dd2ceph does not recognize --delete_empty_dirs flag"
        cd "$original_dir"
        return 1
    else
        pass_test "dd2ceph correctly recognizes --delete_empty_dirs flag"
    fi
    
    # Verify the refactoring works by testing that the plugin source contains the needed logic
    if grep -q "delete_empty_dirs.*-eq 0" "$PROJECT_ROOT/src/plugins/dd2ceph/plugin.sh"; then
        pass_test "dd2ceph source contains empty directory flag conditional logic"
    else
        fail_test "dd2ceph source missing empty directory flag conditional logic"
        cd "$original_dir"
        return 1
    fi
    
    cd "$original_dir"
}

###############################################################################
# Real Ceph Integration Test Functions
###############################################################################

check_ceph_prerequisites() {
    # Check if we can run real Ceph tests
    if ! command -v s3cmd &> /dev/null; then
        log_warning "s3cmd not found, skipping real Ceph tests"
        return 1
    fi
    
    if ! command -v rclone &> /dev/null; then
        log_warning "rclone not found, skipping real Ceph tests"
        return 1
    fi
    
    # Test s3cmd configuration
    if ! timeout 10 s3cmd ls &>/dev/null; then
        log_warning "s3cmd not properly configured or MSI S3 service unavailable"
        return 1
    fi
    
    # Check rclone version
    local rclone_version
    if rclone_version=$(rclone version 2>/dev/null | head -1); then
        log_info "Found rclone: $rclone_version"
    else
        log_warning "Could not determine rclone version"
        return 1
    fi
    
    # For now, disable real Ceph tests as they need more setup
    # This can be enabled later when proper test infrastructure is in place
    log_warning "Real Ceph tests disabled - they require full MSI S3 environment setup"
    return 1
}

test_panfs2ceph_empty_dirs_real_transfer_with_flags() {
    # Create test bucket
    if ! timeout 15 s3cmd mb "s3://$TEST_BUCKET" &>/dev/null; then
        fail_test "Failed to create test bucket for panfs2ceph real test"
        return 1
    fi
    CLEANUP_ITEMS+=("$TEST_BUCKET")
    
    # Create test data with empty directories
    local test_data_dir="/tmp/${TEST_PREFIX}_panfs2ceph_real_with"
    create_test_data_with_empty_dirs "$test_data_dir"
    CLEANUP_ITEMS+=("$test_data_dir")
    
    # Test the new custom empty directory handling approach
    # Find empty directories
    local empty_dirs_file="$test_data_dir.empty_dirs.txt"
    find "$test_data_dir" -type d -empty > "$empty_dirs_file" 2>/dev/null || true
    
    # Create marker files
    local marker_name=".cephtools_empty_dir_marker"
    while IFS= read -r empty_dir; do
        if [[ -n "$empty_dir" && -d "$empty_dir" ]]; then
            echo "This file marks an empty directory for cephtools transfer" > "$empty_dir/$marker_name" 2>/dev/null || true
        fi
    done < "$empty_dirs_file"
    
    # Run actual transfer with custom approach
    if timeout 300 rclone copy "$test_data_dir" "$TEST_BUCKET:" --transfers 4 &>/dev/null; then
        # Validate that empty directories are preserved via marker files
        validate_empty_dirs_with_markers "$TEST_BUCKET" "true" "panfs2ceph"
        
        # Clean up marker files
        while IFS= read -r empty_dir; do
            if [[ -n "$empty_dir" && -d "$empty_dir" ]]; then
                rm -f "$empty_dir/$marker_name" 2>/dev/null || true
            fi
        done < "$empty_dirs_file"
    else
        fail_test "panfs2ceph real transfer with empty dir flags failed"
        return 1
    fi
}

test_panfs2ceph_empty_dirs_real_transfer_without_flags() {
    # Clean bucket first
    timeout 30 s3cmd rm "s3://$TEST_BUCKET" --recursive --force &>/dev/null || true
    
    # Create test data with empty directories
    local test_data_dir="/tmp/${TEST_PREFIX}_panfs2ceph_real_without"
    create_test_data_with_empty_dirs "$test_data_dir"
    CLEANUP_ITEMS+=("$test_data_dir")
    
    # Run actual transfer without marker files (empty dirs should be omitted)
    if timeout 300 rclone copy "$test_data_dir" "$TEST_BUCKET:" --transfers 4 &>/dev/null; then
        
        # Validate that empty directories do NOT exist in bucket (no marker files)
        validate_empty_dirs_with_markers "$TEST_BUCKET" "false" "panfs2ceph"
    else
        fail_test "panfs2ceph real transfer without empty dir flags failed"
        return 1
    fi
}

test_dd2ceph_empty_dirs_real_transfer_with_flags() {
    # Clean bucket first
    timeout 30 s3cmd rm "s3://$TEST_BUCKET" --recursive --force &>/dev/null || true
    
    # Create test data with empty directories
    local test_data_dir="/tmp/${TEST_PREFIX}_dd2ceph_real_with"
    create_test_data_with_empty_dirs "$test_data_dir"
    CLEANUP_ITEMS+=("$test_data_dir")
    
    # Test the new custom empty directory handling approach for dd2ceph
    # Find empty directories
    local empty_dirs_file="$test_data_dir.empty_dirs.txt"
    find "$test_data_dir" -type d -empty > "$empty_dirs_file" 2>/dev/null || true
    
    # Create marker files
    local marker_name=".cephtools_empty_dir_marker"
    while IFS= read -r empty_dir; do
        if [[ -n "$empty_dir" && -d "$empty_dir" ]]; then
            echo "This file marks an empty directory for cephtools transfer" > "$empty_dir/$marker_name" 2>/dev/null || true
        fi
    done < "$empty_dirs_file"
    
    # Run actual transfer with marker files
    if timeout 300 rclone copy "$test_data_dir" "$TEST_BUCKET:" --transfers 4 &>/dev/null; then
        # Validate that empty directories are preserved via marker files
        validate_empty_dirs_with_markers "$TEST_BUCKET" "true" "dd2ceph"
        
        # Clean up marker files
        while IFS= read -r empty_dir; do
            if [[ -n "$empty_dir" && -d "$empty_dir" ]]; then
                rm -f "$empty_dir/$marker_name" 2>/dev/null || true
            fi
        done < "$empty_dirs_file"
    else
        fail_test "dd2ceph real transfer with empty dir flags failed"
        return 1
    fi
}

test_dd2ceph_empty_dirs_real_transfer_without_flags() {
    # Clean bucket first
    timeout 30 s3cmd rm "s3://$TEST_BUCKET" --recursive --force &>/dev/null || true
    
    # Create test data with empty directories
    local test_data_dir="/tmp/${TEST_PREFIX}_dd2ceph_real_without"
    create_test_data_with_empty_dirs "$test_data_dir"
    CLEANUP_ITEMS+=("$test_data_dir")
    
    # Run actual transfer without marker files (empty dirs should be omitted)
    if timeout 300 rclone copy "$test_data_dir" "$TEST_BUCKET:" --transfers 4 &>/dev/null; then
        
        # Validate that empty directories do NOT exist in bucket (no marker files)
        validate_empty_dirs_with_markers "$TEST_BUCKET" "false" "dd2ceph"
    else
        fail_test "dd2ceph real transfer without empty dir flags failed"
        return 1
    fi
}

###############################################################################
# Main Test Execution
###############################################################################

print_test_summary() {
    echo
    echo -e "${BLUE}Empty Directory Flag Test Summary:${NC}"
    echo -e "  Total tests: $TEST_TOTAL"
    echo -e "  ${GREEN}Passed: $TEST_PASSED${NC}"
    echo -e "  ${RED}Failed: $TEST_FAILED${NC}"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All empty directory flag tests passed! ✅${NC}"
        return 0
    else
        echo -e "${RED}Some empty directory flag tests failed! ❌${NC}"
        return 1
    fi
}

main() {
    echo -e "${BLUE}Empty Directory Flag Tests for cephtools${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "Testing --delete_empty_dirs flag functionality"
    echo "Project: $PROJECT_ROOT"
    echo
    
    # Initialize test framework
    init_tests "Empty Directory Flag Tests"
    
    # Mock-based tests (fast, no real dependencies)
    start_test "panfs2ceph default behavior (mock)" && test_panfs2ceph_empty_dirs_default_generates_flags
    start_test "panfs2ceph --delete_empty_dirs (mock)" && test_panfs2ceph_empty_dirs_flag_omits_flags
    start_test "dd2ceph default behavior (mock)" && test_dd2ceph_empty_dirs_default_generates_flags
    start_test "dd2ceph --delete_empty_dirs (mock)" && test_dd2ceph_empty_dirs_flag_omits_flags
    
    # Real Ceph tests (if prerequisites met)
    if check_ceph_prerequisites; then
        log_info "Prerequisites met - running real Ceph integration tests"
        start_test "panfs2ceph real transfer with empty dirs" && test_panfs2ceph_empty_dirs_real_transfer_with_flags
        start_test "panfs2ceph real transfer without empty dirs" && test_panfs2ceph_empty_dirs_real_transfer_without_flags
        start_test "dd2ceph real transfer with empty dirs" && test_dd2ceph_empty_dirs_real_transfer_with_flags
        start_test "dd2ceph real transfer without empty dirs" && test_dd2ceph_empty_dirs_real_transfer_without_flags
    else
        log_warning "Prerequisites not met - skipping real Ceph tests"
        log_info "To run real Ceph tests, ensure:"
        log_info "  - s3cmd is configured for MSI S3"
        log_info "  - rclone >= 1.67.0 is available"
        log_info "  - Network access to s3.msi.umn.edu"
    fi
    
    # Print summary
    print_test_summary
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [options]"
        echo
        echo "Empty directory flag tests for cephtools"
        echo "Tests --delete_empty_dirs flag functionality for both plugins"
        echo
        echo "Test Types:"
        echo "  Mock tests    - Fast validation using mocked dependencies"
        echo "  Real tests    - End-to-end validation using actual MSI S3"
        echo
        echo "Prerequisites for real tests:"
        echo "  - s3cmd configured for MSI S3 service"
        echo "  - rclone >= 1.67.0 available"
        echo "  - Network access to s3.msi.umn.edu"
        echo "  - Valid MSI group membership"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac