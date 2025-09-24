# cephtools Test Suite

Comprehensive testing framework for cephtools with extensive coverage of functionality, dependencies, error scenarios, and system compatibility.

## Test Structure

### Core Test Framework (`test-framework.sh`)
- **Mocking system** - Create mock commands for testing without real dependencies
- **Assertion functions** - Comprehensive set of assertions for validating behavior
- **Test organization** - Structured test reporting with pass/fail tracking
- **Environment setup** - Isolated test environments with cleanup

### Test Suites

#### 1. Basic Plugin Tests (`run-plugin-tests.sh`)
- ✅ Binary existence and executability
- ✅ Help command functionality
- ✅ Version command functionality  
- ✅ Plugin discovery mechanism
- ✅ Individual plugin help display

#### 2. Dependency Validation (`test-dependencies.sh`)
- ✅ **System Commands**: bash, date, mkdir, chmod, find, grep, awk, sed, etc.
- ✅ **MSI Commands**: s3info, getent availability
- ✅ **rclone**: Version checking (≥1.67.0), remote validation, bucket access
- ✅ **s3cmd**: Availability, bucket operations, policy management

- ✅ **Module System**: Module loading and availability
- ✅ **Environment Variables**: MSIPROJECT, USER validation
- ✅ **Plugin-Specific Dependencies**: Per-plugin dependency validation

#### 3. Integration Tests (`test-integration.sh`)
- ✅ **dd2ceph**: Complete workflow, credential setup in SLURM scripts
- ✅ **dd2dr**: Complete workflow, quota checking logic  
- ✅ **filesinbackup**: Complete workflow, file comparison logic
- ✅ **panfs2ceph**: Copy and verify script generation
- ✅ **bucketpolicy**: Bucket operations and policy management
- ✅ **Cross-Plugin Consistency**: Filename patterns, SLURM directives

#### 4. Error Scenario Tests (`test-error-scenarios.sh`)
- ✅ **Missing Dependencies**: Tool unavailability handling
- ✅ **Invalid Arguments**: Required parameter validation
- ✅ **Path Issues**: Non-existent paths, permission problems
- ✅ **Bucket Access**: Access denied, non-existent buckets
- ✅ **Network Issues**: Timeouts, connectivity failures
- ✅ **Credential Failures**: Missing or invalid credentials
- ✅ **Resource Constraints**: Disk space, large datasets
- ✅ **System Issues**: Module loading, concurrent operations
- ✅ **Data Integrity**: Corrupted configuration handling

#### 5. System Compatibility (`test-compatibility.sh`) 
- ✅ **Shell Compatibility**: Bash features, array support
- ✅ **System Commands**: Essential command availability
- ✅ **Filesystem**: Directory/file creation, permissions
- ✅ **MSI Environment**: Environment detection, module system
- ✅ **SLURM Integration**: SLURM command availability
- ✅ **Network Tools**: Connectivity utilities, DNS resolution
- ✅ **Tool Versions**: Python, rclone, s3cmd versions
- ✅ **Locale Support**: Character encoding, timezone handling
- ✅ **Resource Limits**: File descriptors, process limits
- ✅ **Path Handling**: Cross-platform path resolution

#### 6. Empty Directory Flag Tests (`test-empty-dirs-flag.sh`)
- ✅ **Mock Tests**: SLURM script generation with custom empty directory handling
- ✅ **Real Ceph Tests**: End-to-end validation of marker file-based empty directory preservation
- ✅ **panfs2ceph Plugin**: Default custom handling and --delete_empty_dirs flag
- ✅ **dd2ceph Plugin**: Default custom handling and --delete_empty_dirs flag
- ✅ **Marker File Validation**: Verification of .cephtools_empty_dir_marker files
- ✅ **S3 Compatibility**: Ensures no problematic --s3-directory-markers flags are used

#### 7. Permission Handling Tests (`test-permission-handling.sh`)
- ✅ **Permission Detection**: Validates _check_path_permissions function
- ✅ **Failure Scenarios**: Tests with unreadable files and directories
- ✅ **Plugin Integration**: Full panfs2ceph plugin behavior with permission issues
- ✅ **Dry Run Mode**: Ensures --dry_run continues despite permission problems
- ✅ **Error Messages**: Validates informative error reporting
- ✅ **Edge Cases**: Empty directories, single files, completely inaccessible paths
- ✅ **File Counting**: Verifies accurate reporting of readable/unreadable items

#### 8. Complete Vignette Workflow Tests (`test-vignette-panfs2ceph-e2e.sh`)
- ✅ **Full Workflow**: Complete vignette_panfs2ceph.md workflow validation
- ✅ **Bucket Creation**: Real MSI Ceph bucket creation and cleanup
- ✅ **Bucket Policy**: GROUP_READ policy setup and permission verification
- ✅ **Script Generation**: All three panfs2ceph scripts (copy, delete, restore)
- ✅ **Flag Verification**: Correct rclone flags in each script type (no S3-problematic flags)
- ✅ **Script Execution**: Real execution of copy/verify and restore scripts
- ✅ **Custom Empty Directory Handling**: Marker file-based empty directory preservation
- ✅ **End-to-End Validation**: Complete data transfer, policy enforcement, and restore functionality

## Running Tests

### Quick Commands
```bash
# Run all tests
make test-all

# Run specific test suites
make test-quick          # Basic functionality only
make test-deps          # Dependency validation
make test-integration   # Integration tests  
make test-errors        # Error scenarios
make test-compatibility # System compatibility
make test-empty-dirs    # Empty directory flag tests
make test-permissions   # File permission handling tests
make test-vignette-e2e  # Complete vignette workflow (requires S3 access)
```

### Advanced Usage
```bash
# Run tests quietly
./tests/run-all-tests.sh --quiet

# Run specific combinations
./tests/run-all-tests.sh basic integration errors empty-dirs permissions

# Run with verbose output
./tests/run-all-tests.sh --verbose

# Show help
./tests/run-all-tests.sh --help
```

## Test Coverage Summary

### ✅ **Comprehensive Coverage**

#### **System Validation**
- Dependency checking (rclone, s3cmd, etc.)
- Bucket existence and access permissions
- s3cmd connectivity and credentials
- Module system integration
- SLURM compatibility

#### **Plugin Functionality**  
- All 5 plugins tested: dd2ceph, dd2dr, filesinbackup, panfs2ceph, bucketpolicy
- SLURM script generation and validation
- Credential setup and configuration
- File operations and comparisons
- Error handling and recovery

#### **Error Scenarios**
- Missing dependencies and tools
- Invalid arguments and parameters
- Network connectivity issues  
- Permission and access problems
- Resource constraints and limits
- Concurrent operation handling

#### **Cross-Platform Support**
- Shell and system compatibility
- Path handling differences
- Character encoding support
- Resource limit variations
- Environment detection

### **Test Quality Features**
- **Mocking System**: Test without real dependencies
- **Isolated Environments**: No interference between tests  
- **Comprehensive Assertions**: Multiple validation types
- **Clear Reporting**: Color-coded pass/fail with details
- **Modular Design**: Individual test suites can run separately

## Benefits

### **For Developers**
- **Early Detection**: Catch issues before deployment
- **Regression Prevention**: Ensure changes don't break existing functionality
- **Documentation**: Tests serve as usage examples
- **Confidence**: Comprehensive validation of all scenarios

### **For Users**
- **Reliability**: Verified functionality across different environments
- **Better Error Messages**: Validated error handling provides clear feedback
- **Compatibility**: Tested across different system configurations
- **Maintainability**: Easier to identify and fix issues

### **For System Administrators**
- **Deployment Validation**: Verify system compatibility before rollout
- **Troubleshooting**: Identify environment-specific issues
- **Monitoring**: Regular test runs can detect system changes
- **Documentation**: Clear requirements and dependencies

## Test Statistics

- **Total Test Scripts**: 7 (including framework and master runner)
- **Test Categories**: 6 major areas of coverage
- **Mock Commands**: Full simulation of external dependencies  
- **Assertion Types**: 10+ different validation methods
- **Plugin Coverage**: 100% of all plugins tested
- **Error Scenarios**: 15+ failure modes covered
- **System Compatibility**: 10+ environment aspects tested

This test suite provides the most comprehensive validation possible for cephtools, ensuring reliable operation across different environments and use cases.