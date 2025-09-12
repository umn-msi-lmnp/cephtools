# filesinbackup: Compare Backup Files Between Tier 1 and Tier 2

## Purpose

The `filesinbackup` tool generates comprehensive file lists comparing what's stored in your disaster recovery directory (Tier 1) versus your ceph bucket (Tier 2). This helps you:

- **Track what files are backed up** without manually searching directories
- **Maintain backup integrity** by knowing exactly what's stored where

## Basic Usage

```bash
cephtools filesinbackup --group <GROUP>
```

## What Files Get Generated

After running the SLURM job, you'll get these comparison files:

- **`GROUP_TIMESTAMP.disaster_recovery_files.txt`** - Complete list of files in disaster recovery
- **`GROUP_TIMESTAMP.disaster_recovery_files.md5`** - MD5 checksums for disaster recovery files
- **`GROUP_TIMESTAMP.BUCKET_tier2_files.txt`** - Complete list of files in ceph bucket
- **`GROUP_TIMESTAMP.BUCKET_tier2_files.md5`** - MD5 checksums for ceph bucket files

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

