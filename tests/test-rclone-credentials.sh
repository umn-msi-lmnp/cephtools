#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$PROJECT_ROOT/src/core/common.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

test_current_process_credentials() {
    local calls="$TEMP_DIR/s3info.calls"
    s3info() {
        printf 'call\n' >> "$calls"
        printf 'ACCESS SECRET\n'
    }

    _setup_rclone_credentials myremote
    [[ "$(wc -l < "$calls")" -eq 1 ]] || fail "s3info was not read exactly once"
    [[ "$RCLONE_CONFIG_MYREMOTE_TYPE" == s3 ]] || fail "TYPE was not set"
    [[ "$RCLONE_CONFIG_MYREMOTE_ENV_AUTH" == FALSE ]] || fail "ENV_AUTH was not set"
    [[ "$RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID" == ACCESS ]] || fail "access key was not set"
    [[ "$RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY" == SECRET ]] || fail "secret key was not set"
    [[ "$RCLONE_CONFIG_MYREMOTE_ENDPOINT" == s3.msi.umn.edu ]] || fail "endpoint was not canonical"
    [[ "$RCLONE_CONFIG_MYREMOTE_ACL" == private ]] || fail "ACL was not set"
    [[ "$RCLONE_CONFIG_MYREMOTE_PROVIDER" == Ceph ]] || fail "provider was not set"

    : > "$calls"
    RCLONE_CONFIG_MYREMOTE_TYPE=unchanged
    _setup_rclone_credentials configured
    [[ ! -s "$calls" ]] || fail "custom remote invoked s3info"
    [[ "$RCLONE_CONFIG_MYREMOTE_TYPE" == unchanged ]] || fail "custom remote changed MYREMOTE variables"
    unset -f s3info

    if (s3info() { return 1; }; _setup_rclone_credentials myremote) >/dev/null 2>&1; then
        fail "failed s3info command was accepted"
    fi
    if (s3info() { printf '\n'; }; _setup_rclone_credentials myremote) >/dev/null 2>&1; then
        fail "empty s3info credentials were accepted"
    fi
}

assert_script_credentials() {
    local script="$1"
    local expected="$2"

    bash -n "$script" || fail "generated script failed bash -n: $script"
    if [[ "$expected" == myremote ]]; then
        [[ "$(grep -c 'RCLONE_CONFIG_MYREMOTE_TYPE=s3' "$script")" -eq 1 ]] || fail "credential block count was not one: $script"
        grep -q 's3info --keys' "$script" || fail "runtime key lookup missing: $script"
        grep -q 'RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu' "$script" || fail "canonical endpoint missing: $script"
        if grep -q 'ACCESS SECRET\|test-access-key\|test-secret-key' "$script"; then
            fail "literal credentials were embedded: $script"
        fi
    elif grep -q 'RCLONE_CONFIG_MYREMOTE_' "$script"; then
        fail "custom remote received MYREMOTE credentials: $script"
    fi
}

test_generated_credentials() {
    local remote output script
    local source_dir="$TEMP_DIR/source"
    mkdir -p "$source_dir"
    source "$PROJECT_ROOT/src/plugins/vast2ceph/plugin.sh"
    source "$PROJECT_ROOT/src/plugins/dd2ceph/plugin.sh"
    source "$PROJECT_ROOT/src/plugins/filesinbackup/plugin.sh"

    for remote in myremote configured; do
        output="$TEMP_DIR/vast-$remote"
        mkdir -p "$output"
        _create_transfer_scripts "$source_dir" "$remote:bucket/path" "$output" "" 1 2 "$remote"
        for script in "$output"/*.slurm; do
            assert_script_credentials "$script" "$remote"
        done

        output="$TEMP_DIR/dd2ceph-$remote"
        mkdir -p "$output"
        (
            cd "$output"
            _create_dd2ceph_copy_and_verify_script "$remote:bucket" "$source_dir" "$output" job "" 2 1 "$remote"
        )
        assert_script_credentials "$output/job.1_copy_and_verify.slurm" "$remote"

        output="$TEMP_DIR/files-$remote"
        mkdir -p "$output"
        (
            cd "$output"
            _create_filesinbackup_slurm_script "$remote" bucket group "$source_dir" "$output" 3 timestamp 0
        )
        assert_script_credentials "$output/group_timestamp.slurm" "$remote"
    done
}

test_current_process_credentials
test_generated_credentials
printf 'Rclone credential tests passed\n'
