#!/usr/bin/env bash
###############################################################################
# dd2dr Plugin for cephtools
# Copy data from data delivery to disaster recovery.
###############################################################################

# Plugin metadata
PLUGIN_NAME="dd2dr"

PLUGIN_DESCRIPTION="Copy data from data delivery to disaster recovery"

###############################################################################
# Plugin Interface Functions
###############################################################################

plugin_describe() {
cat <<HEREDOC
---------------------------------------------------------------------
Usage:
    ${_ME} dd2dr [options] --group

Options:
    -g|--group <STRING>     MSI group ID (required)

    -l|--log_dir           Absolute or relative path to directory where log files are
                           saved. [Default: "$MSIPROJECT/shared/cephtools/dd2dr"]
                           
    -d|--dry_run           Dry run option will be applied to rclone commands. Nothing 
                           transfered or deleted when scripts run.
    
    -v|--verbose           Verbose mode (print additional info).

Description:
  Copy data from data delivery to disaster recovery. 
  
Help (print this screen):
    ${_ME} help dd2dr

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
GitHub: https://github.com/umn-msi-lmnp/cephtools

Version: @VERSION_SHORT@
---------------------------------------------------------------------
HEREDOC
}

plugin_main() {
    # Note: Don't exit early for no arguments - let validation handle required params

    # Parse Options ###############################################################

    # Initialize program option variables.
    local _group=
    local _dry_run=0
    # Set default log directory - use TEST_OUTPUT_DIR in test environment
    if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
        local _log_dir="$TEST_OUTPUT_DIR/dd2dr"
    else
        local _log_dir="$MSIPROJECT/shared/cephtools/dd2dr"
    fi
    local _threads=8
    local _verbose=0

    # __get_option_value()
    #
    # Usage:
    #   __get_option_value <option> <value>
    #
    # Description:
    #  Given a flag (e.g., -e | --example) return the value or exit 1 if value
    #  is blank or appears to be another option.
    __get_option_value() {
      local __arg="${1:-}"
      local __val="${2:-}"
      
      if [[ -n "${__val:-}" ]] && [[ ! "${__val:-}" =~ ^- ]]
      then
        printf "%s\\n" "${__val}"
      else
        _exit_1 printf "%s requires a valid argument.\\n" "${__arg}"
      fi
    }

    # Parse command line arguments
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -d|--dry_run)
            _dry_run=1
            ;;
        -v|--verbose)
            _verbose=1
            ;;
        -g|--group)
            _group="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -l|--log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -t|--threads)
            _threads="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        --endopts)
            # Terminate option parsing.
            break
            ;;
        -*)
            _exit_1 printf "Unexpected option: %s\\n" "${__arg}"
            ;;
        *)
            plugin_describe
            _exit_1 printf "Unexpected positional arg: %s\\n" "${__arg}"
            ;;
        esac

        shift
    done

    # Set verbose mode if requested
    if [[ ${_verbose} -eq 1 ]]; then
        _USE_VERBOSE=1
    fi

    # Validate required parameters
    if [[ -z "${_group:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--group' is required.\\n"
    fi

    _verb printf "Program options used:\\n"
    _verb printf "group: %s\\n" "$_group"
    _verb printf "log_dir: %s\\n" "$_log_dir"
    _verb printf "threads: %s\\n" "$_threads"
    _verb printf "dry_run: %s\\n" "$([[ ${_dry_run} -eq 1 ]] && echo "yes" || echo "no")"

    # Execute the main workflow
    _execute_dd2dr_workflow "$_group" "$_log_dir" "$_dry_run" "$_threads"
}

###############################################################################
# Helper Functions
###############################################################################

_execute_dd2dr_workflow() {
    local group="$1"
    local log_dir="$2"
    local dry_run="$3"
    local threads="$4"

    # Validate group directory structure
    local data_delivery_path="$MSIPROJECT/data_delivery"
    local disaster_recovery_path="$MSIPROJECT/shared/disaster_recovery"

    if [[ ! -d "$data_delivery_path" ]]; then
        _exit_1 printf "Data delivery directory does not exist: %s\\n" "$data_delivery_path"
    fi

    # Check rclone version and load appropriate module
    _info printf "Checking rclone version...\\n"
    _check_rclone_version

    # Create log directory if needed
    if [[ ! -d "$log_dir" ]]; then
        _info printf "Creating log directory: %s\\n" "$log_dir"
        mkdir -p "$log_dir"
        chmod g+rwx "$log_dir"
    fi

    # Create disaster recovery directory if needed
    if [[ ! -d "$disaster_recovery_path" ]]; then
        _info printf "Creating disaster recovery directory: %s\\n" "$disaster_recovery_path"
        mkdir -p "$disaster_recovery_path"
        chmod g+rwx "$disaster_recovery_path"
    fi

    # Create working directory
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")-$(date +"%N" | cut -c1-6)"
    local work_dir="${log_dir}/dd2dr_${group}_${timestamp}"
    
    _info printf "Creating working directory: %s\\n" "$work_dir"
    mkdir -p -m u=rwx,g=rx,o= "$work_dir"
    cd "$work_dir"

    # Create comprehensive dd2dr SLURM script with full functionality
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")-$(date +"%N" | cut -c1-6)"
    _create_comprehensive_dd2dr_script "$group" "$data_delivery_path" "$disaster_recovery_path" "$work_dir" "$dry_run" "$threads" "$timestamp"

    #######################################################################
    # Print instructions to terminal
    #######################################################################

    # Use a temp function to create multi-line string without affecting exit code
    # https://stackoverflow.com/a/8088167/2367748
    heredoc2var(){ IFS='\n' read -r -d '' ${1} || true; }
    
    local instructions_message
    heredoc2var instructions_message << HEREDOC

---------------------------------------------------------------------
cephtools dd2dr summary


Options used:
group=${group}
dry_run=$([[ ${dry_run} -eq 1 ]] && echo "enabled" || echo "disabled")
threads=${threads}
log_dir=${log_dir}


Source dir: 
${data_delivery_path}


Destination dir:
${disaster_recovery_path}


Transfer script created in:
${work_dir}


Transfer files created and ready to launch!
Next steps:
1. Move into log dir: cd ${work_dir}
2. Review the generated SLURM script for details.
3. Launch the transfer jobfile: sbatch ${group}_${timestamp}.slurm
4. After successful transfer, review the generated file lists for verification.




VERSION: @VERSION_SHORT@
QUESTIONS: lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools
---------------------------------------------------------------------
HEREDOC

    echo "$instructions_message"
}

_create_comprehensive_dd2dr_script() {
    local group="$1"
    local data_delivery_path="$2"
    local disaster_recovery_path="$3"
    local work_dir="$4"
    local dry_run="$5"
    local threads="$6"
    local timestamp="$7"
    local script_name="${group}_${timestamp}.slurm"
    local dry_run_flag=""
    
    if [[ ${dry_run} -eq 1 ]]; then
        dry_run_flag="--dry-run"
    fi

    cat > "$script_name" <<EOF
#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --partition=msismall
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Generated by cephtools @VERSION_SHORT@
# Build Date: @BUILD_DATE@
# Git Branch: @GIT_CURRENT_BRANCH@
# Git Commit: @GIT_LATEST_COMMIT_SHORT@@GIT_LATEST_COMMIT_DIRTY@
# Git Commit Date: @GIT_LATEST_COMMIT_DATETIME@
# Source: @GIT_WEB_URL@

# ------------------------------------------------------------------------------
# Bash safe mode
# ------------------------------------------------------------------------------

# --- Safe defaults ---
set -o errexit   # Exit immediately if a command fails
set -o nounset   # Treat unset variables as an error
set -o pipefail  # Fail if any part of a pipeline fails
set -o errtrace  # Inherit ERR traps in functions/subshells

# Uncomment if you use DEBUG/RETURN traps (rare in production)
# set -o functrace  

# Error handler
error_handler() {
    local exit_code=\$?
    local cmd="\${BASH_COMMAND}"
    local line="\${BASH_LINENO[0]}"
    local src="\${BASH_SOURCE[1]:-main script}"

    >&2 echo "ERROR [\$(date)]"
    >&2 echo "  File: \$src"
    >&2 echo "  Line: \$line"
    >&2 echo "  Command: \$cmd"
    >&2 echo "  Exit code: \$exit_code"

    exit "\$exit_code"
}

# Exit handler (always runs on exit)
on_exit() {
    local exit_code=\$?
    echo "Exiting script (code \$exit_code) [\$(date)]"
    # Add temp file cleanup or resource release here
}

# Signal handlers
on_interrupt() {
    echo "Interrupt signal (SIGINT) received. Exiting."
    exit 130   # 128 + SIGINT(2)
}

on_terminate() {
    echo "Terminate signal (SIGTERM) received. Exiting."
    exit 143   # 128 + SIGTERM(15)
}

on_quit() {
    echo "Quit signal (SIGQUIT) received. Exiting."
    exit 131   # 128 + SIGQUIT(3)
}

# Trap setup
trap error_handler ERR # calls error_handler when a command fails.
trap on_exit EXIT # Runs no matter how the script ends.
trap on_interrupt INT # handles Ctrl-C.
trap on_terminate TERM # handles kill or system shutdown signals
trap on_quit QUIT # handles Ctrl-\ (prevents core dump).

# Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
umask 0007

# Load required modules
# Force load consistent rclone version, overriding any sticky modules
if ! module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
    echo "Error: Failed to load rclone/1.71.0-r1 module even with --force flag"
    exit 1
else
    echo "Successfully loaded rclone/1.71.0-r1 module"
fi
echo "Using rclone: $(command -v rclone)"
echo "Version: $(rclone --version 2>/dev/null | head -1 || echo 'version unknown')"

# Change to working directory
cd ${work_dir}

# Set variables from dd2dr_commands.sh integration
GROUP="${group}"
DATESTAMP="${timestamp}"

# Print some info
echo "\$GROUP sync starting..."
echo "\${DATESTAMP}"

# Check available disk space before transfer
echo "Checking disk space availability..."
DEST_AVAIL=\$(df "${disaster_recovery_path}" | awk 'NR==2 {print \$4}')
DEST_AVAIL_MB=\$((DEST_AVAIL / 1024))

echo "Available space in disaster recovery directory: \${DEST_AVAIL_MB} MB"

# Estimate source data size
SOURCE_SIZE=\$(du -sk "${data_delivery_path}" 2>/dev/null | cut -f1)
SOURCE_SIZE_MB=\$((SOURCE_SIZE / 1024))

echo "Source data size: \${SOURCE_SIZE_MB} MB"

# Check if there's enough space (with 10% buffer)
REQUIRED_SPACE=\$((SOURCE_SIZE_MB * 11 / 10))
if [ \$DEST_AVAIL_MB -lt \$REQUIRED_SPACE ]; then
    echo "ERROR: Not enough space in disaster recovery directory"
    echo "Required: \${REQUIRED_SPACE} MB (with 10% buffer)"
    echo "Available: \${DEST_AVAIL_MB} MB"
    exit 1
fi

echo "✓ Sufficient disk space available"

echo "SLURM Script generated by cephtools @VERSION_SHORT@"
echo "Build Date: @BUILD_DATE@"
echo "Git Info: @GIT_CURRENT_BRANCH@@GIT_LATEST_COMMIT_SHORT@@GIT_LATEST_COMMIT_DIRTY@ (@GIT_LATEST_COMMIT_DATETIME@)"
echo "Source: @GIT_WEB_URL@"
echo ""

# Transfer the files from data_delivery to disaster_recovery
echo "Starting sync from data_delivery to disaster_recovery..."

# Use rclone to copy files
rclone copy ${data_delivery_path} ${disaster_recovery_path}/ \\
    --copy-links \\
    --transfers ${threads} \\
    --checkers ${threads} \\
    --progress \\
    --stats 30s \\
    ${dry_run_flag}

# Check if rclone finished successfully
if [ "\$?" -eq 0 ]; then
    echo "rclone copy finished successfully!"
    echo "Sync complete"
else
    echo "rclone copy did not finish successfully"
    exit 5
fi

echo "dd2dr sync completed at \$(date)"

# Generate file list for disaster recovery
echo "Generating file list..."
if [ -d "${disaster_recovery_path}/data_delivery" ]; then
    find "${disaster_recovery_path}/data_delivery" -type f > ${group}_${timestamp}.disaster_recovery_files.txt
    echo "Destination file list: ${group}_${timestamp}.disaster_recovery_files.txt"
fi

echo "Reports available in: ${work_dir}"
EOF

    chmod +x "$script_name"
    
    _info printf "Created dd2dr SLURM script: %s\\n" "$script_name"
}
