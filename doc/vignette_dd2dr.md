# Cephtools: Backing up `data_delivery` to disaster recovery

## Introduction

Data from various UMN core facilities (e.g. UMGC) is delivered to a special directory called `data_delivery` for a limited time period (~ 1 year). This vignette describes how to easily copy data from `data_delivery` to MSI's Tier 1 `disaster_recovery` directory for backup and long-term storage. The folder `$MSIPROJECT/shared/disaster_recovery` is special because all data in the dir are backed up automatically off-site (not at MSI in Walter library). 

The `dd2dr` command provides a simple, automated way to sync your group's `data_delivery` directory to `disaster_recovery` storage, ensuring your important data is backed up before it's removed from the temporary delivery location.

## Step 1: Set up environment

1. Log into MSI and check your current primary (default) group.

   ```bash
   # Check current group
   id -ng
   ```

   If necessary, run `newgrp GROUPNAME` to change your current group and set a MYGROUP variable.

   ```bash
   # Set a variable for group name
   MYGROUP=$(id -ng)
   ```

2. Load `cephtools` software.

## Step 2: Create working directory

Keep a record of all data transfers in a shared (common) location. Make sure group permissions are set for this folder.

```bash
mkdir -m ug+rwxs -p $MSIPROJECT/shared/cephtools/dd2dr
cd $MSIPROJECT/shared/cephtools/dd2dr
```

## Step 3: Run the backup

1. Explore the tool's options first.

   ```bash
   # View available options
   cephtools dd2dr
   ```

2. Run the backup command.

   ```bash  
   # Actual backup
   cephtools dd2dr --group $MYGROUP
   ```

This will create a SLURM job script that copies all files from:
- **Source**: `$MSIPROJECT/data_delivery/`
- **Destination**: `$MSIPROJECT/shared/disaster_recovery/`

## Step 4: Submit the job

The `dd2dr` command generates a SLURM script that you need to submit to run the backup:

```bash
# The tool will show you the exact command, something like:
cd $MSIPROJECT/shared/cephtools/dd2dr/dd2dr_MYGROUP_2025-09-07-123456 && sbatch MYGROUP_2025-09-07-123456.slurm
```

## Step 5: Monitor the job

Check the status of your backup job:

```bash
# Check job status
squeue -u $USER

# View job output (after completion)
cat MYGROUP_TIMESTAMP.o[JOBID]
```

## What happens during backup

The `dd2dr` tool:

1. **Validates access** to both source and destination directories
2. **Creates working directory** with timestamp for tracking  
3. **Copies all files** from `data_delivery` to `disaster_recovery` using rclone
4. **Generates file lists** for verification
5. **Provides completion report** with file counts and locations

## Tips and best practices

- **Run regularly**: Execute `dd2dr` whenever new data appears in `data_delivery`
- **Use dry run first**: Always test with `--dry_run` to preview what will be copied
- **Check space**: The tool will warn if there are space issues
- **Keep logs**: All operations are logged in the working directory for future reference
- **Verify results**: Check the generated file lists to confirm all data was copied

## Command options

```bash
cephtools dd2dr [options] --group <GROUP>

Options:
  -g|--group <STRING>     MSI group ID (required)
  -l|--log_dir <STRING>   Directory for log files [Default: shared/cephtools/dd2dr]
  -d|--dry_run           Preview mode - shows what would be copied without doing it
  -v|--verbose           Show detailed information during execution
```

## Example workflow

```bash
# Set up (one time)
module load cephtools
MYGROUP=$(id -ng)
mkdir -m ug+rwxs -p $MSIPROJECT/shared/cephtools/dd2dr
cd $MSIPROJECT/shared/cephtools/dd2dr

# Regular backup routine
cephtools dd2dr --group $MYGROUP --dry_run  # Preview
cephtools dd2dr --group $MYGROUP            # Actual backup
# Follow instructions to submit the SLURM job
```

This simple workflow ensures your important `data_delivery` files are safely backed up to `disaster_recovery` storage before they're removed from the temporary delivery location.

## Questions or issues

For help with cephtools dd2dr:
- Submit an issue on GitHub: https://github.com/umn-msi-lmnp/cephtools
- Contact: lmp-help@msi.umn.edu
