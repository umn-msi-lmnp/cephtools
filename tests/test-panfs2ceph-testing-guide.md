# panfs2ceph Testing Guide

This guide explains the comprehensive testing strategy for the panfs2ceph path construction fix and S3 compatibility issues.

## Background

The original panfs2ceph tool had a path construction bug that caused `BucketAlreadyExists` errors. Additionally, the default `--s3-directory-markers` flag causes S3 compatibility issues on some Ceph installations.

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
- ✅ S3 compatibility issue detection (`--s3-directory-markers` problems)
- ✅ `--delete_empty_dirs` flag resolves S3 compatibility issues
- ✅ Actual file transfers and bucket verification
- ✅ Path construction works in real S3 environment
- ✅ Both successful and problematic scenarios

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

### Scenario 1: Default Behavior (Expected to Reveal Issues)

Tests panfs2ceph with default settings:
- Uses `--s3-directory-markers` flag
- **Expected result:** May fail with `BucketAlreadyExists` errors
- **Purpose:** Demonstrates the S3 compatibility issue

### Scenario 2: With --delete_empty_dirs (Should Work)

Tests panfs2ceph with `--delete_empty_dirs` flag:
- Omits `--s3-directory-markers` flag
- **Expected result:** Should work without errors
- **Purpose:** Validates the workaround solution

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
- ⚠️ Default behavior test may fail (demonstrates the issue)
- ✅ `--delete_empty_dirs` tests should pass
- ✅ Path construction tests should pass
- ✅ Files should actually transfer to S3

## Interpreting Results

### If Mock Tests Pass But Real Tests Fail:
This indicates a runtime S3 compatibility issue that wouldn't be caught by syntax-only testing. This is exactly what happened with the `--s3-directory-markers` problem.

### If Real Tests Show BucketAlreadyExists Errors:
This confirms the S3 compatibility issue. The solution is to use the `--delete_empty_dirs` flag.

### If Both Test Types Pass:
The fix is working correctly for both script generation and actual execution.

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
- `rclone_default_execution.log` - Shows default behavior results
- `rclone_no_empty_execution.log` - Shows --delete_empty_dirs results
- `*.1_copy_and_verify.slurm` - Generated scripts for manual review

## Troubleshooting

### "Prerequisites not met"
Ensure s3cmd, rclone, and s3info are available and configured.

### "Failed to create test bucket"  
Check S3 credentials and network connectivity.

### "BucketAlreadyExists errors"
This is expected for default behavior tests - it demonstrates the issue.

### Tests pass but real usage fails
Run the E2E tests to catch runtime issues not visible in mock tests.

## Development Workflow

1. **Make changes** to panfs2ceph plugin
2. **Run mock tests** for quick validation
3. **Run real tests** to catch runtime issues  
4. **Review test artifacts** for detailed analysis
5. **Update tests** if new scenarios are discovered

This comprehensive testing approach ensures that both syntax correctness and runtime behavior are validated, preventing issues like the `--s3-directory-markers` compatibility problem from going undetected.