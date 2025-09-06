# filesinbackup: Compare Backup Files Between Tier 1 and Tier 2

## Purpose

The `filesinbackup` tool generates comprehensive file lists comparing what's stored in your disaster recovery directory (Tier 1) versus your ceph bucket (Tier 2). This helps you:

- **Track what files are backed up** without manually searching directories
- **Identify files that exist in one location but not the other**
- **Maintain backup integrity** by knowing exactly what's stored where
- **Plan storage cleanup** by seeing which files are duplicated or missing

## Basic Usage

```bash
cephtools filesinbackup --group <GROUP>
```

This will:
1. Create a working directory with timestamp
2. Generate a SLURM script for the analysis
3. Provide instructions to run the comparison

## What Files Get Generated

After running the SLURM job, you'll get these comparison files:

- **`GROUP_TIMESTAMP.missing_from_ceph.txt`** - Files in disaster recovery but NOT in ceph bucket
- **`GROUP_TIMESTAMP.missing_from_disaster_recovery.txt`** - Files in ceph bucket but NOT in disaster recovery
- **`GROUP_TIMESTAMP.disaster_recovery_files.txt`** - Complete list of files in disaster recovery
- **`GROUP_TIMESTAMP.ceph_bucket_files.txt`** - Complete list of files in ceph bucket



## Command Options

### Required Options
- `--group <GROUP>` - MSI group ID (e.g., your PI's group name)

### Optional Options
- `--bucket <BUCKET>` - Ceph bucket name [Default: `data-delivery-GROUP`]
- `--disaster_recovery_dir <PATH>` - Path to disaster recovery directory [Default: `$MSIPROJECT/shared/disaster_recovery`]
- `--log_dir <PATH>` - Where to save results [Default: `$MSIPROJECT/shared/cephtools/filesinbackup`]
- `--remote <REMOTE>` - Rclone remote name [Default: auto-configured]
- `--threads <NUM>` - Number of threads for rclone [Default: 8]
- `--verbose` - Print additional information

### Custom Example
```bash
cephtools filesinbackup \
  --group mygroup \
  --bucket custom-backup-bucket \
  --disaster_recovery_dir /home/mygroup/custom_backup \
  --log_dir /home/mygroup/analysis_results
```

## Understanding the Output

### Missing from Ceph
Files listed in `GROUP_TIMESTAMP.missing_from_ceph.txt` are in your disaster recovery but haven't been uploaded to Tier 2. These might be:
- Recently added files that need backup
- Files that failed to upload previously
- Files intentionally kept only on Tier 1

### Missing from Disaster Recovery
Files in `GROUP_TIMESTAMP.missing_from_disaster_recovery.txt` exist in your ceph bucket but not in disaster recovery. This could mean:
- Files were moved or deleted from disaster recovery after backup
- Direct uploads to ceph that bypassed disaster recovery
- Files from other sources uploaded to the same bucket

## Typical Workflow

1. **Monthly Check**: Run filesinbackup monthly to verify backup status
2. **Review Differences**: Examine the missing files lists
3. **Take Action**: Decide whether to:
   - Copy missing files to ceph using `dd2ceph` or `panfs2ceph`
   - Restore missing files to disaster recovery
   - Clean up old files no longer needed

## Integration with Other Tools

- Use **`dd2dr`** to copy from data_delivery to disaster_recovery
- Use **`dd2ceph`** to upload from data_delivery to Tier 2
- Use **`panfs2ceph`** to upload other directories to Tier 2
- Use **`filesinbackup`** to verify everything is properly backed up

