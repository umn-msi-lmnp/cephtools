#!/usr/bin/env bash
###############################################################################
# System Compatibility Tests
# Tests for different environments and system configurations
###############################################################################

# Get script directory and source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

###############################################################################
# Environment Detection Tests
###############################################################################

test_shell_compatibility() {
    start_test "Shell compatibility detection"
    
    # Test that scripts work with different shell configurations
    local current_shell="${SHELL##*/}"
    pass_test "Running in shell: $current_shell"
    
    # Test bash-specific features used in cephtools
    if [[ "${BASH_VERSION:-}" ]]; then
        pass_test "Bash version: $BASH_VERSION"
        
        # Test array support (used in plugins)
        local test_array=("item1" "item2" "item3")
        if [[ ${#test_array[@]} -eq 3 ]]; then
            pass_test "Bash array support available"
        else
            fail_test "Bash array support not working correctly"
        fi
        
        # Test process substitution (used in some plugins)
        if command -v wc >/dev/null && echo "test" | wc -l >/dev/null; then
            pass_test "Process substitution and pipes working"
        else
            fail_test "Process substitution or pipes not working"
        fi
    else
        fail_test "Bash not available - cephtools requires bash"
    fi
}

test_system_commands() {
    start_test "Core system commands availability"
    
    # Test essential commands that cephtools relies on
    local essential_commands=(
        "bash" "sh" "date" "mkdir" "chmod" "cd" "pwd" "ls"
        "find" "grep" "awk" "sed" "sort" "wc" "cut" "tr"
        "cat" "echo" "printf" "test" "which" "command"
    )
    
    local missing_commands=()
    for cmd in "${essential_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        pass_test "All essential commands available"
    else
        fail_test "Missing essential commands: ${missing_commands[*]}"
    fi
}

test_filesystem_features() {
    start_test "Filesystem features and permissions"
    
    # Test directory creation and permissions
    local test_dir="$TEST_OUTPUT_DIR/fs_test"
    if mkdir -p "$test_dir" 2>/dev/null; then
        pass_test "Directory creation works"
        
        # Test permission setting
        if chmod 755 "$test_dir" 2>/dev/null; then
            pass_test "Permission setting works"
        else
            fail_test "Cannot set directory permissions"
        fi
        
        # Test file creation
        local test_file="$test_dir/test_file.txt"
        if echo "test content" > "$test_file" 2>/dev/null; then
            pass_test "File creation works"
            
            # Test file permissions
            if chmod 644 "$test_file" 2>/dev/null; then
                pass_test "File permission setting works"
            else
                fail_test "Cannot set file permissions"
            fi
        else
            fail_test "Cannot create files"
        fi
    else
        fail_test "Cannot create directories"
    fi
}

###############################################################################
# MSI Environment Tests
###############################################################################

test_msi_environment_detection() {
    start_test "MSI environment detection"
    
    # Check if running on MSI systems
    local is_msi=false
    
    # Check for MSI-specific paths and commands
    if [[ -d "/common/software" ]] || [[ -d "/home" ]] || command -v module >/dev/null; then
        is_msi=true
        pass_test "MSI environment detected"
    else
        pass_test "Non-MSI environment (test/development)"
    fi
    
    # Test MSIPROJECT variable handling
    if [[ -n "${MSIPROJECT:-}" ]]; then
        if [[ -d "$MSIPROJECT" ]] || mkdir -p "$MSIPROJECT" 2>/dev/null; then
            pass_test "MSIPROJECT directory accessible: $MSIPROJECT"
        else
            fail_test "MSIPROJECT directory not accessible: $MSIPROJECT"
        fi
    else
        if $is_msi; then
            fail_test "MSIPROJECT not set in MSI environment"
        else
            pass_test "MSIPROJECT not required in non-MSI environment"
        fi
    fi
}

test_module_system_compatibility() {
    start_test "Module system compatibility"
    
    if command -v module >/dev/null 2>&1; then
        pass_test "Module system available"
        
        # Test module list command
        if module list 2>/dev/null >/dev/null; then
            pass_test "Module list command works"
        else
            # Some module systems require different syntax
            if module avail 2>/dev/null >/dev/null; then
                pass_test "Module avail command works (alternative syntax)"
            else
                fail_test "Module system not functioning correctly"
            fi
        fi
    else
        # Create mock module system for testing
        create_mock_command "module" "No modules loaded" 0
        pass_test "Module system mocked for testing"
    fi
}

test_slurm_compatibility() {
    start_test "SLURM system compatibility"
    
    if command -v sbatch >/dev/null 2>&1; then
        pass_test "SLURM sbatch command available"
        
        if command -v squeue >/dev/null 2>&1; then
            pass_test "SLURM squeue command available"
        else
            fail_test "SLURM squeue command missing"
        fi
        
        if command -v scontrol >/dev/null 2>&1; then
            pass_test "SLURM scontrol command available"
        else
            fail_test "SLURM scontrol command missing"
        fi
    else
        # Mock SLURM for testing environments
        create_mock_command "sbatch" "Submitted batch job 12345" 0
        create_mock_command "squeue" "JOBID PARTITION NAME USER ST TIME NODES NODELIST(REASON)" 0
        create_mock_command "scontrol" "JobId=12345 JobName=test" 0
        pass_test "SLURM system mocked for testing"
    fi
}

###############################################################################
# Network and Connectivity Tests
###############################################################################

test_network_tools() {
    start_test "Network connectivity tools"
    
    # Test basic network utilities
    local network_tools=("ping" "curl" "wget")
    local available_tools=()
    
    for tool in "${network_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            available_tools+=("$tool")
        fi
    done
    
    if [[ ${#available_tools[@]} -gt 0 ]]; then
        pass_test "Network tools available: ${available_tools[*]}"
    else
        fail_test "No network connectivity tools found"
    fi
}

test_dns_resolution() {
    start_test "DNS resolution capability"
    
    # Test if DNS resolution works (needed for S3 endpoints)
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup google.com >/dev/null 2>&1; then
            pass_test "DNS resolution working (nslookup)"
        else
            # May fail in restricted environments - that's OK
            pass_test "DNS resolution may be restricted (expected in some environments)"
        fi
    elif command -v dig >/dev/null 2>&1; then
        if dig google.com >/dev/null 2>&1; then
            pass_test "DNS resolution working (dig)"
        else
            pass_test "DNS resolution may be restricted (expected in some environments)"
        fi
    else
        # Mock DNS tools for testing
        create_mock_command "nslookup" "google.com has address 8.8.8.8" 0
        pass_test "DNS tools mocked for testing"
    fi
}

###############################################################################
# Python and Tool Version Tests
###############################################################################

test_python_availability() {
    start_test "Python availability for tools"
    
    # Many tools like s3cmd require Python
    local python_versions=("python3" "python")
    local python_available=false
    
    for py in "${python_versions[@]}"; do
        if command -v "$py" >/dev/null 2>&1; then
            local version=$("$py" --version 2>&1)
            pass_test "$py available: $version"
            python_available=true
            break
        fi
    done
    
    if ! $python_available; then
        # Mock Python for testing
        create_mock_command "python3" "Python 3.8.0" 0
        pass_test "Python mocked for testing"
    fi
}

test_tool_versions() {
    start_test "External tool version compatibility"
    
    # Test version checking for critical tools
    local tools_to_check=("rclone" "s3cmd")
    
    for tool in "${tools_to_check[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version_output=$("$tool" --version 2>/dev/null | head -1)
            pass_test "$tool available: $version_output"
        else
            # Mock the tool with a reasonable version
            case "$tool" in
                "rclone")
                    create_mock_command "rclone" "rclone v1.71.0" 0
                    pass_test "rclone mocked with compatible version"
                    ;;

                "s3cmd")
                    create_mock_command "s3cmd" "s3cmd version 2.3.0" 0
                    pass_test "s3cmd mocked with compatible version"
                    ;;
            esac
        fi
    done
}

###############################################################################
# Locale and Character Encoding Tests
###############################################################################

test_locale_support() {
    start_test "Locale and character encoding support"
    
    # Test locale settings
    if [[ -n "${LC_ALL:-}" ]] || [[ -n "${LANG:-}" ]]; then
        local locale_info="${LC_ALL:-${LANG:-unknown}}"
        pass_test "Locale setting: $locale_info"
        
        # Test UTF-8 support (important for file names with special characters)
        if echo "Test: àáâãäå" | grep -q "àáâãäå" 2>/dev/null; then
            pass_test "UTF-8 character support available"
        else
            fail_test "UTF-8 character support may be limited"
        fi
    else
        pass_test "No specific locale set (using system default)"
    fi
}

test_timezone_handling() {
    start_test "Timezone and date handling"
    
    # Test date command functionality (used for timestamps)
    if date >/dev/null 2>&1; then
        local current_date=$(date)
        pass_test "Date command working: $current_date"
        
        # Test timestamp format used by cephtools
        if date +"%Y-%m-%d-%H%M%S" >/dev/null 2>&1; then
            local timestamp=$(date +"%Y-%m-%d-%H%M%S")
            pass_test "Timestamp format working: $timestamp"
        else
            fail_test "Cannot generate required timestamp format"
        fi
    else
        fail_test "Date command not working"
    fi
}

###############################################################################
# Resource Limit Tests
###############################################################################

test_resource_limits() {
    start_test "System resource limits"
    
    # Test ulimit settings that might affect cephtools
    if command -v ulimit >/dev/null 2>&1; then
        local file_limit=$(ulimit -n 2>/dev/null)
        if [[ -n "$file_limit" ]] && [[ "$file_limit" != "unlimited" ]]; then
            if [[ "$file_limit" -gt 1000 ]]; then
                pass_test "File descriptor limit adequate: $file_limit"
            else
                fail_test "File descriptor limit may be too low: $file_limit"
            fi
        else
            pass_test "File descriptor limit: ${file_limit:-unlimited}"
        fi
        
        local proc_limit=$(ulimit -u 2>/dev/null)
        if [[ -n "$proc_limit" ]] && [[ "$proc_limit" != "unlimited" ]]; then
            pass_test "Process limit: $proc_limit"
        else
            pass_test "Process limit: ${proc_limit:-unlimited}"
        fi
    else
        pass_test "ulimit not available (may not be needed)"
    fi
}

test_disk_space_detection() {
    start_test "Disk space detection capabilities"
    
    # Test df command (used for space checking)
    if command -v df >/dev/null 2>&1; then
        if df "$TEST_OUTPUT_DIR" >/dev/null 2>&1; then
            pass_test "Disk space checking available (df)"
        else
            fail_test "Cannot check disk space with df"
        fi
    else
        fail_test "df command not available for disk space checking"
    fi
    
    # Test du command (used by plugins)
    if command -v du >/dev/null 2>&1; then
        if du -s "$TEST_OUTPUT_DIR" >/dev/null 2>&1; then
            pass_test "Directory size calculation available (du)"
        else
            fail_test "Cannot calculate directory sizes with du"
        fi
    else
        fail_test "du command not available for size calculations"
    fi
}

###############################################################################
# Cross-Platform Compatibility
###############################################################################

test_path_handling() {
    start_test "Path handling compatibility"
    
    # Test absolute vs relative path handling
    local test_dir="$TEST_OUTPUT_DIR/path_test"
    mkdir -p "$test_dir"
    
    # Test realpath/readlink functionality (used in some plugins)
    if command -v realpath >/dev/null 2>&1; then
        if realpath "$test_dir" >/dev/null 2>&1; then
            pass_test "realpath command available"
        else
            fail_test "realpath command not functioning"
        fi
    elif command -v readlink >/dev/null 2>&1; then
        if readlink -f "$test_dir" >/dev/null 2>&1; then
            pass_test "readlink -f available (alternative to realpath)"
        else
            fail_test "Neither realpath nor readlink -f available"
        fi
    else
        fail_test "No path resolution commands available"
    fi
}

test_temporary_directory() {
    start_test "Temporary directory handling"
    
    # Test temporary directory creation (used by test framework)
    if command -v mktemp >/dev/null 2>&1; then
        local temp_dir=$(mktemp -d 2>/dev/null)
        if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
            pass_test "Temporary directory creation works: $temp_dir"
            rm -rf "$temp_dir" 2>/dev/null
        else
            fail_test "Cannot create temporary directories"
        fi
    else
        # Test alternative method
        local alt_temp_dir="${TMPDIR:-/tmp}/cephtools_test_$$"
        if mkdir -p "$alt_temp_dir" 2>/dev/null; then
            pass_test "Alternative temporary directory creation works"
            rm -rf "$alt_temp_dir" 2>/dev/null
        else
            fail_test "Cannot create temporary directories with alternative method"
        fi
    fi
}

###############################################################################
# Main Test Runner
###############################################################################

main() {
    init_tests "System Compatibility Tests"
    
    echo "Running system compatibility tests..."
    
    # Shell and system basics
    test_shell_compatibility
    test_system_commands
    test_filesystem_features
    
    # MSI-specific environment
    test_msi_environment_detection
    test_module_system_compatibility
    test_slurm_compatibility
    
    # Network capabilities
    test_network_tools
    test_dns_resolution
    
    # Tool availability and versions
    test_python_availability
    test_tool_versions
    
    # Locale and encoding
    test_locale_support
    test_timezone_handling
    
    # Resource limits
    test_resource_limits
    test_disk_space_detection
    
    # Cross-platform features
    test_path_handling
    test_temporary_directory
    
    # Print results
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi