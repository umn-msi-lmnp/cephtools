#!/usr/bin/env bash
###############################################################################
# Real S3 Integration Tests for cephtools
# Tests actual bucket creation, policy setting, and data transfer
###############################################################################

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CEPHTOOLS_BIN="$PROJECT_ROOT/build/bin/cephtools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CLEANUP_ITEMS=()

# Test configuration
TEST_PREFIX="cephtools-test-$(date +%Y%m%d-%H%M%S)-$$"
TEST_BUCKET="${TEST_PREFIX}-bucket"
TEST_GROUP="$(id -ng)"
TEST_USER="$(id -un)"
TEST_DIR=""

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

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -e "${YELLOW}Testing:${NC} $test_name"
    
    if $test_function; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        log_error "$test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

cleanup_on_exit() {
    if [[ ${#CLEANUP_ITEMS[@]} -gt 0 ]]; then
        log_info "Cleaning up test resources..."
        
        # Remove test bucket if it exists
        if timeout 15 s3cmd ls "s3://$TEST_BUCKET" &>/dev/null; then
            log_info "Removing test bucket: $TEST_BUCKET"
            
            # First, remove all objects from the bucket
            log_info "Removing all objects from bucket: $TEST_BUCKET"
            timeout 60 s3cmd del "s3://$TEST_BUCKET" --recursive --force &>/dev/null || log_warning "Failed to remove some objects from $TEST_BUCKET"
            
            # Then remove the empty bucket
            timeout 30 s3cmd rb "s3://$TEST_BUCKET" &>/dev/null || log_warning "Failed to remove bucket $TEST_BUCKET"
        fi
        
        # Remove test directory if it exists
        if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
            log_info "Removing test directory: $TEST_DIR"
            rm -rf "$TEST_DIR" || log_warning "Failed to remove test directory"
        fi
        
        # Remove any policy files
        for item in "${CLEANUP_ITEMS[@]}"; do
            if [[ -f "$item" ]]; then
                rm -f "$item" || log_warning "Failed to remove $item"
            fi
        done
    fi
}

trap cleanup_on_exit EXIT

###############################################################################
# Test Prerequisites
###############################################################################

check_prerequisites() {
    # Check if cephtools is built
    if [[ ! -f "$CEPHTOOLS_BIN" ]]; then
        log_error "cephtools binary not found. Run 'make' first."
        return 1
    fi
    
    # Check if s3cmd is available and configured
    if ! command -v s3cmd &> /dev/null; then
        log_error "s3cmd not found in PATH"
        return 1
    fi
    
    # Test s3cmd configuration by listing buckets
    log_info "Testing s3cmd configuration..."
    if ! timeout 30 s3cmd ls &>/dev/null; then
        log_error "s3cmd not properly configured or MSI S3 service unavailable (timeout after 30s)"
        return 1
    fi
    
    # Check if s3info is available
    if ! command -v s3info &> /dev/null; then
        log_error "s3info not found in PATH"
        return 1
    fi
    
    # Check if we can get group information
    if ! getent group "$TEST_GROUP" &>/dev/null; then
        log_error "Cannot get group information for $TEST_GROUP"
        return 1
    fi
    
    # Create test directory
    TEST_DIR="/tmp/$TEST_PREFIX"
    mkdir -p "$TEST_DIR"
    
    log_info "Prerequisites check passed"
    log_info "Test bucket: $TEST_BUCKET"
    log_info "Test group: $TEST_GROUP" 
    log_info "Test user: $TEST_USER"
    log_info "Test directory: $TEST_DIR"
    
    return 0
}

###############################################################################
# Test Functions
###############################################################################

test_bucket_creation() {
    # Ensure bucket doesn't exist first
    if timeout 15 s3cmd ls "s3://$TEST_BUCKET" &>/dev/null; then
        log_error "Test bucket $TEST_BUCKET already exists"
        return 1
    fi
    
    # Create bucket using s3cmd
    if timeout 15 s3cmd mb "s3://$TEST_BUCKET" &>/dev/null; then
        CLEANUP_ITEMS+=("$TEST_BUCKET")
        
        # Verify bucket exists
        if timeout 15 s3cmd ls "s3://$TEST_BUCKET" &>/dev/null; then
            return 0
        else
            log_error "Bucket creation succeeded but bucket not accessible"
            return 1
        fi
    else
        log_error "Failed to create bucket $TEST_BUCKET"
        return 1
    fi
}

test_bucket_policy_group_read() {
    cd "$TEST_DIR"
    
    # Run cephtools bucketpolicy for GROUP_READ
    if "$CEPHTOOLS_BIN" bucketpolicy \
        --bucket "$TEST_BUCKET" \
        --policy GROUP_READ \
        --group "$TEST_GROUP" \
        --log_dir "$TEST_DIR" \
        --verbose &>/dev/null; then
        
        # Check if policy files were created
        local policy_file="${TEST_BUCKET}.bucket_policy.json"
        local readme_file="${TEST_BUCKET}.bucket_policy_readme.md"
        
        if [[ -f "$policy_file" && -f "$readme_file" ]]; then
            CLEANUP_ITEMS+=("$TEST_DIR/$policy_file")
            CLEANUP_ITEMS+=("$TEST_DIR/$readme_file")
            
            # Verify policy file contains expected content
            if grep -q "s3:GetObject" "$policy_file" && \
               grep -q "arn:aws:iam:::user/" "$policy_file"; then
                return 0
            else
                log_error "Policy file missing expected content"
                return 1
            fi
        else
            log_error "Policy files not created"
            return 1
        fi
    else
        log_error "bucketpolicy command failed"
        return 1
    fi
}

test_bucket_policy_group_read_write() {
    cd "$TEST_DIR"
    
    # Run cephtools bucketpolicy for GROUP_READ_WRITE
    if "$CEPHTOOLS_BIN" bucketpolicy \
        --bucket "$TEST_BUCKET" \
        --policy GROUP_READ_WRITE \
        --group "$TEST_GROUP" \
        --log_dir "$TEST_DIR" \
        --verbose &>/dev/null; then
        
        # Check if policy files were updated
        local policy_file="${TEST_BUCKET}.bucket_policy.json"
        
        if [[ -f "$policy_file" ]]; then
            # Verify policy file contains write permissions
            if grep -q '"s3:\*"' "$policy_file"; then
                return 0
            else
                log_error "Policy file missing write permissions"
                return 1
            fi
        else
            log_error "Policy file not found"
            return 1
        fi
    else
        log_error "bucketpolicy GROUP_READ_WRITE command failed"
        return 1
    fi
}

test_data_upload_and_verification() {
    cd "$TEST_DIR"
    
    # Create test data
    local test_file="test-data.txt"
    local test_content="This is test data for cephtools integration test at $(date)"
    echo "$test_content" > "$test_file"
    
    # Upload using s3cmd
    if timeout 60 s3cmd put "$test_file" "s3://$TEST_BUCKET/" &>/dev/null; then
        # Verify file exists in bucket
        if timeout 30 s3cmd ls "s3://$TEST_BUCKET/$test_file" &>/dev/null; then
            # Download and verify content
            local downloaded_file="downloaded-$test_file"
            if timeout 60 s3cmd get "s3://$TEST_BUCKET/$test_file" "$downloaded_file" &>/dev/null; then
                if diff "$test_file" "$downloaded_file" &>/dev/null; then
                    rm -f "$test_file" "$downloaded_file"
                    return 0
                else
                    log_error "Downloaded file content differs from original"
                    return 1
                fi
            else
                log_error "Failed to download test file"
                return 1
            fi
        else
            log_error "Uploaded file not found in bucket"
            return 1
        fi
    else
        log_error "Failed to upload test file"
        return 1
    fi
}

test_bucket_policy_list_users() {
    cd "$TEST_DIR"
    
    # Create a user list file
    local user_list_file="test-users.txt"
    echo "$TEST_USER" > "$user_list_file"
    CLEANUP_ITEMS+=("$TEST_DIR/$user_list_file")
    
    # Run cephtools bucketpolicy for LIST_READ with file input
    if "$CEPHTOOLS_BIN" bucketpolicy \
        --bucket "$TEST_BUCKET" \
        --policy LIST_READ \
        --list "$user_list_file" \
        --log_dir "$TEST_DIR" \
        --verbose &>/dev/null; then
        
        # Check if policy file was created with correct content
        local policy_file="${TEST_BUCKET}.bucket_policy.json"
        
        if [[ -f "$policy_file" ]]; then
            # Verify policy contains the user
            if s3info info --user "$TEST_USER" &>/dev/null; then
                local ceph_username
                ceph_username="$(s3info info --user "$TEST_USER" | grep "Tier 2 username" | sed 's/Tier 2 username: //')"
                if grep -q "arn:aws:iam:::user/$ceph_username" "$policy_file"; then
                    return 0
                else
                    log_error "Policy file missing expected user ARN"
                    return 1
                fi
            else
                log_warning "s3info failed for user $TEST_USER, but policy creation succeeded"
                return 0
            fi
        else
            log_error "Policy file not created for LIST_READ"
            return 1
        fi
    else
        log_error "bucketpolicy LIST_READ command failed"
        return 1
    fi
}

test_bucket_policy_removal() {
    cd "$TEST_DIR"
    
    # Remove bucket policy using NONE
    # Note: s3cmd delpolicy may fail if no policy exists, but that's ok
    local output
    output=$("$CEPHTOOLS_BIN" bucketpolicy \
        --bucket "$TEST_BUCKET" \
        --policy NONE \
        --log_dir "$TEST_DIR" \
        --verbose 2>&1)
    local exit_code=$?
    
    # Check if policy file is empty or contains minimal content
    local policy_file="${TEST_BUCKET}.bucket_policy.json"
    
    if [[ -f "$policy_file" ]]; then
        # NONE policy should create an empty or minimal policy file
        local file_size
        file_size="$(wc -c < "$policy_file")"
        if [[ $file_size -lt 10 ]]; then
            # Success if either command succeeded OR it failed due to "no policy to delete"
            if [[ $exit_code -eq 0 ]] || echo "$output" | grep -q "policy.*not.*exist\|NoSuchBucketPolicy\|no policy"; then
                return 0
            else
                log_error "bucketpolicy NONE failed unexpectedly (exit: $exit_code)"
                echo "$output" >&2
                return 1
            fi
        else
            log_error "NONE policy didn't create minimal policy file (size: $file_size bytes)"
            return 1
        fi
    else
        log_error "Policy file not created for NONE policy"
        return 1
    fi
}

test_bucket_with_make_flag() {
    # Test bucket creation with --make_bucket flag
    local new_test_bucket="${TEST_PREFIX}-makebucket"
    
    # Ensure bucket doesn't exist
    if timeout 15 s3cmd ls "s3://$new_test_bucket" &>/dev/null; then
        # First, remove all objects from the bucket
        timeout 60 s3cmd del "s3://$new_test_bucket" --recursive --force &>/dev/null 2>&1 || true
        # Then remove the empty bucket
        timeout 30 s3cmd rb "s3://$new_test_bucket" &>/dev/null 2>&1 || true
    fi
    
    cd "$TEST_DIR"
    
    # Run bucketpolicy with --make_bucket flag
    if "$CEPHTOOLS_BIN" bucketpolicy \
        --bucket "$new_test_bucket" \
        --policy GROUP_READ \
        --group "$TEST_GROUP" \
        --make_bucket \
        --log_dir "$TEST_DIR" \
        --verbose &>/dev/null; then
        
        # Verify bucket was created
        if timeout 15 s3cmd ls "s3://$new_test_bucket" &>/dev/null; then
            # Clean up the bucket - first remove objects, then bucket
            timeout 60 s3cmd del "s3://$new_test_bucket" --recursive --force &>/dev/null 2>&1 || true
            timeout 30 s3cmd rb "s3://$new_test_bucket" &>/dev/null || log_warning "Failed to clean up $new_test_bucket"
            return 0
        else
            log_error "Bucket not created with --make_bucket flag"
            return 1
        fi
    else
        log_error "bucketpolicy with --make_bucket failed"
        return 1
    fi
}

###############################################################################
# Main Test Execution
###############################################################################

print_test_summary() {
    echo
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "  Total tests: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✅${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed! ❌${NC}"
        return 1
    fi
}

main() {
    echo -e "${BLUE}Real S3 Integration Tests for cephtools${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo "Testing against: s3.msi.umn.edu"
    echo "Project: $PROJECT_ROOT"
    echo "Test directory: $TEST_DIR"
    echo

    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    echo

    # Run tests
    run_test "Bucket creation" test_bucket_creation
    run_test "Bucket policy (GROUP_READ)" test_bucket_policy_group_read
    run_test "Bucket policy (GROUP_READ_WRITE)" test_bucket_policy_group_read_write
    run_test "Data upload and verification" test_data_upload_and_verification
    run_test "Bucket policy (LIST_READ)" test_bucket_policy_list_users
    run_test "Bucket policy removal (NONE)" test_bucket_policy_removal
    run_test "Bucket creation with --make_bucket flag" test_bucket_with_make_flag

    # Print summary
    print_test_summary
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [options]"
        echo
        echo "Real S3 integration tests for cephtools"
        echo "Tests bucket creation, policy management, and data transfer"
        echo "against the actual MSI S3 service at s3.msi.umn.edu"
        echo
        echo "Prerequisites:"
        echo "  - s3cmd configured for MSI S3 service"
        echo "  - s3info command available"
        echo "  - Valid MSI group membership"
        echo "  - cephtools built (run 'make' first)"
        echo
        echo "Note: This test creates and removes real S3 buckets and files"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac