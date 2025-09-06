#!/usr/bin/env bash
###############################################################################
# bucketpolicy Plugin for cephtools
# Create and set bucket policies for tier 2 (ceph).
###############################################################################

# Plugin metadata
PLUGIN_NAME="bucketpolicy"

PLUGIN_DESCRIPTION="Create and set bucket policies for ceph"

###############################################################################
# Plugin Interface Functions
###############################################################################

plugin_describe() {
cat <<HEREDOC
---------------------------------------------------------------------
Usage:
    ${_ME} bucketpolicy [options] --bucket <BUCKET> --policy <POLICY_OPTION>

Options:
    -b|--bucket <STRING>    Name of the ceph bucket for policy. Required.

    -m|--make_bucket        If the bucket does not exist, make it. [Default = buckets are not created
                            but policies will be adjusted if a bucket already exists.]

    -p|--policy <STRING>    What policy should be created? [Default = "GROUP_READ"]
                            Policy options: 
                                NONE: Removes any policy currently set.
                                GROUP_READ: Allows all current memebers of the MSI group 
                                    read-only access to the bucket. 
                                GROUP_READ_WRITE: Allows all current memebers of the MSI 
                                    group read and write access to the bucket.
                                OTHERS_READ: Allows anyone read-only access to the bucket
                                    (i.e. world public read-only access). WARNING: this
                                    policy will expose all files in the bucket to the 
                                    entire Internet for viewing or downloading. However,
                                    this can be a good option for hosting a public static
                                    website.
                                LIST_READ: Allows a specific list of users to have read-only 
                                    access to the bucket. Must be a comma separated x500 
                                    list without spaces.
                                LIST_READ_WRITE: Allows a specific list of users to have 
                                    read and write access to the bucket. Must be a comma 
                                    separated x500 list without spaces.
                                    
    -g|--group <STRING>     MSI group id. Required only if "--policy GROUP_READ" is
                            specified.
    
    -n|--do_not_setpolicy   If specified, the policy will be created (i.e. written to
                            file) but it will not be set on the bucket.
                            
    -l|--list               Provide a list of user ids for the particular policy setting
    
    -v|--verbose            Verbose mode (print additional info).


Description:
  Create and set bucket policies for tier 2 (ceph). To overwrite a current policy, just rerun. 
  
Help (print this screen):
    ${_ME} help bucketpolicy

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
    local _bucket=
    local _make_bucket=0
    local _policy="GROUP_READ"
    local _group=
    local _do_not_setpolicy=0
    local _verbose=0
    local _list=

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

    # Parse command line arguments
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -m|--make_bucket)
            _make_bucket=1
            ;;
        -v|--verbose)
            _verbose=1
            ;;
        -n|--do_not_setpolicy)
            _do_not_setpolicy=1
            ;;
        -b|--bucket)
            _bucket="$(__validate_bucket_name "$(__get_option_value "${__arg}" "${__val:-}")")"
            shift
            ;;
        -p|--policy)
            _policy="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -g|--group)
            _group="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -l|--list)
            _list="$(__get_option_value "${__arg}" "${__val:-}")"
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
    if [[ -z "${_bucket:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--bucket' is required.\\n"
    fi

    # Validate policy option
    case "${_policy}" in
        "NONE"|"GROUP_READ"|"GROUP_READ_WRITE"|"OTHERS_READ"|"LIST_READ"|"LIST_READ_WRITE")
            # Valid policy
            ;;
        *)
            plugin_describe
            _exit_1 printf "Invalid policy option: %s\\n" "${_policy}"
            ;;
    esac

    # Check policy-specific requirements
    if [[ "${_policy}" =~ ^GROUP_ ]] && [[ -z "${_group:-}" ]]; then
        _group="$(id -ng)"
        _verb printf "No group specified, using current group: %s\\n" "${_group}"
    fi

    if [[ "${_policy}" =~ ^LIST_ ]] && [[ -z "${_list:-}" ]]; then
        plugin_describe
        _exit_1 printf "LIST policies require --list option with comma-separated user list\\n"
    fi

    _verb printf "Program options used:\\n"
    _verb printf "--bucket: %s\\n" "$_bucket"
    _verb printf "--policy: %s\\n" "$_policy"
    _verb printf "--group: %s\\n" "$_group"
    _verb printf "--list: %s\\n" "$_list"
    _verb printf "--make_bucket: %s\\n" "$([[ ${_make_bucket} -eq 1 ]] && echo "yes" || echo "no")"
    _verb printf "--do_not_setpolicy: %s\\n" "$([[ ${_do_not_setpolicy} -eq 1 ]] && echo "yes" || echo "no")"

    # Execute the main workflow
    _execute_bucketpolicy_workflow "$_bucket" "$_policy" "$_group" "$_list" "$_make_bucket" "$_do_not_setpolicy"
}

###############################################################################
# Helper Functions
###############################################################################

_execute_bucketpolicy_workflow() {
    local bucket="$1"
    local policy="$2"
    local group="$3"
    local list="$4"
    local make_bucket="$5"
    local do_not_setpolicy="$6"

    # Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
    umask 0007

    # Check s3cmd availability
    if ! command -v s3cmd &> /dev/null; then
        _exit_1 printf "s3cmd could not be found in PATH\\n"
    fi

    _verb printf "Using s3cmd: %s\\n" "$(which s3cmd)"

    # Check if bucket exists
    local bucket_exists=0
    if s3cmd ls s3://${bucket} &>/dev/null; then
        bucket_exists=1
        _info printf "Bucket exists: %s\\n" "${bucket}"
    else
        _info printf "Bucket does not exist: %s\\n" "${bucket}"
        
        if [[ ${make_bucket} -eq 1 ]]; then
            _info printf "Creating bucket: %s\\n" "${bucket}"
            if ! s3cmd mb s3://${bucket}; then
                _exit_1 printf "Failed to create bucket: %s\\n" "${bucket}"
            fi
            bucket_exists=1
        else
            _exit_1 printf "Bucket does not exist and --make_bucket not specified: %s\\n" "${bucket}"
        fi
    fi

    # Generate the policy JSON
    local policy_file="${bucket}_policy.json"
    _generate_policy_json "$policy" "$bucket" "$group" "$list" "$policy_file"

    # Apply the policy if requested
    if [[ ${do_not_setpolicy} -eq 0 ]]; then
        if [[ "$policy" == "NONE" ]]; then
            _info printf "Removing bucket policy for: %s\\n" "${bucket}"
            s3cmd delpolicy s3://${bucket} || _warn printf "Could not remove policy (may not exist)\\n"
        else
            _info printf "Setting bucket policy for: %s\\n" "${bucket}"
            if ! s3cmd setpolicy "$policy_file" s3://${bucket}; then
                _exit_1 printf "Failed to set bucket policy\\n"
            fi
        fi
    else
        _info printf "Policy file created but not applied: %s\\n" "$policy_file"
    fi

    _info printf "Bucket policy operation completed successfully\\n"
}

_generate_policy_json() {
    local policy="$1"
    local bucket="$2"
    local group="$3" 
    local list="$4"
    local policy_file="$5"

    case "$policy" in
        "NONE")
            # Empty policy to remove existing policy
            echo '{}' > "$policy_file"
            ;;
        "GROUP_READ")
            _generate_group_policy "$bucket" "$group" "read" "$policy_file"
            ;;
        "GROUP_READ_WRITE")
            _generate_group_policy "$bucket" "$group" "readwrite" "$policy_file"
            ;;
        "OTHERS_READ")
            _generate_public_read_policy "$bucket" "$policy_file"
            ;;
        "LIST_READ")
            _generate_list_policy "$bucket" "$list" "read" "$policy_file"
            ;;
        "LIST_READ_WRITE")
            _generate_list_policy "$bucket" "$list" "readwrite" "$policy_file"
            ;;
    esac

    _verb printf "Generated policy file: %s\\n" "$policy_file"
}

_generate_group_policy() {
    local bucket="$1"
    local group="$2"
    local access_type="$3"
    local policy_file="$4"

    # Get group members
    local group_members
    if command -v getent >/dev/null 2>&1; then
        group_members="$(getent group "$group" | cut -d: -f4 | tr ',' '\n' | sed 's/^/urn:msi:/' | paste -sd, -)"
    else
        _warn printf "getent not available, using current user only\\n"
        group_members="urn:msi:$(id -un)"
    fi

    local actions
    if [[ "$access_type" == "readwrite" ]]; then
        actions='"s3:GetBucketLocation","s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"'
    else
        actions='"s3:GetBucketLocation","s3:ListBucket","s3:GetObject"'
    fi

    cat > "$policy_file" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Group${access_type}Access",
            "Effect": "Allow",
            "Principal": {
                "AWS": [$(echo "$group_members" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
                ]
            },
            "Action": [${actions}],
            "Resource": [
                "arn:aws:s3:::${bucket}",
                "arn:aws:s3:::${bucket}/*"
            ]
        }
    ]
}
EOF
}

_generate_public_read_policy() {
    local bucket="$1"
    local policy_file="$2"

    cat > "$policy_file" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${bucket}/*"
            ]
        }
    ]
}
EOF
}

_generate_list_policy() {
    local bucket="$1"
    local user_list="$2"
    local access_type="$3"
    local policy_file="$4"

    # Convert comma-separated list to URN format
    local user_arns="$(echo "$user_list" | tr ',' '\n' | sed 's/^/urn:msi:/' | paste -sd, - | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')"

    local actions
    if [[ "$access_type" == "readwrite" ]]; then
        actions='"s3:GetBucketLocation","s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"'
    else
        actions='"s3:GetBucketLocation","s3:ListBucket","s3:GetObject"'
    fi

    cat > "$policy_file" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "List${access_type}Access",
            "Effect": "Allow",
            "Principal": {
                "AWS": [${user_arns}]
            },
            "Action": [${actions}],
            "Resource": [
                "arn:aws:s3:::${bucket}",
                "arn:aws:s3:::${bucket}/*"
            ]
        }
    ]
}
EOF
}
