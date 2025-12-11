#!/bin/bash
source tests/test-framework.sh
PROJECT_ROOT="$(pwd)"
CEPHTOOLS_BIN="${PROJECT_ROOT}/build/bin/cephtools"

init_tests "dd2dr-isolated"
setup_mock_cephtools "$PROJECT_ROOT"
create_mock_command "rclone" "" 0
create_mock_command "module" "" 0
create_test_data "$MSIPROJECT/data_delivery" 3
create_test_data "$MSIPROJECT/shared/disaster_recovery" 3

output_dir="$TEST_OUTPUT_DIR/dd2dr_test"
mkdir -p "$output_dir"

original_dir=$(pwd)
cd "$output_dir"

echo "Running dd2dr command..."
timeout 10 "$CEPHTOOLS_BIN" dd2dr --group testgroup --log_dir "$output_dir" --dry_run 2>&1
exit_code=$?

cd "$original_dir"

echo "Exit code: $exit_code"
ls -la "$output_dir"
find "$output_dir" -name "*.slurm"
