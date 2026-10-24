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
    local wall_time="$3"
    local cpus="$4"
    local memory="$5"

    bash -n "$script" || fail "generated script failed bash -n: $script"
    [[ -x "$script" ]] || fail "generated script is not executable: $script"
    [[ "$(grep -c '^#!/usr/bin/env bash$' "$script")" -eq 1 ]] || fail "shared shebang count was not one: $script"
    [[ "$(grep -c '^error_handler()' "$script")" -eq 1 ]] || fail "shared handler count was not one: $script"
    [[ "$(grep -c 'module load --force rclone/1.74.4' "$script")" -eq 1 ]] || fail "forced module load count was not one: $script"
    grep -q "^#SBATCH --time=${wall_time}$" "$script" || fail "incorrect wall time: $script"
    grep -q "^#SBATCH --cpus-per-task=${cpus}$" "$script" || fail "incorrect CPU count: $script"
    grep -q "^#SBATCH --mem=${memory}$" "$script" || fail "incorrect memory: $script"
    local last_directive first_command
    last_directive="$(grep -n '^#SBATCH ' "$script" | tail -1 | cut -d: -f1)"
    first_command="$(grep -n '^set -o errexit$' "$script" | cut -d: -f1)"
    [[ "$last_directive" -lt "$first_command" ]] || fail "SBATCH directives appear after commands: $script"
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
            case "$script" in
                *.2_delete.slurm) assert_script_credentials "$script" "$remote" 8:00:00 2 16gb ;;
                *) assert_script_credentials "$script" "$remote" 24:00:00 2 32gb ;;
            esac
        done

        output="$TEMP_DIR/dd2ceph-$remote"
        mkdir -p "$output"
        (
            cd "$output"
            _create_dd2ceph_copy_and_verify_script "$remote:bucket" "$source_dir" "$output" job "" 2 1 "$remote"
        )
        assert_script_credentials "$output/job.1_copy_and_verify.slurm" "$remote" 24:00:00 2 32gb

        output="$TEMP_DIR/files-$remote"
        mkdir -p "$output"
        (
            cd "$output"
            _create_filesinbackup_slurm_script "$remote" bucket group "$source_dir" "$output" 3 timestamp 0
        )
        assert_script_credentials "$output/group_timestamp.slurm" "$remote" 2:00:00 3 16gb
    done

    source "$PROJECT_ROOT/src/plugins/dd2dr/plugin.sh"
    output="$TEMP_DIR/dd2dr"
    mkdir -p "$output"
    (
        cd "$output"
        _create_comprehensive_dd2dr_script group "$source_dir" "$output/recovery" "$output" 1 4 timestamp
    )
    assert_script_credentials "$output/group_timestamp.slurm" custom 24:00:00 4 32gb
}

test_current_process_credentials
test_generated_credentials
printf 'Rclone credential tests passed\n'
