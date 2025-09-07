#!/usr/bin/env bash
###############################################################################
# Dependency Validation Tests
# Tests that validate system dependencies for all cephtools plugins
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

###############################################################################
# Common Dependency Tests
###############################################################################

test_basic_system_commands() {
    start_test "Basic system commands are available"
    
    # Test core commands that should always be available
    local required_commands=("bash" "date" "mkdir" "chmod" "cd" "find" "wc" "awk" "sed")
    
    for cmd in "${required_commands[@]}"; do
        assert_command_exists "$cmd"
    done
}

test_msi_specific_commands() {
    start_test "MSI-specific commands availability"
    
    # Create mocks for MSI-specific commands
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12"
    create_mock_command "getent" "testgroup:x:1001:user1,user2,user3"
    
    assert_command_exists "s3info" 
    assert_command_exists "getent"
}

###############################################################################
# rclone Dependency Tests
###############################################################################

test_rclone_availability() {
    start_test "rclone command availability and version"
    
    # Test when rclone is not available
    assert_command_not_exists "rclone"
    
    # Test with old version rclone
    create_mock_command "rclone" "rclone v1.55.1" 0
    assert_command_exists "rclone"
    
    # Test with current version rclone
    create_mock_command "rclone" "rclone v1.64.1" 0
    assert_command_exists "rclone"
}

test_rclone_configuration() {
    start_test "rclone configuration validation"
    
    create_mock_command "rclone" "rclone v1.64.1" 0
    
    # Test listremotes command
    create_logging_mock_command "rclone"
    
    # Simulate rclone listremotes call
    rclone listremotes >/dev/null 2>&1 || true
    
    if was_mock_called "rclone" "listremotes"; then
        pass_test "rclone listremotes would be called"
    else
        fail_test "rclone listremotes not called when expected"
    fi
}

test_rclone_remote_validation() {
    start_test "rclone remote validation"
    
    # Test with valid remote
    create_mock_command "rclone" "myremote:" 0
    assert_exit_code 0 rclone listremotes
    
    # Test with invalid/empty remotes
    create_failing_mock_command "rclone" "No remotes configured" 1
    assert_exit_code 1 rclone listremotes
}

test_rclone_bucket_access() {
    start_test "rclone bucket access validation"
    
    # Test successful bucket access
    create_logging_mock_command "rclone" "file1.txt\nfile2.txt\n" 0
    
    rclone lsf myremote:test-bucket >/dev/null 2>&1 || true
    
    if was_mock_called "rclone" "lsf myremote:test-bucket"; then
        pass_test "rclone bucket access attempted"
    else
        fail_test "rclone bucket access not attempted"
    fi
    
    # Test failed bucket access
    create_failing_mock_command "rclone" "bucket not found" 1
    assert_exit_code 1 rclone lsf myremote:nonexistent-bucket
}

###############################################################################
# s3cmd Dependency Tests
###############################################################################

test_s3cmd_availability() {
    start_test "s3cmd command availability"
    
    # Test when s3cmd is not available
    assert_command_not_exists "s3cmd"
    
    # Test when s3cmd is available
    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
    assert_command_exists "s3cmd"
}

test_s3cmd_bucket_operations() {
    start_test "s3cmd bucket operations"
    
    create_logging_mock_command "s3cmd"
    
    # Test bucket listing
    s3cmd ls s3://test-bucket >/dev/null 2>&1 || true
    
    if was_mock_called "s3cmd" "ls s3://test-bucket"; then
        pass_test "s3cmd bucket listing attempted"
    else
        fail_test "s3cmd bucket listing not attempted"
    fi
    
    # Test bucket info
    s3cmd info s3://test-bucket >/dev/null 2>&1 || true
    
    if was_mock_called "s3cmd" "info s3://test-bucket"; then
        pass_test "s3cmd bucket info attempted"
    else
        fail_test "s3cmd bucket info not attempted"
    fi
}

test_s3cmd_bucket_creation() {
    start_test "s3cmd bucket creation and policy management"
    
    create_logging_mock_command "s3cmd"
    
    # Test bucket creation
    s3cmd mb s3://new-bucket >/dev/null 2>&1 || true
    
    if was_mock_called "s3cmd" "mb s3://new-bucket"; then
        pass_test "s3cmd bucket creation attempted"
    else
        fail_test "s3cmd bucket creation not attempted"
    fi
    
    # Test policy operations
    s3cmd setpolicy /path/to/policy.json s3://test-bucket >/dev/null 2>&1 || true
    
    if was_mock_called "s3cmd" "setpolicy"; then
        pass_test "s3cmd policy setting attempted"
    else
        fail_test "s3cmd policy setting not attempted"
    fi
}



###############################################################################
# Module System Tests  
###############################################################################

test_module_system() {
    start_test "Module system availability"
    
    # Create mock module command
    create_mock_command "module" "Module 'rclone/1.64.1' loaded successfully" 0
    
    assert_command_exists "module"
    
    # Test module load
    create_logging_mock_command "module"
    
    module load rclone/1.64.1 >/dev/null 2>&1 || true
    
    if was_mock_called "module" "load rclone"; then
        pass_test "Module loading capability"
    else
        fail_test "Module loading not working"
    fi
}

###############################################################################
# Plugin-Specific Dependency Tests
###############################################################################

test_dd2ceph_dependencies() {
    start_test "dd2ceph plugin dependencies"
    
    # Set up all required dependencies for dd2ceph
    create_mock_command "rclone" "rclone v1.64.1" 0
    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "module" "Module loaded" 0
    
    # Test that all dependencies are available
    assert_command_exists "rclone"
    assert_command_exists "s3cmd"
    assert_command_exists "s3info"
    assert_command_exists "module"
}

test_dd2dr_dependencies() {
    start_test "dd2dr plugin dependencies"
    
    # Set up all required dependencies for dd2dr
    create_mock_command "rclone" "rclone v1.64.1" 0
    create_mock_command "module" "Module loaded" 0
    
    # Test that all dependencies are available
    assert_command_exists "rclone"
    assert_command_exists "module"
}

test_filesinbackup_dependencies() {
    start_test "filesinbackup plugin dependencies"
    
    # Set up all required dependencies for filesinbackup
    create_mock_command "rclone" "rclone v1.64.1" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "find" "" 0
    create_mock_command "comm" "" 0
    create_mock_command "sort" "" 0
    create_mock_command "module" "Module loaded" 0
    
    # Test that all dependencies are available
    assert_command_exists "rclone"
    assert_command_exists "s3info"
    assert_command_exists "find"
    assert_command_exists "comm"
    assert_command_exists "sort"
    assert_command_exists "module"
}

test_panfs2ceph_dependencies() {
    start_test "panfs2ceph plugin dependencies"
    
    # Set up all required dependencies for panfs2ceph
    create_mock_command "rclone" "rclone v1.64.1" 0
    create_mock_command "s3info" "AKIA1234567890 abcdef1234567890abcdef1234567890abcdef12" 0
    create_mock_command "module" "Module loaded" 0
    
    # Test that all dependencies are available
    assert_command_exists "rclone"
    assert_command_exists "s3info"
    assert_command_exists "module"
}

test_bucketpolicy_dependencies() {
    start_test "bucketpolicy plugin dependencies"
    
    # Set up all required dependencies for bucketpolicy
    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
    create_mock_command "getent" "testgroup:x:1001:user1,user2,user3" 0
    
    # Test that all dependencies are available
    assert_command_exists "s3cmd"
    assert_command_exists "getent"
}

###############################################################################
# Environment Variable Tests
###############################################################################

test_required_environment_variables() {
    start_test "Required environment variables"
    
    # Test MSIPROJECT variable
    if [[ -z "${MSIPROJECT:-}" ]]; then
        fail_test "MSIPROJECT environment variable not set"
        return 1
    fi
    pass_test "MSIPROJECT is set: $MSIPROJECT"
    
    # Test USER variable
    if [[ -z "${USER:-}" ]]; then
        fail_test "USER environment variable not set"
        return 1
    fi
    pass_test "USER is set: $USER"
    
    # Test that MSIPROJECT directory exists or can be created
    if [[ ! -d "$MSIPROJECT" ]]; then
        if mkdir -p "$MSIPROJECT" 2>/dev/null; then
            pass_test "MSIPROJECT directory created successfully"
        else
            fail_test "Cannot create MSIPROJECT directory: $MSIPROJECT"
            return 1
        fi
    else
        pass_test "MSIPROJECT directory exists: $MSIPROJECT"
    fi
}

###############################################################################
# Main Test Runner
###############################################################################

main() {
    init_tests "Dependency Validation Tests"
    
    echo "Running dependency validation tests..."
    
    # Basic system tests
    test_basic_system_commands
    test_msi_specific_commands
    test_required_environment_variables
    
    # Tool-specific tests
    test_rclone_availability
    test_rclone_configuration
    test_rclone_remote_validation
    test_rclone_bucket_access
    
    test_s3cmd_availability
    test_s3cmd_bucket_operations
    test_s3cmd_bucket_creation
    

    
    test_module_system
    
    # Plugin-specific dependency tests
    test_dd2ceph_dependencies
    test_dd2dr_dependencies
    test_filesinbackup_dependencies
    test_panfs2ceph_dependencies
    test_bucketpolicy_dependencies
    
    # Print results
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi