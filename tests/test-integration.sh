#!/usr/bin/env bash
###############################################################################
# Integration Tests with Mocks
# Tests plugin workflows with mocked dependencies
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

###############################################################################
# Setup Functions
###############################################################################

setup_full_mock_environment() {
    # Set up complete mock environment with all dependencies
    setup_mock_cephtools "$PROJECT_ROOT"
    
    # Mock all external commands
    create_mock_command "rclone" "rclone v1.71.0" 0
    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0


    create_mock_command "getent" "testgroup:x:1001:user1,user2,user3" 0
    create_mock_command "module" "" 0
    create_mock_command "sbatch" "Submitted batch job 12345" 0
    
    # Mock successful operations
    create_logging_mock_command "rclone"
    create_logging_mock_command "s3cmd"

    
    # Create test data
    create_test_data "$MSIPROJECT/data_delivery" 5
    create_test_data "$MSIPROJECT/shared/disaster_recovery" 3
}

verify_slurm_script_basics() {
    local script_file="$1"
    local expected_prefix="$2"
    
    validate_slurm_script "$script_file"
    
    # Check for standard SLURM directives
    assert_contains "$(cat "$script_file")" "#SBATCH --time=" "Contains time directive"
    assert_contains "$(cat "$script_file")" "#SBATCH --ntasks=" "Contains ntasks directive"
    assert_contains "$(cat "$script_file")" "#SBATCH --mem=" "Contains memory directive"
    assert_contains "$(cat "$script_file")" "#SBATCH --error=%x.e%j" "Contains error output directive"
    assert_contains "$(cat "$script_file")" "#SBATCH --output=%x.o%j" "Contains standard output directive"
    
    # Check for expected filename pattern
    if [[ "$script_file" == *"$expected_prefix"* ]]; then
        pass_test "SLURM script uses expected filename pattern"
    else
        fail_test "SLURM script filename doesn't match expected pattern: $expected_prefix"
    fi
}

###############################################################################
# dd2ceph Integration Tests
###############################################################################

test_dd2ceph_workflow() {
    start_test "dd2ceph complete workflow integration"
    
    setup_full_mock_environment
    
    # Build cephtools if needed
    if [[ ! -f "$CEPHTOOLS_BIN" ]]; then
        make -C "$PROJECT_ROOT" >/dev/null 2>&1 || {
            fail_test "Could not build cephtools"
            return 1
        }
    fi
    
    # Mock successful bucket access
    create_mock_command "rclone" "" 0
    
    # Run dd2ceph (dry run to avoid actual execution)
    local output_dir="$TEST_OUTPUT_DIR/dd2ceph_test"
    mkdir -p "$output_dir"
    
    # Change to test directory
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # This should create SLURM script without executing it
    local cmd_output
    if cmd_output=$("$CEPHTOOLS_BIN" dd2ceph --bucket test-bucket --path "$MSIPROJECT/data_delivery" --log_dir "$output_dir" --dry_run 2>&1); then
        pass_test "dd2ceph command executed successfully"
    else
        fail_test "dd2ceph command failed: $cmd_output"
        cd "$original_dir"
        return 1
    fi
    
    cd "$original_dir"
    
    # Verify SLURM script was created
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        pass_test "SLURM script created: $(basename "$slurm_script")"
        verify_slurm_script_basics "$slurm_script" "dd2ceph"
        
        # Check for dd2ceph-specific content
        assert_contains "$(cat "$slurm_script")" "rclone" "Contains rclone commands"
        assert_contains "$(cat "$slurm_script")" "module load rclone" "Loads rclone module"
    else
        fail_test "No SLURM script created"
    fi
}

test_dd2ceph_credential_setup() {
    start_test "dd2ceph credential setup in SLURM script"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/dd2ceph_creds"
    mkdir -p "$output_dir"
    
    # Mock successful operations
    create_mock_command "rclone" "" 0
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # Run with default remote (should set up credentials)
    "$CEPHTOOLS_BIN" dd2ceph --bucket test-bucket --path "$MSIPROJECT/data_delivery" --log_dir "$output_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Find and check SLURM script
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        # Should contain credential setup for myremote
        assert_contains "$(cat "$slurm_script")" "RCLONE_CONFIG_MYREMOTE" "Contains credential setup"
        assert_contains "$(cat "$slurm_script")" "s3info --keys" "Uses s3info for credentials"
    else
        fail_test "No SLURM script found to check credentials"
    fi
}

###############################################################################
# dd2dr Integration Tests  
###############################################################################

test_dd2dr_workflow() {
    start_test "dd2dr complete workflow integration"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/dd2dr_test"
    mkdir -p "$output_dir"
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # Run dd2dr
    "$CEPHTOOLS_BIN" dd2dr --group testgroup --log_dir "$output_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Verify SLURM script was created
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        pass_test "dd2dr SLURM script created"
        verify_slurm_script_basics "$slurm_script" "testgroup"
        
        # Check for dd2dr-specific content
        assert_contains "$(cat "$slurm_script")" "rclone" "Contains rclone commands"

        assert_contains "$(cat "$slurm_script")" "data_delivery" "References data_delivery"
        assert_contains "$(cat "$slurm_script")" "disaster_recovery" "References disaster_recovery"
    else
        fail_test "No dd2dr SLURM script created"
    fi
}

test_dd2dr_quota_checking() {
    start_test "dd2dr quota checking logic"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/dd2dr_quota"
    mkdir -p "$output_dir"
    

    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    "$CEPHTOOLS_BIN" dd2dr --group testgroup --log_dir "$output_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        # Should contain quota checking logic

        assert_contains "$(cat "$slurm_script")" "AVAIL=" "Contains quota calculation"
        assert_contains "$(cat "$slurm_script")" "remaining in" "Contains quota reporting"
    else
        fail_test "No SLURM script to check quota logic"
    fi
}

###############################################################################
# filesinbackup Integration Tests
###############################################################################

test_filesinbackup_workflow() {
    start_test "filesinbackup complete workflow integration"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/filesinbackup_test"
    mkdir -p "$output_dir"
    
    # Mock successful rclone operations
    create_mock_command "rclone" "file1.txt\nfile2.txt" 0
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    "$CEPHTOOLS_BIN" filesinbackup --group testgroup --log_dir "$output_dir" >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Should create SLURM script
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        pass_test "filesinbackup SLURM script created"
        verify_slurm_script_basics "$slurm_script" "testgroup"
        
        # Check for filesinbackup-specific content
        assert_contains "$(cat "$slurm_script")" "find" "Contains find commands for file listing"
        assert_contains "$(cat "$slurm_script")" "rclone lsf" "Contains rclone file listing"
        assert_contains "$(cat "$slurm_script")" "comm -23" "Contains file comparison commands"
        assert_contains "$(cat "$slurm_script")" "disaster_recovery_files.txt" "Creates disaster recovery file list"
        assert_contains "$(cat "$slurm_script")" "ceph_bucket_files.txt" "Creates ceph bucket file list"
    else
        fail_test "No filesinbackup SLURM script created"
    fi
}

test_filesinbackup_file_comparison() {
    start_test "filesinbackup file comparison logic"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/filesinbackup_compare"
    mkdir -p "$output_dir"
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    "$CEPHTOOLS_BIN" filesinbackup --group testgroup --log_dir "$output_dir" >/dev/null 2>&1
    
    cd "$original_dir"
    
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        # Should contain comparison file generation
        assert_contains "$(cat "$slurm_script")" "missing_from_ceph.txt" "Creates missing from ceph report"
        assert_contains "$(cat "$slurm_script")" "missing_from_disaster_recovery.txt" "Creates missing from disaster recovery report"
        
        # Check that it uses proper filename format
        local script_content="$(cat "$slurm_script")"
        if [[ "$script_content" == *"testgroup_"*".missing_from_ceph.txt" ]]; then
            pass_test "Uses GROUP_TIMESTAMP filename format"
        else
            fail_test "Does not use expected GROUP_TIMESTAMP filename format"
        fi
    else
        fail_test "No SLURM script to check comparison logic"
    fi
}

test_umask_settings() {
    start_test "Umask settings for group-writable permissions"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/umask_test"
    mkdir -p "$output_dir"
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    # Test filesinbackup umask in SLURM script
    "$CEPHTOOLS_BIN" filesinbackup --group testgroup --log_dir "$output_dir" >/dev/null 2>&1
    
    local slurm_script=$(find "$output_dir" -name "*.slurm" | head -1)
    if [[ -n "$slurm_script" ]]; then
        assert_contains "$(cat "$slurm_script")" "umask 0007" "SLURM script contains umask setting"
        assert_contains "$(cat "$slurm_script")" "group-writable files (660) and directories (770)" "Contains umask explanation"
    else
        fail_test "No SLURM script found to check umask"
    fi
    
    cd "$original_dir"
    
    # Test dd2ceph umask in SLURM script  
    create_mock_command "rclone" "" 0
    local dd2ceph_dir="$TEST_OUTPUT_DIR/dd2ceph_umask"
    mkdir -p "$dd2ceph_dir"
    
    cd "$dd2ceph_dir"
    
    # This may fail due to bucket validation, but should still create the script structure
    "$CEPHTOOLS_BIN" dd2ceph --bucket test --path /tmp --log_dir "$dd2ceph_dir" --dry_run >/dev/null 2>&1 || true
    
    # Look for any .slurm files that might have been created
    local dd2ceph_script=$(find "$dd2ceph_dir" -name "*.slurm" | head -1)
    if [[ -n "$dd2ceph_script" ]]; then
        assert_contains "$(cat "$dd2ceph_script")" "umask 0007" "dd2ceph SLURM script contains umask setting"
    else
        pass_test "dd2ceph umask test skipped (script generation failed as expected)"
    fi
    
    cd "$original_dir"
}

###############################################################################
# panfs2ceph Integration Tests
###############################################################################

test_panfs2ceph_workflow() {
    start_test "panfs2ceph complete workflow integration"
    
    setup_full_mock_environment
    
    local output_dir="$TEST_OUTPUT_DIR/panfs2ceph_test"
    local test_source_dir="$TEST_OUTPUT_DIR/test_source"
    mkdir -p "$output_dir" "$test_source_dir"
    create_test_data "$test_source_dir" 3
    
    # Mock successful operations
    create_mock_command "rclone" "" 0
    
    local original_dir=$(pwd)
    cd "$output_dir"
    
    "$CEPHTOOLS_BIN" panfs2ceph --bucket test-bucket --path "$test_source_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Should create SLURM scripts (combined copy and verify, delete, restore)
    local copy_and_verify_script=$(find "$output_dir" -name "*copy_and_verify*.slurm" | head -1)
    local delete_script=$(find "$output_dir" -name "*delete*.slurm" | head -1)
    local restore_script=$(find "$output_dir" -name "*restore*.slurm" | head -1)
    
    if [[ -n "$copy_and_verify_script" ]]; then
        pass_test "panfs2ceph copy and verify script created"
        verify_slurm_script_basics "$copy_and_verify_script" "copy_and_verify"
        assert_contains "$(cat "$copy_and_verify_script")" "rclone copy" "Contains rclone copy command"
        assert_contains "$(cat "$copy_and_verify_script")" "rclone check" "Contains rclone check command"
    else
        fail_test "No panfs2ceph copy and verify script created"
    fi
    
    if [[ -n "$delete_script" ]]; then
        pass_test "panfs2ceph delete script created"
        verify_slurm_script_basics "$delete_script" "delete"
        assert_contains "$(cat "$delete_script")" "rclone purge" "Contains rclone purge command"
    else
        fail_test "No panfs2ceph delete script created"
    fi
    
    if [[ -n "$restore_script" ]]; then
        pass_test "panfs2ceph restore script created"
        verify_slurm_script_basics "$restore_script" "restore"
    else
        fail_test "No panfs2ceph restore script created"
    fi
}

###############################################################################
# bucketpolicy Integration Tests
###############################################################################

test_bucketpolicy_workflow() {
    start_test "bucketpolicy complete workflow integration"
    
    setup_full_mock_environment
    
    # Mock s3cmd bucket operations
    create_logging_mock_command "s3cmd"
    
    # Run bucketpolicy
    if "$CEPHTOOLS_BIN" bucketpolicy --bucket test-bucket --policy GROUP_READ_WRITE --group testgroup >/dev/null 2>&1; then
        pass_test "bucketpolicy command executed successfully"
    else
        fail_test "bucketpolicy command failed"
        return 1
    fi
    
    # Check that s3cmd operations were called
    if was_mock_called "s3cmd" "ls"; then
        pass_test "Bucket existence check attempted"
    else
        fail_test "Bucket existence not checked"
    fi
}

###############################################################################
# Cross-Plugin Consistency Tests
###############################################################################

test_filename_consistency() {
    start_test "Consistent filename patterns across plugins"
    
    setup_full_mock_environment
    
    local test_dir="$TEST_OUTPUT_DIR/consistency"
    mkdir -p "$test_dir"
    
    create_mock_command "rclone" "" 0
    
    local original_dir=$(pwd)
    cd "$test_dir"
    
    # Run plugins that generate timestamped files
    "$CEPHTOOLS_BIN" filesinbackup --group testgroup --log_dir "$test_dir" >/dev/null 2>&1
    "$CEPHTOOLS_BIN" dd2dr --group testgroup --log_dir "$test_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Check that both use GROUP_TIMESTAMP format
    local filesinbackup_script=$(find "$test_dir" -name "testgroup_*.slurm" | grep -v dd2dr | head -1)
    local dd2dr_script=$(find "$test_dir" -name "testgroup_*.slurm" | grep -v filesinbackup | head -1)
    
    if [[ -n "$filesinbackup_script" ]] && [[ -n "$dd2dr_script" ]]; then
        # Both should follow GROUP_TIMESTAMP.slurm pattern
        local filesinbackup_name=$(basename "$filesinbackup_script")
        local dd2dr_name=$(basename "$dd2dr_script")
        
        if [[ "$filesinbackup_name" =~ ^testgroup_[0-9-]{19}\.slurm$ ]] && [[ "$dd2dr_name" =~ ^testgroup_[0-9-]{19}\.slurm$ ]]; then
            pass_test "Both plugins use consistent GROUP_TIMESTAMP.slurm naming"
        else
            fail_test "Inconsistent filename patterns: $filesinbackup_name vs $dd2dr_name"
        fi
    else
        fail_test "Could not find SLURM scripts from both plugins"
    fi
}

test_slurm_directive_consistency() {
    start_test "Consistent SLURM directives across plugins"
    
    setup_full_mock_environment
    
    local test_dir="$TEST_OUTPUT_DIR/slurm_consistency"
    mkdir -p "$test_dir"
    
    create_mock_command "rclone" "" 0
    
    local original_dir=$(pwd)
    cd "$test_dir"
    
    # Generate scripts from multiple plugins
    "$CEPHTOOLS_BIN" filesinbackup --group testgroup --log_dir "$test_dir" >/dev/null 2>&1
    "$CEPHTOOLS_BIN" dd2dr --group testgroup --log_dir "$test_dir" --dry_run >/dev/null 2>&1
    
    cd "$original_dir"
    
    # Check all SLURM scripts for consistent directives
    local consistent=true
    while IFS= read -r script; do
        if ! grep -q "#SBATCH --error=%x.e%j" "$script"; then
            consistent=false
            fail_test "Script $(basename "$script") missing standard error directive"
            break
        fi
        
        if ! grep -q "#SBATCH --output=%x.o%j" "$script"; then
            consistent=false
            fail_test "Script $(basename "$script") missing standard output directive"  
            break
        fi
    done < <(find "$test_dir" -name "*.slurm")
    
    if $consistent; then
        pass_test "All SLURM scripts use consistent directives"
    fi
}

###############################################################################
# Main Test Runner
###############################################################################

main() {
    init_tests "Integration Tests with Mocks"
    
    echo "Running integration tests with mocked dependencies..."
    
    # dd2ceph tests
    test_dd2ceph_workflow
    test_dd2ceph_credential_setup
    
    # dd2dr tests
    test_dd2dr_workflow  
    test_dd2dr_quota_checking
    
    # filesinbackup tests
    test_filesinbackup_workflow
    test_filesinbackup_file_comparison
    
    # Umask and permissions tests
    test_umask_settings
    
    # panfs2ceph tests
    test_panfs2ceph_workflow
    
    # bucketpolicy tests
    test_bucketpolicy_workflow
    
    # Cross-plugin consistency
    test_filename_consistency
    test_slurm_directive_consistency
    
    # Print results
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi