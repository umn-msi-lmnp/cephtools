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
GitHub: https://github.umn.edu/lmnp/cephtools

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
    local _group=
    local _dry_run=0
    local _log_dir="$MSIPROJECT/shared/cephtools/dd2dr"
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
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")"
    local work_dir="${log_dir}/dd2dr_${group}_${timestamp}"
    
    _info printf "Creating working directory: %s\\n" "$work_dir"
    mkdir -p "$work_dir"
    cd "$work_dir"

    # Create comprehensive dd2dr SLURM script with full functionality
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")"
    _create_comprehensive_dd2dr_script "$group" "$data_delivery_path" "$disaster_recovery_path" "$work_dir" "$dry_run" "$threads" "$timestamp"

    _info printf "Change into the log dir and launch the slurm job:\\n"
    _info printf "cd %s && sbatch %s.slurm\\n" "$work_dir" "${group}_${timestamp}"
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
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --mail-user=\${USER}@umn.edu
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rsync

# Change to working directory
cd ${work_dir}

# Set variables from dd2dr_commands.sh integration
GROUP="${group}"
DATESTAMP="${timestamp}"

# Print some info
echo "\$GROUP sync starting..."
echo "\${DATESTAMP}"
umask u=rwx,g=rx,o=

# Check for any space issues
echo "Checking group quota..."
if command -v groupquota >/dev/null 2>&1; then
    groupquota -g \$GROUP -p -U 'G' -c
    AVAIL=\$(groupquota -g \$GROUP -p -U '' -cH | awk 'BEGIN { FS=",";OFS=","} {print \$3-\$2}')
    AVAILH=\$(groupquota -g \$GROUP -p -U 'G' -cH | sed 's/G//g' | awk 'BEGIN { FS=",";OFS=","} {print \$3-\$2}')
    echo "\${AVAILH}G remaining in \$MSIPROJECT total quota"
else
    echo "groupquota command not available, skipping quota check"
    AVAIL=999999999999999  # Large number to allow transfer
    AVAILH="N/A"
fi

# Check data_delivery
echo "Checking data_delivery size..."
DDTOTAL=\$(du -Lhc ${data_delivery_path} | tail -1 | cut -f1)
echo "\$DDTOTAL in ${data_delivery_path}"
DDBYTES=\$(du -Lbc ${data_delivery_path} | tail -1 | cut -f1)
echo "\$DDBYTES bytes in data_delivery"

# Total size of files that will be transferred
echo "Calculating transfer size..."
DDBYTES_TRANSFER=\$(rsync -Lvru --dry-run --stats ${data_delivery_path} ${disaster_recovery_path}/ | grep "Total transferred file size:" | tr " " "\t" | cut -f 5 | sed 's/\,//g')
echo "\$DDBYTES_TRANSFER bytes to be transferred"

# Transfer the files
if [ "\$DDBYTES_TRANSFER" -lt "\$AVAIL" ]; then
    echo "\$DDBYTES_TRANSFER < \$AVAIL, syncing data_delivery to disaster_recovery"
    
    # Use rsync with -L to copy links as files
    rsync -Lvru ${dry_run_flag} ${data_delivery_path} ${disaster_recovery_path}/
    
    # Check if rsync finished successfully
    if [ "\$?" -eq 0 ]; then
        echo "rsync finished successfully!"
        
        # Check new space availability
        if command -v groupquota >/dev/null 2>&1; then
            AVAILHNEW=\$(groupquota -g \$GROUP -U 'G' -cH | sed 's/G//g' | awk 'BEGIN { FS=",";OFS=","} {print \$3-\$2}')
            echo "Previous space available was \${AVAILH}G"
            echo "New space available is \${AVAILHNEW}G"
        fi
        echo "Sync complete"
    else
        echo "rsync did not finish successfully"
        exit 5
    fi
    
else
    echo "\$DDBYTES > \$AVAIL Not enough space for syncing!"
    echo "Checking disaster_recovery data_delivery size..."
    
    if [ -d "${disaster_recovery_path}/data_delivery" ]; then
        DDDRBYTES=\$(du -Lbc ${disaster_recovery_path}/data_delivery | tail -1 | cut -f1)
        echo "\$DDDRBYTES in disaster_recovery data_delivery"
        
        if [ "\$DDBYTES" -eq "\$DDDRBYTES" ]; then
            echo "\$DDBYTES (dd size) equal to \$DDDRBYTES (dddr size)"
            echo "Nothing needs to transfer, but space is not available"
        else
            echo "Data sizes differ but insufficient space for transfer"
            echo "Manual intervention may be required"
            exit 20
        fi
    else
        echo "Disaster recovery directory structure not found"
        echo "Insufficient space for initial sync"
        exit 10
    fi
fi

echo "dd2dr sync completed at \$(date)"

# Generate file lists for comparison
echo "Generating file lists..."
if [ -d "${data_delivery_path}" ]; then
    find "${data_delivery_path}" -type f > ${group}_${timestamp}.data_delivery_files.txt
    echo "Source file list: ${group}_${timestamp}.data_delivery_files.txt"
fi

if [ -d "${disaster_recovery_path}/data_delivery" ]; then
    find "${disaster_recovery_path}/data_delivery" -type f > ${group}_${timestamp}.disaster_recovery_files.txt
    echo "Destination file list: ${group}_${timestamp}.disaster_recovery_files.txt"
fi

echo "Reports available in: ${work_dir}"
EOF

    chmod +x "$script_name"
    
    _info printf "Created dd2dr SLURM script: %s\\n" "$script_name"
    _info printf "Submit with: sbatch %s\\n" "$script_name"
}
