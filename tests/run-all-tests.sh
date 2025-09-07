#!/usr/bin/env bash
###############################################################################
# Master Test Runner for cephtools
# Runs all test suites and provides comprehensive reporting
###############################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test suite tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=()

###############################################################################
# Test Runner Functions
###############################################################################

run_test_suite() {
    local suite_name="$1"
    local script_path="$2"
    local description="$3"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running: $suite_name${NC}"
    echo -e "${BLUE}$description${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    if [[ ! -f "$script_path" ]]; then
        echo -e "${RED}ERROR: Test script not found: $script_path${NC}"
        FAILED_SUITES+=("$suite_name (script not found)")
        return 1
    fi
    
    # Make script executable
    chmod +x "$script_path"
    
    # Run the test suite
    if bash "$script_path"; then
        echo -e "${GREEN}✅ $suite_name PASSED${NC}"
        PASSED_SUITES=$((PASSED_SUITES + 1))
        return 0
    else
        echo -e "${RED}❌ $suite_name FAILED${NC}"
        FAILED_SUITES+=("$suite_name")
        return 1
    fi
}

###############################################################################
# Individual Test Suites
###############################################################################

run_basic_tests() {
    run_test_suite \
        "Basic Plugin Tests" \
        "$SCRIPT_DIR/run-plugin-tests.sh" \
        "Basic framework functionality and plugin discovery"
}

run_dependency_tests() {
    run_test_suite \
        "Dependency Validation" \
        "$SCRIPT_DIR/test-dependencies.sh" \
        "System dependencies and tool availability validation"
}

run_integration_tests() {
    run_test_suite \
        "Integration Tests" \
        "$SCRIPT_DIR/test-integration.sh" \
        "End-to-end plugin workflows with mocked dependencies"
}

run_error_tests() {
    run_test_suite \
        "Error Scenario Tests" \
        "$SCRIPT_DIR/test-error-scenarios.sh" \
        "Error handling and failure mode validation"
}

run_compatibility_tests() {
    run_test_suite \
        "System Compatibility" \
        "$SCRIPT_DIR/test-compatibility.sh" \
        "Cross-platform and environment compatibility"
}

###############################################################################
# Test Summary and Reporting
###############################################################################

print_overall_summary() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}OVERALL TEST SUMMARY${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    echo -e "Total test suites: $TOTAL_SUITES"
    echo -e "${GREEN}Passed: $PASSED_SUITES${NC}"
    echo -e "${RED}Failed: $((TOTAL_SUITES - PASSED_SUITES))${NC}"
    
    if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}Failed test suites:${NC}"
        for suite in "${FAILED_SUITES[@]}"; do
            echo -e "  ${RED}• $suite${NC}"
        done
        echo
        echo -e "${RED}Some tests failed! ❌${NC}"
        return 1
    else
        echo
        echo -e "${GREEN}All test suites passed! ✅${NC}"
        return 0
    fi
}

###############################################################################
# Build Verification
###############################################################################

verify_build() {
    echo -e "${BLUE}Verifying build...${NC}"
    
    if [[ ! -f "$PROJECT_ROOT/build/bin/cephtools" ]]; then
        echo -e "${YELLOW}cephtools not built, building now...${NC}"
        if make -C "$PROJECT_ROOT" >/dev/null 2>&1; then
            echo -e "${GREEN}Build successful${NC}"
        else
            echo -e "${RED}Build failed!${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}cephtools binary found${NC}"
    fi
}

###############################################################################
# Main Test Execution
###############################################################################

show_usage() {
    echo "Usage: $0 [options] [test-suite...]"
    echo
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -q, --quiet       Run tests quietly (less output)"
    echo "  -v, --verbose     Run tests with verbose output"
    echo "  --build-only      Only verify build, don't run tests"
    echo "  --skip-build      Skip build verification"
    echo
    echo "Test suites (run all if none specified):"
    echo "  basic             Basic plugin functionality tests"
    echo "  dependencies      Dependency validation tests"
    echo "  integration       Integration tests with mocks"
    echo "  errors            Error scenario tests"
    echo "  compatibility     System compatibility tests"
    echo
    echo "Examples:"
    echo "  $0                          # Run all test suites"
    echo "  $0 basic integration        # Run only basic and integration tests"
    echo "  $0 --quiet dependencies     # Run dependency tests quietly"
}

main() {
    local quiet=false
    local verbose=false
    local build_only=false
    local skip_build=false
    local specific_tests=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --build-only)
                build_only=true
                shift
                ;;
            --skip-build)
                skip_build=true
                shift
                ;;
            basic|dependencies|integration|errors|compatibility)
                specific_tests+=("$1")
                shift
                ;;
            *)
                echo "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up output redirection based on quiet/verbose flags
    if $quiet; then
        exec 3>&1 1>/dev/null
    elif $verbose; then
        set -x
    fi
    
    echo -e "${BLUE}cephtools Comprehensive Test Suite${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo "Project: $PROJECT_ROOT"
    echo "Tests: $SCRIPT_DIR"
    echo
    
    # Verify build unless skipped
    if ! $skip_build; then
        if ! verify_build; then
            echo -e "${RED}Build verification failed!${NC}"
            exit 1
        fi
        
        if $build_only; then
            echo -e "${GREEN}Build verification complete.${NC}"
            exit 0
        fi
        echo
    fi
    
    # Determine which tests to run
    local run_all_tests=true
    if [[ ${#specific_tests[@]} -gt 0 ]]; then
        run_all_tests=false
    fi
    
    # Run test suites
    local overall_success=true
    
    # Run specified tests or all tests
    for test_name in "${specific_tests[@]:-basic dependencies integration errors compatibility}"; do
        case $test_name in
            basic)
                run_basic_tests || overall_success=false
                ;;
            dependencies)
                run_dependency_tests || overall_success=false
                ;;
            integration)
                run_integration_tests || overall_success=false
                ;;
            errors)
                run_error_tests || overall_success=false
                ;;
            compatibility)
                run_compatibility_tests || overall_success=false
                ;;
        esac
        echo
    done
    
    # Restore output if it was redirected
    if $quiet; then
        exec 1>&3 3>&-
    fi
    
    # Print overall summary
    if ! print_overall_summary; then
        overall_success=false
    fi
    
    # Exit with appropriate code
    if $overall_success; then
        exit 0
    else
        exit 1
    fi
}

# Run main function with all arguments
main "$@"