#!/usr/bin/env bash
###############################################################################
# Test Case: Path Validation for dd2ceph --log_dir
# 
# Tests the proposed fix for double slash issue using validation instead of
# automatic path normalization.
###############################################################################

echo "=== Path Validation Approach for dd2ceph --log_dir Issue ==="
echo ""

# Proposed validation function that would be added to dd2ceph
validate_log_dir_path() {
    local path="$1"
    local errors=0
    
    echo "Validating path: '$path'"
    
    # Check for double slashes that can cause path issues
    if [[ "$path" =~ // ]]; then
        echo "  ❌ ERROR: Path contains double slashes (//) which can cause issues"
        echo "     Please provide a clean path without double slashes"
        echo "     Example: instead of '/path//to/dir', use '/path/to/dir'"
        ((errors++))
    fi
    
    # Check for leading double slashes
    if [[ "$path" =~ ^// ]]; then
        echo "  ❌ ERROR: Path starts with double slashes"
        echo "     Please provide a path starting with a single slash"
        ((errors++))
    fi
    
    # Warn about trailing slashes (non-fatal)
    if [[ "$path" =~ /$ ]] && [[ "$path" != "/" ]]; then
        echo "  ⚠️  WARNING: Path ends with trailing slash"
        echo "     Consider removing trailing slashes for consistency"
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "  ✅ Path validation passed"
        return 0
    else
        echo "  ❌ Path validation failed with $errors error(s)"
        return 1
    fi
}

echo "1. Testing Path Validation Function:"
echo ""

# Test cases including the reported problematic path
test_paths=(
    "/panfs/jay/groups/13/dehms/shared/ceph//shrestha-70-mcrpc-biopsy-samples-atac-seq"  # Reported issue
    "/normal/clean/path"                                                                  # Good path
    "//leading/double/slash"                                                             # Bad: leading //
    "/middle//double/slash/path"                                                         # Bad: middle //
    "/trailing/path/"                                                                    # Warning: trailing /
    "/clean/path/no/issues"                                                             # Good path
    "///multiple///slashes///"                                                          # Bad: multiple //
)

valid_count=0
invalid_count=0
warning_count=0

for path in "${test_paths[@]}"; do
    if validate_log_dir_path "$path"; then
        if [[ "$path" =~ /$ ]] && [[ "$path" != "/" ]]; then
            ((warning_count++))
        else
            ((valid_count++))
        fi
    else
        ((invalid_count++))
    fi
    echo ""
done

echo "Results Summary:"
echo "  ✅ Valid paths: $valid_count"
echo "  ❌ Invalid paths: $invalid_count (would cause dd2ceph to exit with error)"
echo "  ⚠️  Paths with warnings: $warning_count (would work but show warning)"
echo ""

echo "2. Benefits of Validation Approach:"
echo "  - Catches problematic paths early before they cause issues"
echo "  - Provides clear, actionable error messages to users"
echo "  - Preserves user's original intent (no automatic modification)"
echo "  - Prevents mysterious bucket access errors later in the process"
echo "  - Easy to maintain and understand"
echo ""

echo "3. How This Fixes the Original Issue:"
echo "  - User runs: dd2ceph --log_dir '/path//with/double' --bucket test"
echo "  - Instead of mysterious bucket access error later..."
echo "  - Tool immediately shows: ERROR: Path contains double slashes"
echo "  - User fixes path and re-runs successfully"
echo ""

echo "4. Integration into dd2ceph plugin:"
echo "  Add validation function and call it during option parsing:"
echo "  _log_dir=\"\$(__get_option_value \"\${__arg}\" \"\${__val:-}\")\"" 
echo "  __validate_log_dir_path \"\$_log_dir\""
echo ""

if [[ $invalid_count -gt 0 ]]; then
    echo "✅ Test PASSED: Path validation correctly identified $invalid_count problematic paths"
else
    echo "❌ Test FAILED: Path validation should have caught some problematic paths"
fi

echo ""
echo "=== Path Validation Test Complete ==="