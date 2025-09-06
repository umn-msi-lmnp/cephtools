#!/usr/bin/env bash
###############################################################################
# Test Framework for cephtools
# Provides utilities for mocking, assertions, and test organization
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0

# Current test info
CURRENT_TEST=""
TEST_OUTPUT_DIR=""

###############################################################################
# Core Test Functions
###############################################################################

# Initialize test environment
init_tests() {
    local test_name="$1"
    echo -e "${BLUE}Initializing test suite: $test_name${NC}"
    
    # Create temporary test directory
    TEST_OUTPUT_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR
    
    # Set up mock environment
    export PATH="$TEST_OUTPUT_DIR/mock-bin:$PATH"
    mkdir -p "$TEST_OUTPUT_DIR/mock-bin"
    
    # Set test-specific environment variables
    export MSIPROJECT="$TEST_OUTPUT_DIR/mock-msiproject"
    export HOME="$TEST_OUTPUT_DIR/mock-home"
    mkdir -p "$MSIPROJECT" "$HOME"
    
    echo "Test environment: $TEST_OUTPUT_DIR"
}

# Clean up test environment
cleanup_tests() {
    if [[ -n "${TEST_OUTPUT_DIR:-}" ]] && [[ -d "$TEST_OUTPUT_DIR" ]]; then
        rm -rf "$TEST_OUTPUT_DIR"
    fi
}

# Start a new test
start_test() {
    local test_description="$1"
    CURRENT_TEST="$test_description"
    ((TEST_TOTAL++))
    echo -e "  ${YELLOW}Testing:${NC} $test_description"
}

# Mark test as passed
pass_test() {
    local message="${1:-}"
    ((TEST_PASSED++))
    if [[ -n "$message" ]]; then
        echo -e "    ${GREEN}✓${NC} $message"
    else
        echo -e "    ${GREEN}✓${NC} $CURRENT_TEST"
    fi
}

# Mark test as failed
fail_test() {
    local message="$1"
    ((TEST_FAILED++))
    echo -e "    ${RED}✗${NC} $CURRENT_TEST"
    echo -e "      ${RED}Error:${NC} $message"
    return 1
}

# Print test summary
print_test_summary() {
    echo
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "  Total tests: $TEST_TOTAL"
    echo -e "  ${GREEN}Passed: $TEST_PASSED${NC}"
    echo -e "  ${RED}Failed: $TEST_FAILED${NC}"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✅${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed! ❌${NC}"
        return 1
    fi
}

###############################################################################
# Mock Command Functions
###############################################################################

# Create a mock command that always succeeds
create_mock_command() {
    local cmd="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"
    
    cat > "$TEST_OUTPUT_DIR/mock-bin/$cmd" <<EOF
#!/bin/bash
if [[ -n "$output" ]]; then
    echo "$output"
fi
exit $exit_code
EOF
    chmod +x "$TEST_OUTPUT_DIR/mock-bin/$cmd"
}

# Create a mock command that fails
create_failing_mock_command() {
    local cmd="$1"
    local error_message="${2:-Command failed}"
    local exit_code="${3:-1}"
    
    cat > "$TEST_OUTPUT_DIR/mock-bin/$cmd" <<EOF
#!/bin/bash
echo "$error_message" >&2
exit $exit_code
EOF
    chmod +x "$TEST_OUTPUT_DIR/mock-bin/$cmd"
}

# Create a mock command that logs its invocation
create_logging_mock_command() {
    local cmd="$1"
    local output="${2:-}"
    local log_file="$TEST_OUTPUT_DIR/${cmd}.log"
    
    cat > "$TEST_OUTPUT_DIR/mock-bin/$cmd" <<EOF
#!/bin/bash
echo "\$0 \$*" >> "$log_file"
if [[ -n "$output" ]]; then
    echo "$output"
fi
exit 0
EOF
    chmod +x "$TEST_OUTPUT_DIR/mock-bin/$cmd"
}

# Check if a mock command was called
was_mock_called() {
    local cmd="$1"
    local expected_args="${2:-}"
    local log_file="$TEST_OUTPUT_DIR/${cmd}.log"
    
    if [[ ! -f "$log_file" ]]; then
        return 1
    fi
    
    if [[ -n "$expected_args" ]]; then
        grep -q "$expected_args" "$log_file"
    else
        return 0  # Just check if file exists
    fi
}

# Get mock command call count
get_mock_call_count() {
    local cmd="$1"
    local log_file="$TEST_OUTPUT_DIR/${cmd}.log"
    
    if [[ ! -f "$log_file" ]]; then
        echo "0"
        return
    fi
    
    wc -l < "$log_file"
}

###############################################################################
# Assertion Functions
###############################################################################

# Assert that a command exists
assert_command_exists() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail_test "Command '$cmd' not found"
        return 1
    fi
    pass_test "Command '$cmd' exists"
}

# Assert that a command doesn't exist
assert_command_not_exists() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        fail_test "Command '$cmd' unexpectedly found"
        return 1
    fi
    pass_test "Command '$cmd' correctly not found"
}

# Assert that a file exists
assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        fail_test "File '$file' does not exist"
        return 1
    fi
    pass_test "File '$file' exists"
}

# Assert that a directory exists
assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        fail_test "Directory '$dir' does not exist"
        return 1
    fi
    pass_test "Directory '$dir' exists"
}

# Assert that two strings are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values do not match}"
    
    if [[ "$expected" != "$actual" ]]; then
        fail_test "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
    pass_test "$message"
}

# Assert that a string contains another string
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String does not contain expected substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        fail_test "$message (looking for: '$needle' in: '$haystack')"
        return 1
    fi
    pass_test "$message"
}

# Assert that a command exits with expected code
assert_exit_code() {
    local expected_code="$1"
    shift
    local cmd="$*"
    
    local actual_code=0
    eval "$cmd" >/dev/null 2>&1 || actual_code=$?
    
    if [[ $actual_code -ne $expected_code ]]; then
        fail_test "Command exited with code $actual_code, expected $expected_code: $cmd"
        return 1
    fi
    pass_test "Command exited with correct code $expected_code"
}

###############################################################################
# cephtools-Specific Test Utilities
###############################################################################

# Set up a mock cephtools environment
setup_mock_cephtools() {
    local cephtools_dir="${1:-$(pwd)}"
    
    # Mock MSI environment
    export USER="testuser"
    export GROUP="testgroup"
    
    # Create mock directories
    mkdir -p "$MSIPROJECT"/{data_delivery,shared/{disaster_recovery,cephtools}}
    mkdir -p "$MSIPROJECT/shared/cephtools"/{dd2ceph,dd2dr,filesinbackup,panfs2ceph}
    
    # Mock the cephtools binary if it doesn't exist
    if [[ ! -f "$cephtools_dir/build/bin/cephtools" ]]; then
        mkdir -p "$cephtools_dir/build/bin"
        echo '#!/bin/bash
echo "Mock cephtools"' > "$cephtools_dir/build/bin/cephtools"
        chmod +x "$cephtools_dir/build/bin/cephtools"
    fi
}

# Create test files for data transfer tests
create_test_data() {
    local base_dir="$1"
    local file_count="${2:-5}"
    
    mkdir -p "$base_dir"
    for i in $(seq 1 "$file_count"); do
        echo "Test file $i content" > "$base_dir/testfile$i.txt"
    done
}

# Validate generated SLURM script
validate_slurm_script() {
    local script_file="$1"
    
    assert_file_exists "$script_file"
    
    # Check for required SLURM directives
    assert_contains "$(cat "$script_file")" "#SBATCH" "SLURM script contains SBATCH directives"
    assert_contains "$(cat "$script_file")" "#!/bin/bash" "SLURM script has bash shebang"
    
    # Check that script is executable
    if [[ ! -x "$script_file" ]]; then
        fail_test "SLURM script is not executable"
        return 1
    fi
    pass_test "SLURM script is executable"
}

###############################################################################
# Export functions for use in other scripts
###############################################################################

# Trap to clean up on exit
trap cleanup_tests EXIT