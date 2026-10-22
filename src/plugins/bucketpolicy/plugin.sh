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
    ${_ME} bucketpolicy [options] --bucket <BUCKET>

Options:
    -b|--bucket <STRING>    Name of the ceph bucket for policy. Required.

    -m|--make_bucket        Attempt to create the bucket if it cannot be accessed.

    -p|--policy <STRING>    What policy should be created? [Default = "GROUP_READ"]
                            Policy options: 
                                NONE: Removes any policy currently set.
                                GROUP_READ: Allows resolved members of the MSI group
                                    read-only access to the bucket. 
                                GROUP_READ_WRITE: Allows resolved members of the MSI group
                                    full bucket permissions (s3:*).
                                OTHERS_READ: Allows anyone to retrieve objects when they
                                    know the object key. Does not allow bucket listing.
                                LIST_READ: Allows a specific list of users to have read-only 
                                    access to the bucket.
                                LIST_READ_WRITE: Allows a specific list of users to have 
                                    full bucket permissions (s3:*).

    -g|--group <STRING>     MSI group ID for GROUP policies. [Default = current group]
    
    -n|--do_not_setpolicy   Write policy files without changing the bucket policy.

    -l|--list <STRING>      Comma-separated InternetIDs or a file containing them.
                            Required for LIST policies.
    
    --log_dir <STRING>      Absolute or relative path to the directory where bucket policy files
                            are saved. [Default = "/projects/{standard,regulated,restricted}/GROUP/shared/cephtools/bucketpolicy" when --group is used]
     
     -v|--verbose            Verbose mode (print additional info).


Description:
  Create and set bucket policies for tier 2 (ceph). To overwrite a current policy, just rerun. 
  
Help (print this screen):
    ${_ME} help bucketpolicy

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
    local _bucket=
    local _make_bucket=0
    local _policy="GROUP_READ"
    local _group=
    local _do_not_setpolicy=0
    local _verbose=0
    local _list=
    local _log_dir=
    local _log_dir_provided=0

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
        if [[ -z "${__val:-}" ]]; then
          _exit_1 printf "%s requires a valid argument. Did you forget to define a variable?\\n" "${__arg}"
        else
          _exit_1 printf "%s requires a valid argument (got '%s' which looks like another option).\\n" "${__arg}" "${__val}"
        fi
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
        _exit_1 printf "Bucket name cannot be empty. Check that your variable is defined (e.g., export BUCKET_NAME=my-bucket).\\n"
      fi
      
      # Remove trailing slash if present
      bucket_name="${bucket_name%/}"
      
      # Check if bucket name is now empty after removing slash
      if [[ -z "$bucket_name" ]]; then
        _exit_1 printf "Bucket name cannot be just a slash. Please provide a valid bucket name.\\n"
      fi
      
      # Basic S3 bucket name validation
      if [[ ${#bucket_name} -lt 3 ]] || [[ ${#bucket_name} -gt 63 ]]; then
        _exit_1 printf "Bucket name must be between 3 and 63 characters long: '%s'\\n" "$bucket_name"
      fi
      
      # Check for invalid characters (basic check)
      if [[ "$bucket_name" =~ [^a-zA-Z0-9._-] ]]; then
        _exit_1 printf "Bucket name contains invalid characters. Use only letters, numbers, dots, hyphens, and underscores: '%s'\\n" "$bucket_name"
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
        --log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            _log_dir_provided=1
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

    # Set default log directory if not provided
    if [[ $_log_dir_provided -eq 0 ]]; then
        # In test environment, use TEST_OUTPUT_DIR as base
        if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
            _log_dir="$TEST_OUTPUT_DIR/bucketpolicy"
        elif [[ -n "${_group:-}" ]]; then
            # If group is specified, use group's directory
            _log_dir="$(_resolve_group_project_root "$_group")/shared/cephtools/bucketpolicy"
        else
            # Otherwise use current user's MSIPROJECT
            _log_dir="$MSIPROJECT/shared/cephtools/bucketpolicy"
        fi
    fi

    _verb printf "Program options used:\\n"
    _verb printf "bucket: %s\\n" "$_bucket"
    _verb printf "policy: %s\\n" "$_policy"
    _verb printf "group: %s\\n" "$_group"
    _verb printf "list: %s\\n" "$_list"
    _verb printf "log_dir: %s\\n" "$_log_dir"
    _verb printf "make_bucket: %s\\n" "$([[ ${_make_bucket} -eq 1 ]] && echo "yes" || echo "no")"
    _verb printf "do_not_setpolicy: %s\\n" "$([[ ${_do_not_setpolicy} -eq 1 ]] && echo "yes" || echo "no")"

    # Execute the main workflow
    _execute_bucketpolicy_workflow "$_bucket" "$_policy" "$_group" "$_list" "$_make_bucket" "$_do_not_setpolicy" "$_log_dir"
}

###############################################################################
# Helper Functions
###############################################################################

_resolve_policy_users() {
    local user_input="$1"
    local -n resolved_users_ref="$2"
    local -n principal_string_ref="$3"
    local -a internet_ids=()
    local internet_id
    local s3info_output
    local ceph_username
    local principal

    readarray -t internet_ids < <(
        printf "%s\n" "$user_input" |
            tr ',' '\n' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
            awk 'NF && $0 != "." && !seen[$0]++'
    )

    if [[ ${#internet_ids[@]} -eq 0 ]]; then
        _exit_1 printf "No valid UMN InternetIDs were found for the policy.\\n"
    fi

    if ! command -v s3info >/dev/null 2>&1; then
        _exit_1 printf "s3info is required to resolve UMN InternetIDs for bucket policies.\\n"
    fi

    for internet_id in "${internet_ids[@]}"; do
        if ! s3info_output="$(s3info info --user "$internet_id" 2>/dev/null)"; then
            _exit_1 printf "Could not resolve Tier 2 username for UMN InternetID: %s\\n" "$internet_id"
        fi

        ceph_username="$(printf "%s\\n" "$s3info_output" | sed -n 's/^Tier 2 username:[[:space:]]*//p' | head -n 1)"
        if [[ -z "$ceph_username" ]]; then
            _exit_1 printf "s3info returned no Tier 2 username for UMN InternetID: %s\\n" "$internet_id"
        fi

        resolved_users_ref+=("$internet_id")
        principal="\"arn:aws:iam:::user/${ceph_username}\""
        if [[ -z "$principal_string_ref" ]]; then
            principal_string_ref="$principal"
        else
            principal_string_ref+=",${principal}"
        fi
    done
}

_execute_bucketpolicy_workflow() {
    local _bucket="$1"
    local _policy="$2"
    local _group="$3"
    local _list="$4"
    local _make_bucket="$5"
    local _do_not_setpolicy="$6"
    local _log_dir="$7"

    # Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
    umask 0007

    # Check s3cmd availability
    if command -v s3cmd &> /dev/null
    then
        _verb printf "Using s3cmd: %s\\n" "$(command -V s3cmd)"
        _verb printf "%s\\n" "$(s3cmd --version)" 
    else
        _exit_1 printf "s3cmd could not be found in PATH\\n"
    fi

    # Make sure access to bucket is possible
    if ! s3cmd ls "s3://${_bucket}" &>/dev/null; then
        if ((_make_bucket))
        then
            if s3cmd mb "s3://${_bucket}" &>/dev/null; then
                _info printf "Bucket was made: %s\\n" "${_bucket}"
            else
                _exit_1 printf "Errors occured when trying to make bucket: '%s'\\nCheck the bucket access policy using 's3cmd info s3://%s'\\n" "${_bucket}" "${_bucket}"
            fi
        else
            _exit_1 printf "Errors occured when accessing bucket: '%s'\\nDo you have access rights to the bucket?\\nCheck the bucket access policy using 's3cmd info s3://%s'\\nIf the bucket does not exist, use the -m|--make_bucket flag to create it.\\n" "${_bucket}" "${_bucket}"
        fi
    fi

    # Ensure log directory exists and is accessible
    if [ ! -d "${_log_dir}" ]; then
        _info printf "Creating bucket policy directory: '%s'\\n" "${_log_dir}"
        mkdir -p "${_log_dir}"
        chmod g+rwx "${_log_dir}"
    fi
    
    # Create bucket policy vars
    local _curr_date_time="$(date +"%Y-%m-%d-%H%M%S")-$(date +"%N" | cut -c1-6)"
    local _bucket_policy="${_log_dir}/${_bucket}.bucket_policy.json"
    local _bucket_policy_readme="${_log_dir}/${_bucket}.bucket_policy_readme.md"

    # Get group user ids and generate policy based on type
    local _users_with_access
    local _all_ceph_username_string=""

    if [[ "${_policy}" == "NONE" ]]
    then
        _users_with_access="None (policy removed)"
        # Skip user collection for NONE policy
    elif [[ "${_policy}" =~ ^.*GROUP.*$ ]]
    then
        local _group_entry
        if ! _group_entry="$(getent group "${_group}")"; then
            _exit_1 printf "Could not resolve MSI group: %s\\n" "${_group}"
        fi

        local _username_msi_csv="${_group_entry##*:}"
        local _username_ceph_msi=()
        _resolve_policy_users "${_username_msi_csv}" _username_ceph_msi _all_ceph_username_string
        _users_with_access=("${_username_ceph_msi[@]}")
    elif [[ "${_policy}" =~ ^.*OTHERS.*$ ]]
    then
        _users_with_access="All MSI users and the entire public Internet"
    elif [[ "${_policy}" =~ ^.*LIST.*$ ]]
    then
        # Read in the specific users in the list
        local _username_msi_csv
        if [[ -e "$_list" ]]; then
            if [[ ! -r "$_list" ]]; then
                _exit_1 printf "User list file is not readable: %s\\n" "$_list"
            fi
            _username_msi_csv="$(cat "${_list}")"
        else
            _username_msi_csv="$_list"
        fi

        local _username_ceph_msi=()
        _resolve_policy_users "${_username_msi_csv}" _username_ceph_msi _all_ceph_username_string
        _users_with_access=("${_username_ceph_msi[@]}")
    fi

    # Generate the policy JSON using original structure
    _generate_policy_json_original "$_policy" "$_bucket" "$_all_ceph_username_string" "$_bucket_policy"

    # Apply the policy if requested
    local _policy_result
    local _policy_operation_failed=0
    if ((_do_not_setpolicy))
    then
        _policy_result="Policy files generated; bucket policy was not changed."
    else
        if _contains "${_policy}" "NONE"
        then
            if s3cmd delpolicy "s3://${_bucket}" &>/dev/null
            then
                _policy_result="Bucket policy removed."
            else
                _policy_result="Failed to remove the bucket policy."
                _policy_operation_failed=1
            fi
        else
            if s3cmd setpolicy "${_bucket_policy}" "s3://${_bucket}" &>/dev/null
            then
                _policy_result="Bucket policy applied."
            else
                _policy_result="Failed to apply the bucket policy."
                _policy_operation_failed=1
            fi
        fi
    fi

    # Create summary readme
    if [[ "${_policy}" == "NONE" ]] || [[ "${_policy}" =~ ^.*OTHERS.*$ ]]; then
        # For NONE and OTHERS policies, _users_with_access is a string, not an array
        _generate_readme "$_policy" "$_bucket" "$_curr_date_time" "$_do_not_setpolicy" "$_users_with_access" "$_bucket_policy_readme" "$_policy_result"
    else
        # For GROUP and LIST policies, pass all users in the array
        _generate_readme_with_users "$_policy" "$_bucket" "$_curr_date_time" "$_do_not_setpolicy" "$_bucket_policy_readme" "$_policy_result" "${_users_with_access[@]}"
    fi

    # Set file permissions
    chmod ug+rw,o-rwx "${_bucket_policy_readme}"
    chmod ug+rw,o-rwx "${_bucket_policy}"

    #######################################################################
    # Print instructions to terminal
    #######################################################################

    # Use a temp function to create multi-line string without affecting exit code
    # https://stackoverflow.com/a/8088167/2367748
    heredoc2var(){ IFS='\n' read -r -d '' ${1} || true; }
    
    local instructions_message
    heredoc2var instructions_message << HEREDOC

---------------------------------------------------------------------
cephtools bucketpolicy summary


Options used:
bucket=${_bucket}
policy=${_policy}
make_bucket=${_make_bucket}
do_not_setpolicy=${_do_not_setpolicy}
group=${_group}
list=${_list}


Result:
${_policy_result}


Policy files created in:
${_log_dir}


Next steps:
1. Review the readme file for details: ${_log_dir}/${_bucket}.bucket_policy_readme.md
2. Review the JSON bucket policy for details: ${_log_dir}/${_bucket}.bucket_policy.json
3. Verify the live bucket policy after applying a change.




VERSION: @VERSION_SHORT@
QUESTIONS: lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools
---------------------------------------------------------------------
HEREDOC

    echo "$instructions_message"

    if [[ ${_policy_operation_failed} -eq 1 ]]; then
        return 1
    fi
}

_generate_readme() {
    local _policy="$1"
    local _bucket="$2"
    local _curr_date_time="$3"
    local _do_not_setpolicy="$4"
    local _users_with_access="$5"
    local _bucket_policy_readme="$6"
    local _policy_result="$7"

    if _contains "${_policy}" "NONE"
    then
        tee "${_bucket_policy_readme}" << HEREDOC > /dev/null 
# cephtools bucketpolicy readme

## Options

Bucket policy initated (Y-m-d-HMS):  
${_curr_date_time} 

Options used:
bucket=${_bucket}
policy=${_policy}
do_not_setpolicy=${_do_not_setpolicy}
policy_json=${_bucket_policy}


VERSION: @VERSION_SHORT@
QUESTIONS: Please submit an issue on Github or lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools

## Policy

${_policy_result}

HEREDOC
    else
        tee "${_bucket_policy_readme}" << HEREDOC > /dev/null 
# cephtools bucketpolicy summary

## Options used

Bucket policy initated (Y-m-d-HMS):  
${_curr_date_time}  


\`\`\`
bucket=${_bucket}  
policy=${_policy}  
do_not_setpolicy=${_do_not_setpolicy}  
policy_json=${_bucket_policy}  
\`\`\`


VERSION: @VERSION_SHORT@  
QUESTIONS: Please submit an issue on Github or lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools


## Result

${_policy_result}


## MSI users included in the access policy

\`\`\`
${_users_with_access}
\`\`\`


## Ceph Actions enabled

See the ceph documentation for details:

[https://docs.ceph.com/en/latest/radosgw/bucketpolicy/](https://docs.ceph.com/en/latest/radosgw/bucketpolicy/)

See all "Actions" listed in the policy JSON file:  
\`${_bucket_policy}\`


HEREDOC
    fi
}

_generate_readme_with_users() {
    local _policy="$1"
    local _bucket="$2"
    local _curr_date_time="$3"
    local _do_not_setpolicy="$4"
    local _bucket_policy_readme="$5"
    local _policy_result="$6"
    shift 6  # Remove fixed arguments, remaining are user list
    local _user_list=("$@")  # All remaining arguments are users

    # Build the user list string with one user per line
    local _users_string=""
    for user in "${_user_list[@]}"; do
        if [[ -n "$user" ]]; then  # Skip empty usernames
            _users_string+="${user}"$'\n'
        fi
    done
    # Remove trailing newline
    _users_string="${_users_string%$'\n'}"

    tee "${_bucket_policy_readme}" << HEREDOC > /dev/null 
# cephtools bucketpolicy summary

## Options used

Bucket policy initated (Y-m-d-HMS):  
${_curr_date_time}  


\`\`\`
bucket=${_bucket}  
policy=${_policy}  
do_not_setpolicy=${_do_not_setpolicy}  
policy_json=${_bucket_policy}  
\`\`\`


VERSION: @VERSION_SHORT@  
QUESTIONS: Please submit an issue on Github or lmp-help@msi.umn.edu
REPO: https://github.com/umn-msi-lmnp/cephtools


## Result

${_policy_result}


## MSI users included in the access policy

\`\`\`
${_users_string}
\`\`\`


## Ceph Actions enabled

See the ceph documentation for details:

[https://docs.ceph.com/en/latest/radosgw/bucketpolicy/](https://docs.ceph.com/en/latest/radosgw/bucketpolicy/)

See all "Actions" listed in the policy JSON file:  
\`${_bucket_policy}\`


HEREDOC
}

_generate_policy_json_original() {
    local _policy="$1"
    local _bucket="$2"
    local _all_ceph_username_string="$3"
    local _bucket_policy="$4"

    if _contains "${_policy}" "NONE"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null

HEREDOC
    elif _contains "${_policy}" "GROUP_READ"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Principal": {"AWS": [
            ${_all_ceph_username_string}
        ]},
        "Action": [
            "s3:ListBucket",
            "s3:ListBucketVersions",
            "s3:GetBucketAcl",
            "s3:GetBucketCORS",
            "s3:GetBucketLocation",
            "s3:GetBucketLogging",
            "s3:GetBucketNotification",
            "s3:GetBucketPolicy",
            "s3:GetBucketTagging",
            "s3:GetBucketVersioning",
            "s3:GetBucketWebsite",
            "s3:GetObjectAcl",
            "s3:GetObject",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersion"
        ],
        "Resource": ["arn:aws:s3:::${_bucket}/*", "arn:aws:s3:::${_bucket}"]
        }
    ]
}

HEREDOC
    elif _contains "${_policy}" "GROUP_READ_WRITE"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Principal": {"AWS": [
            ${_all_ceph_username_string}
        ]},
        "Action": [
            "s3:*"
        ],
        "Resource": ["arn:aws:s3:::${_bucket}/*", "arn:aws:s3:::${_bucket}"]
        }
    ]
}

HEREDOC
    elif _contains "${_policy}" "LIST_READ"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Principal": {"AWS": [
            ${_all_ceph_username_string}
        ]},
        "Action": [
            "s3:ListBucket",
            "s3:ListBucketVersions",
            "s3:GetBucketAcl",
            "s3:GetBucketCORS",
            "s3:GetBucketLocation",
            "s3:GetBucketLogging",
            "s3:GetBucketNotification",
            "s3:GetBucketPolicy",
            "s3:GetBucketTagging",
            "s3:GetBucketVersioning",
            "s3:GetBucketWebsite",
            "s3:GetObjectAcl",
            "s3:GetObject",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersion"
        ],
        "Resource": ["arn:aws:s3:::${_bucket}/*", "arn:aws:s3:::${_bucket}"]
        }
    ]
}

HEREDOC
    elif _contains "${_policy}" "LIST_READ_WRITE"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Principal": {"AWS": [
            ${_all_ceph_username_string}
        ]},
        "Action": [
            "s3:*"
        ],
        "Resource": ["arn:aws:s3:::${_bucket}/*", "arn:aws:s3:::${_bucket}"]
        }
    ]
}


HEREDOC
    elif _contains "${_policy}" "OTHERS_READ"
    then
        tee "${_bucket_policy}" << HEREDOC > /dev/null
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Sid":"PublicRead",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
            "s3:GetObject",
            "s3:GetObjectVersion"
        ],
        "Resource": ["arn:aws:s3:::${_bucket}/*", "arn:aws:s3:::${_bucket}"]
        }
    ]
}

HEREDOC
    else
        _exit_1 printf "The '--policy' option is not recognized."
    fi
}
