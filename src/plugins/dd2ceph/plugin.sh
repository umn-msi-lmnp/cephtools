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
    ${_ME} dd2ceph [options] --bucket <BUCKET> --path <DIR_PATH>

Options:                            
    -r|--remote <STRING>    [Optional] Rclone remote name. (use "rclone listremotes" for available
                            remotes). Rclone remotes must be set up using "rclone init"
                            and can be viewed at: ~/.config/rclone/rclone.conf. This option
                            is not required. If you do not specify --remote, the tool will 
                            automatically identify your MSI ceph keys and set the remote. 
                            This option was left here for backward compatibility. 

    -b|--bucket <STRING>    Name of the ceph bucket that data should be used for the 
                            transfer. [Default = "$(id -ng)-data-archive"]
    
    -p|--path <STRING>      Absolute or relative path to the directory that should be 
                            transfered. [Default = "$MSIPROJECT/data_delivery"]
                            
    -l|--log_dir <STRING>   Absolute or relative path to the directory where log files 
                            are saved. [Default = "$MSIPROJECT/shared/cephtools/dd2ceph"]
    
    -d|--dry_run            Dry run option will be enabled in the rclone commands (so nothing 
                            will be transfered or deleted when scripts run). Also, the slurm 
                            scripts will be written, but not automatically launched, so you can
                            review them.
    
    -v|--verbose            Verbose mode (print additional info).
                            
    -t|--threads <INT>      Threads to use for uploading with rclone. [Default = 16].
    

Description:
  Archiving tool to copy any new data from the "data_delivery" directory to tier 2 (ceph).
  
Help (print this screen):
    ${_ME} help dd2ceph

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
Repo: https://github.umn.edu/lmnp/cephtools  

Version: $VERSION_SHORT
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
    local _bucket="$(id -ng)-data-archive"
    local _path="$MSIPROJECT/data_delivery"
    local _log_dir="$MSIPROJECT/shared/cephtools/dd2ceph"
    local _dry_run=
    local _verbose=0
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

    # __validate_bucket_name()
    #
    # Usage:
    #   __validate_bucket_name <bucket_name>
    #
    # Description:
    #   Validates bucket name format and removes common problematic patterns
    __validate_bucket_name() {
      local bucket_name="${1:-}"
      
      if [[ -z "$bucket_name" ]]; then
        _exit_1 printf "Bucket name cannot be empty\\n"
      fi
      
      # Remove trailing slash if present
      bucket_name="${bucket_name%/}"
      
      # Check if bucket name is now empty after removing slash
      if [[ -z "$bucket_name" ]]; then
        _exit_1 printf "Bucket name cannot be just a slash. Please provide a valid bucket name.\\n"
      fi
      
      # Warn about other potential issues
      if [[ "$bucket_name" == *"/"* ]]; then
        _warn printf "Bucket name contains slashes which may cause issues: '%s'\\n" "$bucket_name"
      fi
      
      printf "%s\\n" "$bucket_name"
    }

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
        -r|--remote)
             _remote="$(__get_option_value "${__arg}" "${__val:-}")"
             shift
             ;;
        -b|--bucket)
            _bucket="$(__validate_bucket_name "$(__get_option_value "${__arg}" "${__val:-}")")"
            shift
            ;;
        -p|--path)
            _path="$(__get_option_value "${__arg}" "${__val:-}")"
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

    # ---------------------------------------------------------------------
    # Check and print input options
    # ---------------------------------------------------------------------

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
    _verb printf "remote: %s\\n" "$_remote"
    _verb printf "bucket: %s\\n" "$_bucket"
    _verb printf "path: %s\\n" "$_path"
    _verb printf "log_dir: %s\\n" "$_log_dir"
    _verb printf "dry_run: %s\\n" "$_dry_run"
    _verb printf "verbose: %s\\n" "$_verbose"
    _verb printf "threads: %s\\n" "$_threads"

    # If required options are empty or null, exit.
    _root_path_dir=$(readlink -m "${_path}")
    if [ ! -d "${_root_path_dir}" ]; then
        _exit_1 printf "The '--path' option specified is not a valid directory. \\nReadlink does not convert to a valid directory: 'readlink -m %s'\\n" "${_path}"
    fi

    # Check rclone version
    _check_rclone_version

    # Create log directory if needed
    if [ ! -d "${_log_dir}" ]; then
        _warn printf "The '--log_dir' option specified is not a valid directory. Creating the dir with g+rwx permissions: '%s'\\n" "${_log_dir}"
        mkdir -p ${_log_dir}
        chmod g+rwx ${_log_dir}
    fi

    # Validate remote and bucket access
    _validate_remote_and_bucket "$_remote" "$_bucket"

    # Check s3cmd availability
    _check_s3cmd_access "$_bucket"

    # Execute the main workflow
    _execute_dd2ceph_workflow "$_remote" "$_bucket" "$_root_path_dir" "$_log_dir" "$_dry_run" "$_threads"
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
    
    # Only need to check that we can access s3cmd commands
    if command -v s3cmd &> /dev/null; then
        _verb printf "Using s3cmd found in PATH: %s\\n" "$(which s3cmd)"
        _verb printf "%s\\n" "$(s3cmd --version)" 
    else
        _exit_1 printf "s3cmd could not be found in PATH\\n"
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

    # Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
    umask 0007

    # Create archive working dir
    local archive_date_time="$(date +"%Y-%m-%d-%H%M%S")"
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
    _create_dd2ceph_scripts "${remote}" "${bucket}" "${root_path_dir}" "${myprefix_dir}" "${myprefix}" "${dry_run}" "${threads}"

    # Show completion message
    _info printf "dd2ceph workflow completed\\n"
    _info printf "Working directory: %s\\n" "${myprefix_dir}"
    _info printf "Review the generated scripts and submit them to SLURM as needed.\\n"
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

_create_dd2ceph_scripts() {
    local remote="$1"
    local bucket="$2"
    local root_path_dir="$3" 
    local myprefix_dir="$4"
    local myprefix="$5"
    local dry_run="$6"
    local threads="$7"

    # Create the main transfer script
    cat > "${myprefix}.slurm" <<EOF
#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --mail-user=\${USER}@umn.edu
#SBATCH --job-name=dd2ceph_\${USER}_${myprefix}
#SBATCH -o ${myprefix}.stdout
#SBATCH -e ${myprefix}.stderr

# Load required modules
module load rclone/1.71.0-r1

# Set umask for group-writable files (660) and directories (770)
umask 0007

# Set up credentials for myremote
export RCLONE_CONFIG_MYREMOTE_TYPE=s3
export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE
export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')
export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')
export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu
export RCLONE_CONFIG_MYREMOTE_ACL=private
export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph

# Change to working directory
cd ${myprefix_dir}

# Perform the transfer
echo "Starting dd2ceph transfer at \$(date)"
echo "Source: ${root_path_dir}"
echo "Destination: ${remote}:${bucket}"

rclone copy "${root_path_dir}" "${remote}:${bucket}" \\
    --transfers ${threads} \\
    --progress \\
    --stats 30s \\
    ${dry_run} \\
    --log-file "${myprefix}.rclone.log" \\
    --log-level INFO

echo "Transfer completed at \$(date)"

# Generate file comparison
echo "Generating file comparison..."
rclone lsf -R "${remote}:${bucket}" > ${myprefix}.destination_files.txt

echo "Transfer summary available in: ${myprefix_dir}"
EOF

    chmod +x "${myprefix}.slurm"
    
    _info printf "Created SLURM script: %s\\n" "${myprefix}.slurm"
}