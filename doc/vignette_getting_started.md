# Cephtools: Getting Started

## Introduction

This vignette describes the basic purpose for each of the `cephtools` subcommand functions.

## `vast2ceph`: Transfer a directory from vast (tier1) to ceph (tier2)

The purpose of this subcommand is to backup a single directory, and all its contents, from tier 1 to tier 2. The tool will create a working directory and output a file list and slurm job scripts to complete the steps. By default, the working directory is created at the same path as the original input directory, with a suffix name. For example, if the input is `/projects/regulated/GROUP/shared/myproject`, the working directory will be created at `/projects/regulated/GROUP/shared/myproject___vast2ceph_archive_DATE`.

Inside the working directory:

- A `PREFIX.1_copy_and_verify.slurm` job file can be launched to copy all the data to a ceph bucket and verify the transfer.
- A `PREFIX.2_delete.slurm` job file can be launched to delete all the data from tier 1.
- A `PREFIX.3_restore.slurm` job file can be launched to copy all the data back from ceph to tier 1, if you ever need to restore the project directory to the original location.

## `bucketpolicy`: Allow others to access your ceph (tier2) bucket

By default, new ceph buckets can only be accessed by the owner. The purpose of this subcommand is create and apply a "bucket policy" that can change how other ceph users (or even public Internet users) can access files in your bucket. This tool will (1) write a bucket policy (json file), (2) write a readme file describing the changes, and (3) apply the policy to the bucket.

A few bucket policy presets exist:

- `NONE`: Removes any policy currently set.
- `GROUP_READ`: This policy gives all current users of an MSI group read-only access to all files in bucket. This is great for sharing data with coworkers.
- `GROUP_READ_WRITE`: This policy gives all current users of an MSI group full bucket permissions (s3:*). This is great for allowing coworkers to write files into your bucket.
- `OTHERS_READ`: Allows anyone to download objects when they know the object key. Does not allow bucket listing. This can be a good option for sharing specific files publicly.
- `LIST_READ`: Allows a specific list of users (UMN InternetIDs via `--list`) to have read-only access to the bucket.
- `LIST_READ_WRITE`: Allows a specific list of users (UMN InternetIDs via `--list`) to have full bucket permissions (s3:*).

## `dd2ceph`: Backup all files in a group's data_delivery folder to ceph (tier2)

The purpose of this subcommand is to backup all of the data in the group's special "data_delivery" or "data_release" directories (e.g. sequencing data from UMGC or other core facilities). The data deposited into these directories are automatically deleted after a period of time (~ 1 year), so backing up the data is essential. The tool finds all files (and follows symbolic links) in the directory and copies it to ceph (tier2). The tool resolves the group root from `/projects/{standard,regulated,restricted}/MYGROUP` and creates the working directory at `GROUP_ROOT/shared/cephtools/dd2ceph`.

Inside the working directory:

- A `PREFIX.1_copy_and_verify.slurm` job file can be launched to copy all the data to a ceph bucket and verify the transfer.

## `dd2dr`: Backup all files in a group's data_delivery folder to disaster_recovery (tier1)

The purpose of this subcommand is to backup all of the data in the group's special "data_delivery" or "data_release" directories to MSI's Tier 1 `disaster_recovery` directory for backup and long-term storage. The folder `$MSIPROJECT/shared/disaster_recovery` is special because all data in the directory are backed up automatically off-site (not at MSI in Walter library). The tool finds all files (and follows symbolic links) in the directory and copies it to `disaster_recovery`. The tool will create a working directory and output a file list and a slurm job script to complete the steps. By default, the working directory is created at `$MSIPROJECT/shared/cephtools/dd2dr`.

Inside the working directory:

- A SLURM job file can be launched to copy all the data to the disaster recovery directory.

## `filesinbackup`: Create file lists from tier 2 bucket and `shared/disaster_recovery`

The purpose of this subcommand is to generate a list of files stored in a tier 2 bucket and a list of files in the `$MSIPROJECT/shared/disaster_recovery` directory. Many people backup files in these two locations, but it's helpful to have a current inventory of what's stored where.  

## FAQs

- How do these tools handle symbolic links?
  - `vast2ceph` does NOT follow symbolic links and does not transfer the actual file. It transfers the symbolic link itself. See the `rclone` flag [`--links`](https://rclone.org/local/#links-l) for details. `dd2ceph` and `dd2dr` commands DO follow symbolic links and copy the actual file (i.e. it copies the dereferenced file). The rationale is that any symlinks in the data_delivery dir will want to be copied (backed up) as real files. However, symlinks in a regular project dir should remain as symlinks in the backup. 
- How fast is the transfer?
  - The empirical data transfer rate from tier 1 to tier 2 is approximately 1 TB per 30 min (or around 30 GB/min). By default, both `vast2ceph` and `dd2ceph` request a 24 hr job time. These times can be adjusted directly in the slurm script before launching. Reviewing the end of a slurm error log file will show a summary from `rclone`, indicating how much data was transferred and how long it took.
- Do I have to create a bucket first?
  - Yes, you'll need to create a bucket before using it with `cephtools`. `cephtools` checks that the bucket exists before running for added safety and transparency. `rclone` can automatically create buckets when transferring for the first time, but `cephtools` fails before writing the "copy" slurm script if the bucket does not exist. To create a new bucket, run: `s3cmd mb s3://MY-BUCKET-NAME`.
- How should I name buckets?
  - Ceph is an open-source software storage platform that uses the Amazon S3 APIs. Ceph allows for buckets to be named with underscores, but some S3 APIs will fail if they find buckets with underscores. I think everything in `cephtools` will work with underscores in the bucket names, but use hyphens to be safe. [Amazon bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html) and [Ceph bucket naming rules](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/)
  - **Important:** Do not include trailing slashes in bucket names (e.g., avoid `"bucketname/"`). `cephtools` will automatically remove trailing slashes, but bucket names with internal slashes may cause issues and will generate warnings.
- How are relative paths handled?
  - `cephtools` converts relative paths to full length paths using `readlink -m PATHNAME`. This process has an (unfortunate?) consequence of converting paths to their full absolute form on tier 1. The full paths are used on ceph because they inherently show where the original files were once located on tier 1 (making file collisions less likely).
- How much storage am I using on ceph (tier2)?
  - You can run `s3info` to learn how much data is being used. See `s3info --help` for options. Ceph storage is calculated for each MSI user (not by MSI group).
- How can I ensure robust data transfer?
  - `cephtools` creates slurm job scripts that use `rclone` for data transfer. You can review and modify those default scripts. By default, `rclone` uses md5sum checks on every file transfer. So each file transfer is robust. However, when `rclone` checks to see if a file needs to be transfered, it compares the current file against the remote file using file size and timestamp. `cephtools` uses this default action in `dd2ceph`. However, you can have `rclone` make this check using md5sums by adding the `-c` option to `rclone`.
- How can I see the bucket policy for a ceph/tier2 bucket?
    - Try this first: `s3cmd info s3://BUCKET`
    - If that does not work, you may need to use a different command line tool, `aws`, that is not installed on MSI by default. But if you can get access to it, try:
    ```
    export AWS_ACCESS_KEY_ID="$(s3info --keys | awk '{print $1}')"
    export AWS_SECRET_ACCESS_KEY="$(s3info --keys | awk '{print $2}')"
    export AWS_REGION="us-east-1"
    export AWS_DEFAULT_REGION="us-east-1"
    export AWS_OUTPUT="json"
    export AWS_ENDPOINT_URL="https://s3.msi.umn.edu"
    # Get access to aws cli tool
    module load /projects/standard/lmnp/knut0297/software/modulesfiles/aws/2.13.11
    aws s3api get-bucket-policy --bucket BUCKET | jq -r '.Policy'
    ```
    - There is a discussion here, https://github.com/umn-msi-lmnp/cephtools/issues/17, for more details.
