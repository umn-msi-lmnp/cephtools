#!/usr/bin/env bash
###############################################################################
# dd2ceph Plugin for cephtools
# Archiving tool to copy any new data from the "data_delivery" directory to tier 2 (ceph).
###############################################################################

# Plugin metadata
PLUGIN_NAME="dd2ceph"

PLUGIN_DESCRIPTION="Archive tool to copy data from data_delivery to ceph"

###############################################################################
# Plugin Interface Functions
###############################################################################

plugin_describe() {
cat <<HEREDOC
---------------------------------------------------------------------
Usage:
    ${_ME} dd2ceph [options] --group <GROUP>

Options:                            
    -r|--remote <STRING>    [Optional] Rclone remote name. (use "rclone listremotes" for available
                            remotes). Rclone remotes must be set up using "rclone init"
                            and can be viewed at: ~/.config/rclone/rclone.conf. This option
                            is not required. If you do not specify --remote, the tool will 
                            automatically identify your MSI ceph keys and set the remote. 
                            This option was left here for backward compatibility. 

    -g|--group <STRING>     MSI group ID (required). Your current group is $(id -ng). Used to set default bucket name.

    -b|--bucket <STRING>    [Optional] Name of the ceph bucket that data should be used for the 
                            transfer. [Default = "data-delivery-$(id -ng)"]
    
    -p|--path <STRING>      Absolute or relative path to the directory that should be 
                            transfered. [Default = "$MSIPROJECT/data_delivery"]
                            
    -l|--log_dir <STRING>   Absolute or relative path to the directory where log files 
                            are saved. [Default = "$MSIPROJECT/shared/cephtools/dd2ceph"]
    
    -d|--dry_run            Dry run option will be enabled in the rclone commands (so nothing 
                            will be transfered or deleted when scripts run). Also, the slurm 
                            scripts will be written, but not automatically launched, so you can
                            review them.
     
    -e|--delete_empty_dirs  Do NOT transfer empty dirs from source to ceph. [Default is to 
                            preserve empty dirs using custom marker files instead of 
                            rclone's problematic --s3-directory-markers flag which can 
                            cause compatibility issues. Setting this flag will skip 
                            empty directory preservation entirely.]
    
    -v|--verbose            Verbose mode (print additional info).
                            
    -t|--threads <INT>      Threads to use for uploading with rclone. [Default = 16].
    

Description:
  Archiving tool to copy any new data from the "data_delivery" directory to tier 2 (ceph).
  
Help (print this screen):
    ${_ME} help dd2ceph

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
Repo: https://github.com/umn-msi-lmnp/cephtools  

Version: @VERSION_SHORT@
---------------------------------------------------------------------
HEREDOC
}

plugin_main() {
    # Show help if no arguments provided
    if [[ $# -eq 0 ]]; then
        plugin_describe
        return 0
    fi

    # Parse Options ###############################################################

    # Initialize program option variables.
    local _remote="myremote"
    local _group=
    local _bucket=
    local _path=
    local _path_provided=0
    local _log_dir=
    local _log_dir_provided=0
    local _dry_run=
    local _verbose=0
    local _delete_empty_dirs=0
    local _threads="16"

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

    # Note: __validate_bucket_name() is now defined in common.sh

    # For flags (i.e. no corresponding value), do not shift inside the case testing
    # statement. For options with required value, shift inside case testing statement, 
    # so the loop moves twice. 
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -d|--dry_run)
            _dry_run="--dry-run"
            ;;
         -v|--verbose)
             _verbose=1
             ;;
         -e|--delete_empty_dirs)
             _delete_empty_dirs=1
             ;;
         -r|--remote)
             _remote="$(__get_option_value "${__arg}" "${__val:-}")"
             shift
             ;;
        -b|--bucket)
            _bucket="$(__validate_bucket_name "$(__get_option_value "${__arg}" "${__val:-}")")"
            shift
            ;;
        -g|--group)
            _group="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -p|--path)
            _path="$(__get_option_value "${__arg}" "${__val:-}")"
            _path_provided=1
            shift
            ;;
        -l|--log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            _log_dir_provided=1
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
    shift $((OPTIND-1))

    # Validate required parameters
    if [[ -z "${_group:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--group' is required.\\n"
    fi

    # Set defaults based on group if not explicitly provided
    if [[ -z "${_bucket:-}" ]]; then
        _bucket="data-delivery-${_group}"
    fi
    
    if [[ $_path_provided -eq 0 ]]; then
        _path="/projects/standard/${_group}/data_delivery"
    fi
    
    if [[ $_log_dir_provided -eq 0 ]]; then
        # Use TEST_OUTPUT_DIR in test environment
        if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
            _log_dir="$TEST_OUTPUT_DIR/dd2ceph"
        else
            _log_dir="/projects/standard/${_group}/shared/cephtools/dd2ceph"
        fi
    fi

    # Setup rclone credentials if using default remote
    if [[ "$_remote" == "myremote" ]]; then
        if command -v s3info >/dev/null 2>&1; then
            export RCLONE_CONFIG_MYREMOTE_TYPE=s3
            export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE
            RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID="$(s3info --keys | awk '{print $1}')"
            RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY="$(s3info --keys | awk '{print $2}')"
            export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY
            export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu
            export RCLONE_CONFIG_MYREMOTE_ACL=private
            export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph
        else
            _exit_1 printf "s3info failed\\n"
        fi
    fi

    _verb printf "Program options used:\\n"
    _verb printf "group: %s\\n" "$_group"
    _verb printf "remote: %s\\n" "$_remote"
    _verb printf "bucket: %s\\n" "$_bucket"
    _verb printf "path: %s\\n" "$_path"
    _verb printf "log_dir: %s\\n" "$_log_dir"
     _verb printf "dry_run: %s\\n" "$_dry_run"
     _verb printf "verbose: %s\\n" "$_verbose"
     _verb printf "delete_empty_dirs: %s\\n" "$([[ ${_delete_empty_dirs} -eq 1 ]] && echo "enabled" || echo "disabled")"
     _verb printf "threads: %s\\n" "$_threads"

    # Validate and normalize path
    _root_path_dir=$(readlink -m "${_path}")
    if [ ! -d "${_root_path_dir}" ]; then
        _exit_1 printf "The '--path' option specified is not a valid directory. \\nReadlink does not convert to a valid directory: 'readlink -m %s'\\n" "${_path}"
    fi

    # Create log directory if needed
    if [ ! -d "${_log_dir}" ]; then
        _warn printf "The '--log_dir' option specified is not a valid directory. Creating the dir with g+rwx permissions: '%s'\\n" "${_log_dir}"
        mkdir -p ${_log_dir}
        chmod g+rwx ${_log_dir}
    fi

    _info printf "Starting dd2ceph transfer preparation\\n"
    _info printf "Source: %s\\n" "${_root_path_dir}"
    _info printf "Destination: %s:%s\\n" "${_remote}" "${_bucket}"
    
    # Run comprehensive pre-flight checks (skip source permission checks for read-only data_delivery)
    if ! _run_preflight_checks "${_root_path_dir}" "${_remote}" "${_bucket}" "${_log_dir}" "${_dry_run}" "false"; then
        if [[ -z "${_dry_run}" ]]; then
            _exit_1 printf "Pre-flight checks failed. Use --dry_run to proceed anyway, or fix issues first.\\n"
            return 1
        else
            _warn printf "Pre-flight checks had issues, but continuing with dry run.\\n"
        fi
    fi

    # Check s3cmd availability
    _check_s3cmd_access "$_bucket" "$_dry_run"

     # Execute the main workflow
     _execute_dd2ceph_workflow "$_remote" "$_bucket" "$_root_path_dir" "$_log_dir" "$_dry_run" "$_threads" "$_delete_empty_dirs"
}

###############################################################################
# Helper Functions
###############################################################################

# Note: _check_rclone_version() is now defined in common.sh

_validate_remote_and_bucket() {
    local remote="$1"
    local bucket="$2"

    # Make sure the remote exists
    if ! rclone listremotes | grep -q "^$remote:\$"; then
       _exit_1 printf "Rclone remote does not exist: %s\\nCheck available remotes by running 'rclone listremotes', or set one up by running 'rclone init'.\\n" "$remote"
    fi

    # Make sure access to bucket is possible
    if ! rclone lsf ${remote}:${bucket} &>/dev/null; then
        _exit_1 printf "Errors occured when accessing bucket: '%s'\\nDoes the bucket exist?\\nDo you have access rights to the bucket?\\nCheck the bucket access policy using 's3cmd info s3://%s'\\nOr the MSI group PI should create the bucket using 's3cmd mb s3://%s'\\n" "${bucket}" "${bucket}" "${bucket}"
    fi
}

_check_s3cmd_access() {
    local bucket="$1"
    local dry_run="${2:-}"
    
    # Only need to check that we can access s3cmd commands
    if command -v s3cmd &> /dev/null; then
        _verb printf "Using s3cmd found in PATH: %s\\n" "$(which s3cmd)"
        _verb printf "%s\\n" "$(s3cmd --version)" 
    else
        _exit_1 printf "s3cmd could not be found in PATH\\n"
    fi

    # Skip actual bucket access check in dry run mode to avoid credential issues
    if [[ -n "${dry_run}" ]]; then
        _info printf "Skipping bucket access check (dry run mode)\\n"
        return 0
    fi

    # check that bucket exists
    if s3cmd ls s3://${bucket} &>/dev/null; then
        _info printf "Bucket was accessed: %s\\n" "${bucket}"
    else
        _exit_1 printf "Errors occured when accessing bucket: '%s'\\nDo you have access rights to the bucket?\\nCheck the bucket access policy using 's3cmd info s3://%s'\\nIf bucket does not exist run cephtools bucketpolicy first\\n" "${bucket}" "${bucket}"
    fi
}

 _execute_dd2ceph_workflow() {
     local remote="$1"
     local bucket="$2"
     local root_path_dir="$3"
     local log_dir="$4"
     local dry_run="$5"
     local threads="$6"
     local delete_empty_dirs="$7"

    # Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
    umask 0007

    # Create archive working dir
    local archive_date_time="$(date +"%Y-%m-%d-%H%M%S")-$(date +"%N" | cut -c1-6)"
    local myprefix="dd2ceph_${archive_date_time}"
    local myprefix_dir="${log_dir}/${bucket}___${myprefix}"

    _verb printf "Archive dir name: %s\\n" ${myprefix_dir}
    mkdir -p ${myprefix_dir}
    chmod g+rwx ${myprefix_dir}
    cd ${myprefix_dir}

    # Get a file list
    _verb printf "Creating the archive file list. This might take a while for large dirs...\\n"
    rclone lsf -R --copy-links ${root_path_dir} > ${myprefix}.filelist.txt
    
    # Prefix the files with full pathname
    sed -i -e "s|^|${root_path_dir}/|" ${myprefix}.filelist.txt

    # Check for filenames or pathnames that are too long
    _check_pathname_lengths "${myprefix}"

     # Create the transfer scripts
     _create_dd2ceph_copy_and_verify_script "${remote}" "${bucket}" "${root_path_dir}" "${myprefix_dir}" "${myprefix}" "${dry_run}" "${threads}" "${delete_empty_dirs}"

    #######################################################################
    # Print instructions to terminal
    #######################################################################

    # Use a temp function to create multi-line string without affecting exit code
    # https://stackoverflow.com/a/8088167/2367748
    heredoc2var(){ IFS='\n' read -r -d '' ${1} || true; }
    
    local instructions_message
    heredoc2var instructions_message << HEREDOC

---------------------------------------------------------------------
cephtools dd2ceph summary


Options used:
dry_run=${dry_run}
delete_empty_dirs=${delete_empty_dirs}
remote=${remote}
bucket=${bucket}
threads=${threads}


Source dir: 
${root_path_dir}


Archive dir transfer scripts:
${myprefix_dir}


Archive transfer files created and file transfer script started! 
Next steps:
1. Move into log dir: cd ${myprefix_dir}
2. Review the *.readme.md file for details.
3. Review the ${myprefix}.filelist.txt file. Any files not already on ceph, will be copied to ceph.
4. Launch the copy and verify jobfile: sbatch ${myprefix}.1_copy_and_verify.slurm




VERSION: @VERSION_SHORT@
QUESTIONS: lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools
---------------------------------------------------------------------
HEREDOC

    echo "$instructions_message"
}

_check_pathname_lengths() {
    local myprefix="$1"
    local pathname_max=1024

    # Are there any with filenames that are too long? They need to be less than 1024 characters.
    awk '{ PATHNAME=$0; print length(PATHNAME)"\t"PATHNAME}' ${myprefix}.filelist.txt | awk -v pathname_max=$pathname_max -v out_file="${myprefix}.filelist.paths_too_long.txt" '{if ($1 >= pathname_max) {print $0 > out_file}}'

    if [[ -s "${myprefix}.filelist.paths_too_long.txt" ]]; then
        _exit_1 printf "There are files with pathnames that are too long (>= %s characters). These items cannot be transferred. Review them here: '%s/%s'. You may be able to create a symbolic link to the parent directory to shorten the path length.\\n" "$pathname_max" "$(pwd)" "${myprefix}.filelist.paths_too_long.txt"
    else
        _verb printf "All pathnames are acceptable lengths (< %s characters)\\n" "$pathname_max"
    fi
}

 _create_dd2ceph_copy_and_verify_script() {
     local remote="$1"
     local bucket="$2"
     local root_path_dir="$3" 
     local myprefix_dir="$4"
     local myprefix="$5"
     local dry_run="$6"
     local threads="$7"
     local delete_empty_dirs="$8"

    # Create the combined copy and verify script
    cat > "${myprefix}.1_copy_and_verify.slurm" <<EOF
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

# Load required modules - try to get consistent rclone version
# Force load consistent rclone version, overriding any sticky modules
if ! module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
    echo "Error: Failed to load rclone/1.71.0-r1 module even with --force flag"
    exit 1
fi
echo "Successfully loaded rclone/1.71.0-r1 module"
echo "Using rclone: $(command -v rclone)"
echo "Version: $(rclone --version 2>/dev/null | head -1 || echo 'version unknown')"

echo "SLURM Script generated by cephtools @VERSION_SHORT@"
echo "Build Date: @BUILD_DATE@"
echo "Git Info: @GIT_CURRENT_BRANCH@@GIT_LATEST_COMMIT_SHORT@@GIT_LATEST_COMMIT_DIRTY@ (@GIT_LATEST_COMMIT_DATETIME@)"
echo "Source: @GIT_WEB_URL@"
echo ""

# Set umask for group-writable files (660) and directories (770)
umask 0007

# Set up credentials for myremote
$(if command -v s3info >/dev/null 2>&1; then
    echo "export RCLONE_CONFIG_MYREMOTE_TYPE=s3"
    echo "export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE"
    echo "export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')"
    echo "export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')"
    echo "export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu"
    echo "export RCLONE_CONFIG_MYREMOTE_ACL=private"
    echo "export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph"
fi)

# Change to working directory
cd ${myprefix_dir}

# Pre-transfer validation
echo "Performing pre-transfer validation..."

# Quick permission check
echo "Checking source directory accessibility..."
if [[ ! -r "${root_path_dir}" ]]; then
    echo "ERROR: Cannot read source directory: ${root_path_dir}"
    exit 1
fi

echo "✓ Source directory is accessible"

# Perform the transfer
echo "Starting dd2ceph transfer at \$(date)"
echo "Source: ${root_path_dir}"
echo "Destination: ${remote}:${bucket}"

$(if [[ ${delete_empty_dirs} -eq 0 ]]; then
    echo "echo \"Using custom empty directory handling...\""
    echo ""
    echo "# Find empty directories"
    echo "empty_dirs_file=\"${myprefix}.empty_dirs.txt\""
    echo "find \"${root_path_dir}\" -type d -empty > \"\$empty_dirs_file\" 2>/dev/null || true"
    echo "empty_count=\$(wc -l < \"\$empty_dirs_file\" 2>/dev/null || echo \"0\")"
    echo "echo \"Found \$empty_count empty directories\""
    echo ""
    echo "# Main file transfer"
    echo "# Note: We skip the README.txt at the top of the file tree only because it is a"
    echo "# symlink that cannot be resolved, but it is not actual data that needs to be backed up."
    echo "# Without skipping this file, rclone will error."
    echo "rclone copy \"${root_path_dir}\" \"${remote}:${bucket}\" \\"
    echo "    --copy-links \\"
    echo "    --transfers ${threads} \\"
    echo "    --progress \\"
    echo "    --stats 30s \\"
    echo "    --exclude \"/README.txt\" \\"
    echo "    ${dry_run} \\"
    echo "    --log-file \"${myprefix}.1_copy.rclone.log\" \\"
    echo "    --log-level INFO"
    echo ""
    echo "# Create marker files for empty directories using temp directory approach"
    echo "marker_temp_dir=\"\$(mktemp -d -t cephtools_markers.XXXXXX)\""
    echo "mkdir -p \"\$marker_temp_dir\""
    echo "marker_count=0"
    echo "while IFS= read -r empty_dir; do"
    echo "    if [[ -n \"\$empty_dir\" && -d \"\$empty_dir\" ]]; then"
    echo "        # Convert absolute source path to relative path"
    echo "        relative_path=\"\${empty_dir#${root_path_dir}}\""
    echo "        # Remove leading slash if present"
    echo "        relative_path=\"\${relative_path#/}\""
    echo "        # Create local marker file in temp directory structure"
    echo "        marker_dir=\"\$marker_temp_dir/\$relative_path\""
    echo "        mkdir -p \"\$marker_dir\""
    echo "        echo \"This file marks an empty directory for cephtools transfer - created \$(date)\" > \"\$marker_dir/.cephtools_empty_dir_marker\""
    echo "        marker_count=\$((marker_count + 1))"
    echo "    fi"
    echo "done < \"\$empty_dirs_file\""
    echo ""
    echo "# Copy all marker files to bucket in one operation"
    echo "if [[ \$marker_count -gt 0 ]]; then"
    echo "    echo \"Copying \$marker_count empty directory markers to bucket...\""
    echo "    if rclone copy \"\$marker_temp_dir\" \"${remote}:${bucket}\" --copy-links ${dry_run} --log-level INFO; then"
    echo "        echo \"Successfully placed markers in \$marker_count empty directories\""
    echo "    else"
    echo "        echo \"Warning: Failed to copy some empty directory markers\""
    echo "    fi"
    echo "else"
    echo "    echo \"No empty directories found to mark\""
    echo "fi"
    echo ""
    echo "# Clean up temporary marker directory"
    echo "rm -rf \"\$marker_temp_dir\""
else
    echo "echo \"Skipping empty directories (--delete_empty_dirs flag set)...\""
    echo "# Note: We skip the README.txt at the top of the file tree only because it is a"
    echo "# symlink that cannot be resolved, but it is not actual data that needs to be backed up."
    echo "# Without skipping this file, rclone will error."
    echo "rclone copy \"${root_path_dir}\" \"${remote}:${bucket}\" \\"
    echo "    --copy-links \\"
    echo "    --transfers ${threads} \\"
    echo "    --progress \\"
    echo "    --stats 30s \\"
    echo "    --exclude \"/README.txt\" \\"
    echo "    ${dry_run} \\"
    echo "    --log-file \"${myprefix}.1_copy.rclone.log\" \\"
    echo "    --log-level INFO"
fi)

echo "Transfer completed at \$(date)"

# Verify the transfer immediately
echo "Starting verification at \$(date)"  
rclone check "${root_path_dir}" "${remote}:${bucket}" \\
    --copy-links \\
    --exclude "/README.txt" \\
    --log-file "${myprefix}.1_verify.rclone.log" \\
    --progress \\
    --log-level DEBUG \\
    --transfers ${threads} \\
    --checkers ${threads} \\
    --retries 5 \\
    --low-level-retries 20 \\
    --one-way \\
    --differ "${myprefix}.1_verify.rclone.differ.txt" \\
    --missing-on-dst "${myprefix}.1_verify.rclone.missing-on-tier2.txt" \\
    --error "${myprefix}.1_verify.rclone.error.txt"
echo "Verification completed at \$(date)"

echo "Copy and verification completed at \$(date)"

# Create success marker file to indicate successful completion
echo "Creating success marker file..."
echo "Copy and verify operations completed successfully at \$(date)" > "${myprefix}.copy_and_verify_SUCCESS.txt"
EOF

    chmod +x "${myprefix}.1_copy_and_verify.slurm"
    
    _info printf "Created SLURM script: %s\\n" "${myprefix}.1_copy_and_verify.slurm"
}
