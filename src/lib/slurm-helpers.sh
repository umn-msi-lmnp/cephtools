#!/usr/bin/env bash
###############################################################################
# SLURM Helper Functions for cephtools
###############################################################################

# _create_slurm_script()
#
# Usage:
#   _create_slurm_script <script_path> <job_name> <time> <cpus> <memory> <commands...>
#
# Description:
#   Creates a SLURM job script with the specified parameters
_create_slurm_script() {
  local script_path="${1}"
  local job_name="${2}"
  local time="${3:-24:00:00}"
  local cpus="${4:-4}"
  local memory="${5:-16gb}"
  shift 5
  local commands=("${@}")
  
  cat > "${script_path}" <<EOF
#!/bin/bash
#SBATCH --time=${time}
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${cpus}
#SBATCH --mem=${memory}
#SBATCH --mail-type=ALL
#SBATCH --mail-user=\${USER}@umn.edu
#SBATCH --job-name=${job_name}
#SBATCH -o ${script_path%.slurm}.stdout
#SBATCH -e ${script_path%.slurm}.stderr

# Commands
$(printf "%s\n" "${commands[@]}")
EOF

  chmod +x "${script_path}"
  _debug printf "Created SLURM script: %s\\n" "${script_path}"
}

# _submit_slurm_job()
#
# Usage:
#   _submit_slurm_job <script_path> [dependency_job_id]
#
# Description:
#   Submits a SLURM job script and returns the job ID
_submit_slurm_job() {
  local script_path="${1}"
  local dependency="${2:-}"
  
  if [[ ! -f "${script_path}" ]]; then
    _exit_1 printf "SLURM script not found: %s\\n" "${script_path}"
  fi
  
  local sbatch_cmd="sbatch"
  if [[ -n "${dependency}" ]]; then
    sbatch_cmd="${sbatch_cmd} --dependency=afterok:${dependency}"
  fi
  
  local job_output
  job_output=$(${sbatch_cmd} "${script_path}" 2>&1)
  local exit_code=$?
  
  if [[ ${exit_code} -eq 0 ]]; then
    # Extract job ID from output (format: "Submitted batch job 12345")
    local job_id
    job_id=$(echo "${job_output}" | grep -o '[0-9]\+$')
    printf "%s" "${job_id}"
  else
    _exit_1 printf "Failed to submit SLURM job: %s\\n" "${job_output}"
  fi
}