# panfs2ceph Testing Guide

This guide explains the comprehensive testing strategy for the panfs2ceph path construction fix and custom empty directory handling implementation.

## Background

The original panfs2ceph tool had a path construction bug that caused `BucketAlreadyExists` errors. Additionally, rclone's native `--s3-directory-markers` flag caused S3 compatibility issues on some Ceph installations. This has been resolved by implementing custom empty directory handling using marker files instead of problematic S3-specific flags.

## Test Coverage

### 1. Mock Tests (Fast, Safe) 

**File:** `test-panfs2ceph-path-fix.sh`

**Purpose:** Validates script generation and path construction syntax without actual S3 execution.

**What it tests:**
- ✅ Path construction uses `bucket/object-path` format
- ✅ Generated SLURM scripts have correct rclone commands  
- ✅ Multiple absolute path formats work correctly
- ✅ Restore scripts also have correct path construction
- ✅ Old buggy concatenation is eliminated

**Limitations:**
- ❌ Only tests script generation, not execution
- ❌ Cannot catch runtime S3 compatibility issues
- ❌ Does not validate actual file transfers

**Usage:**
```bash
# Run mock tests (default)
./tests/test-panfs2ceph-path-fix.sh

# View help
./tests/test-panfs2ceph-path-fix.sh --help
```

### 2. End-to-End Real Bucket Tests (Comprehensive)

**File:** `test-panfs2ceph-e2e-real.sh`

**Purpose:** Validates actual rclone execution against real S3/Ceph buckets to catch runtime issues.

**What it tests:**
- ✅ Real rclone command execution with generated scripts
- ✅ Custom empty directory handling with marker files
- ✅ `--delete_empty_dirs` flag correctly skips empty directory handling
- ✅ Actual file transfers and bucket verification
- ✅ Path construction works in real S3 environment
- ✅ No S3 compatibility issues with new approach

**Prerequisites:**
- s3cmd configured for MSI S3 service
- rclone available and working
- s3info for credential access  
- Network access to s3.msi.umn.edu
- Permission to create/delete test buckets

**Usage:**
```bash
# Run E2E tests (requires S3 setup)
./tests/test-panfs2ceph-e2e-real.sh

# Or via the path fix test
./tests/test-panfs2ceph-path-fix.sh --real
```

## Test Scenarios

### Scenario 1: Default Behavior (Custom Empty Directory Handling)

Tests panfs2ceph with default settings:
- Uses custom marker files for empty directory preservation
- **Expected result:** Should work without S3 compatibility issues
- **Purpose:** Validates the custom empty directory handling approach

### Scenario 2: With --delete_empty_dirs (Skip Empty Directories)

Tests panfs2ceph with `--delete_empty_dirs` flag:
- Skips empty directory handling entirely
- **Expected result:** Should work without errors, no marker files created
- **Purpose:** Validates that empty directory handling can be disabled when not needed

### Scenario 3: Path Construction Validation

Tests various absolute path structures:
- Deep nested paths
- Paths with special characters
- Verifies bucket/object-path separation
- **Purpose:** Confirms the original path fix works

## Running Tests

### Quick Validation (Recommended)
```bash
# Run mock tests - fast and safe
make test-all path-fix
```

### Comprehensive Validation (If S3 Available)
```bash
# Run both mock and real tests
./tests/run-all-tests.sh path-fix e2e-real
```

### Individual Test Execution
```bash
# Mock tests only
./tests/test-panfs2ceph-path-fix.sh

# Real S3 tests only  
./tests/test-panfs2ceph-e2e-real.sh

# Real tests via mock test script
./tests/test-panfs2ceph-path-fix.sh --real
```

## Expected Results

### Mock Tests
- ✅ All tests should pass
- ✅ Confirms path construction syntax is correct
- ✅ Verifies script generation works properly

### Real Tests (If S3 Available)
- ✅ Default behavior test should pass (uses custom empty directory handling)
- ✅ `--delete_empty_dirs` tests should pass
- ✅ Path construction tests should pass
- ✅ Files should actually transfer to S3

## Interpreting Results

### If Mock Tests Pass But Real Tests Fail:
This indicates a runtime issue that wouldn't be caught by syntax-only testing. With the custom empty directory handling, S3 compatibility issues should be eliminated.

### If Tests Show Custom Marker Files:
Look for `.cephtools_empty_dir_marker` files in the bucket when empty directory preservation is enabled. These should be cleaned up from source after transfer.

### If Both Test Types Pass:
The custom empty directory handling is working correctly for both script generation and actual execution.

## Test Artifacts

### Mock Test Outputs
- **Location:** `tests/outputs/panfs2ceph-path-fix-*`
- **Contents:** Generated SLURM scripts, test data
- **Purpose:** Manual inspection of generated commands

### Real Test Outputs  
- **Location:** `tests/outputs/panfs2ceph-e2e-real-*`
- **Contents:** Generated SLURM scripts, rclone logs, test data
- **Purpose:** Debugging real execution issues

### Important Log Files
- `rclone_default_execution.log` - Shows default custom empty directory handling results
- `rclone_no_empty_execution.log` - Shows --delete_empty_dirs results
- `*.1_copy_and_verify.slurm` - Generated scripts for manual review
- `*.empty_dirs.txt` - List of empty directories found (when using custom handling)

## Troubleshooting

### "Prerequisites not met"
Ensure s3cmd, rclone, and s3info are available and configured.

### "Failed to create test bucket"  
Check S3 credentials and network connectivity.

### "Custom marker file issues"
Check that marker files (`.cephtools_empty_dir_marker`) are properly created and cleaned up.

### Tests pass but real usage fails
Run the E2E tests to catch runtime issues not visible in mock tests.

## Development Workflow

1. **Make changes** to panfs2ceph plugin
2. **Run mock tests** for quick validation
3. **Run real tests** to catch runtime issues  
4. **Review test artifacts** for detailed analysis
5. **Update tests** if new scenarios are discovered

This comprehensive testing approach ensures that both syntax correctness and runtime behavior are validated, preventing issues like the `--s3-directory-markers` compatibility problem from going undetected.