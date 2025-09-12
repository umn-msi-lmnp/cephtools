# Cephtools: Transfer a directory from panfs (tier1) to ceph (tier2)

## Introduction

The purpose of the `panfs2ceph` subcommand is to backup a single directory, and all its contents, from panfs to ceph. The tool will create a working directory and output a file list and slurm job scripts to complete the steps. Notably, this tool was built when tier 1 storage was located on Panasas (panfs) -- now, most tier 1 data is stored on the VAST storage platform. Either way, panfs2ceph is really for transferring data from tier 1 to tier 2, regardless of their names.

A common use case for this tool is this:

- You completed a project on panfs and don't plan on accessing the data for computation anymore
- You would like to archive the project to ceph
- You would like to delete the files from panfs, freeing up storage
- You would like a trail of info regarding where the project files are located and how to access them
- You would like to browse the project files (but not use them for computation) on ceph

## Set up environment

If necessary, run `newgrp` and set the MYGROUP variable. Then load `cephtools`.

```
# newgrp GROUPNAME
MYGROUP=$(id -ng)

# Load cephtools or make sure it's in your PATH
module load cephtools
which cephtools
```

## Create a bucket

You need to create a ceph bucket before transferring data with `cephtools`. After the bucket is created, a bucket policy can be applied to the bucket (i.e. `cephtools bucketpolicy`), controlling access to the bucket for only certain MSI users. If you don't want to share the data with anyone, no bucket policy is needed.

What should I name my bucket? The [Ceph bucket naming rules](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/) can be found here. If you are archiving projects for a particular group, I suggest a format like this: `GROUP-USER-tier1-archive`.

```
MYGROUP=$(id -ng)
BUCKET_NAME="${MYGROUP}-${USER}-tier1-archive"
s3cmd mb "s3://${BUCKET_NAME}"
```

### (Optional) Use `cephtools` to set a bucket policy

For example, it can be helpful to allow anyone in your MSI group read-only access to the archived projects bucket. Running this tool will generate two files (the json bucket policy and a readme), so you should put these files in common location. Re-run the bucket policy command after MSI members are added or removed from group.

```
# Change into a common place to store policies
mkdir -m ug+rwxs -p $MSIPROJECT/shared/cephtools/bucketpolicy
cd $MSIPROJECT/shared/cephtools/bucketpolicy

cephtools bucketpolicy --verbose --bucket $BUCKET_NAME --policy GROUP_READ --group $MYGROUP
```

## Create transfer scripts

NOTE: you can supply your `rclone` remote name in the command below. To learn more about rclone remotes, [see this tips page](https://github.umn.edu/lmnp/tips/tree/main/rclone#umn-tier2-ceph). However, the --remote option is not required and cephtools will automatically find your MSI tier 2 keys and automatically use a temporary rclone remote.

```
cephtools panfs2ceph --bucket $BUCKET_NAME --path $MSIPROJECT/shared/myproject
```

By default, the working directory is created at the same path as the original input directory, with a suffix name. For example, input directory and working directory paths are shown below:

| Input dir path name                       | Working dir path name                                               |
| ----------------------------------------- | ------------------------------------------------------------------- |
| `$MSIPROJECT/shared/myproject` | `$MSIPROJECT/shared/myproject___panfs2ceph_archive_DATE` |

Inside the working directory:

- A `PREFIX.1_copy_and_verify.slurm` job file can be launched to copy and verify all the data to a ceph bucket.
- A `PREFIX.2_delete.slurm` job file can be launched to delete all the data from panfs.
- A `PREFIX.3_restore.slurm` job file can be launched to copy all the data back from ceph to panfs, if you ever need to restore the project directory to the original location.
- Finally, a `PREFIX.readme.md` file is created that describes the process and where the files on ceph are located.

## Launch the transfer job scripts

- Change into the working directory created above.
- Review the slurm scripts (change any parameters you wish)
- Launch the combined "copy and verify" job

```
sbatch PREFIX.1_copy_and_verify.slurm
```

- Review progress in the job error log file (`tail PREFIX.1_copy_and_verify.slurm.e*`)
- The combined script will copy data to ceph and immediately verify the transfer
- Review the verification log (`PREFIX.1_verify.rclone.log`) to ensure all files were transferred successfully
- After verification is complete and successful, delete the original data from panfs (tier1)

```
sbatch PREFIX.2_delete.slurm
```

- After the data is removed from panfs (tier1), you can restore it back to its original location by running the restore script.

```
sbatch PREFIX.3_restore.slurm
```
