# Cephtools: Getting Started

## Introduction

This vignette describes the basic purpose for each of the `cephtools` subcommand functions.

## `panfs2ceph`: Transfer a directory from panfs (tier1) to ceph (tier2)

The purpose of this subcommand is to backup a single directory, and all its contents, from panfs to ceph. The tool will create a working directory and output a file list and slurm job scripts to complete the steps. By default, the working directory is created at the same path as the original input directory, with a suffix name. For example, if the input is `/projects/standard/GROUP/shared/myproject`, the working directory will be created at `/projects/standard/GROUP/shared/myproject___panfs2ceph_archive_DATE`.

Inside the working directory:

- A `PREFIX.1_copy.slurm` job file can be launched to copy all the data to a ceph bucket.
- A `PREFIX.2_verify.slurm` job file can be launched to verify all the data was transferred correctly.
- A `PREFIX.3_delete.slurm` job file can be launched to delete all the data from panfs.
- A `PREFIX.4_restore.slurm` job file can be launched to copy all the data back from ceph to panfs, if you ever need to restore the project directory to the original location.
- Finally, a `PREFIX.readme.md` file is created that describes the process and where the files on ceph are located.

## `bucketpolicy`: Allow others to access your ceph (tier2) bucket

By default, new ceph buckets can only be accessed by the owner. The purpose of this subcommand is create and apply a "bucket policy" that can change how other ceph users (or even public Internet users) can access files in your bucket. This tool will (1) write a bucket policy (json file), (2) write a readme file describing the changes, and (3) apply the policy to the bucket.

A few bucket policy presets exist:

- `NONE`: Removes any policy currently set.
- `GROUP_READ`: This policy gives all current users of an MSI group read-only access to all files in bucket. This is great for sharing data with coworkers.
- `GROUP_READ_WRITE`: This policy gives all current users of an MSI group read and write access to all files in bucket. This is great for allowing coworkers to write files into your bucket.
- `OTHERS_READ`: Allows anyone read-only access to the bucket (i.e. world public read-only access). This policy will expose all files in the bucket to the entire Internet for viewing or downloading. This can be a good option for hosting a public static website (or simple R markdown report, etc.).
- `LIST_READ`: Allows a specific list of users to have read-only access to the bucket. Must be a comma separated x500 list without spaces.
- `LIST_READ_WRITE`: Allows a specific list of users to have read and write access to the bucket. Must be a comma separated x500 list without spaces.

## `dd2ceph`: Backup all files in a group's data_delivery folder to ceph (tier2)

The purpose of this subcommand is to backup all of the data in the group's special "data_delivery" or "data_release" directories (e.g. sequencing data from UMGC or other core facilities). The data deposited into these directories are automatically deleted after a period of time (~ 1 year), so backing up the data is essential. The tool finds all files (and follows symbolic links) in the directory and copies it to ceph (tier2). The tool will create a working directory and output a file list and a slurm job script to complete the steps. By default, the working directory is created at `/projects/standard/MYGROUP/shared/dd2ceph`.

Inside the working directory:

- A `PREFIX.1_copy.slurm` job file can be launched to copy all the data to a ceph bucket.
- A `PREFIX.readme.md` file is created that describes the process and where the files on ceph are located.

## `dd2dr`: Backup all files in a group's data_delivery folder to disaster_recovery (tier1)

The purpose of this subcommand is to backup all of the data in the group's special "data_delivery" or "data_release" directories to MSI's Tier 1 `disaster_recovery` directory for backup and long-term storage. The folder `$MSIPROJECT/shared/disaster_recovery` is special because all data in the directory are backed up automatically off-site (not at MSI in Walter library). The tool finds all files (and follows symbolic links) in the directory and copies it to `disaster_recovery`. The tool will create a working directory and output a file list and a slurm job script to complete the steps. By default, the working directory is created at `$MSIPROJECT/shared/cephtools/dd2dr`.

Inside the working directory:

- A `PREFIX.1_copy.slurm` job file can be launched to copy all the data to the disaster recovery directory.
- A `PREFIX.readme.md` file is created that describes the process and where the files in disaster recovery are located.

## `filesinbackup`: Create file lists from tier 2 bucket and `shared/disaster_recovery`

The purpose of this subcommand is to generate a list of files that are stored in a tier 2 bucket. It also generates a file list for all files in the $MSIPROJECT/shared/disaster_recovery. Finally, the tool will compare these file lists and report differences. Many people backup files in these two locations, but it's helpful to have a current list of files.  

## FAQs

- How do these tools handle symbolic links?
  - `panfs2ceph` does NOT follow symbolic links and does not transfer the actual file. It transfers the symbolic link itself. See the `rclone` flag [`--links`](https://rclone.org/local/#links-l) for details. `dd2ceph` DOES follow symbolic links and copies the actual file (i.e. it copies the dereferenced file).
- How fast is the transfer?
  - The empirical data transfer rate from panfs to ceph is approximately 1 TB per 30 min (or around 30 GB/min). By default, `panfs2ceph` requests a 24 hr job time and `dd2ceph` requests a 72 hr job time. These times can be adjusted directly in the slurm script before launching. Reviewing the end of a slurm error log file will show a summary from `rclone`, indicating how much data was transfered and how long it took.
- Do I have to create a bucket first?
  - Yes, you'll need to create a bucket before using it with `cephtools`. `cephtools` checks that the bucket exists before running for added safety and transparency. `rclone` can automatically create buckets when transferring for the first time, but `cephtools` fails before writing the "copy" slurm script if the bucket does not exist. To create a new bucket, run: `s3cmd mb s3://MY-BUCKET-NAME`.
- How should I name buckets?
  - Ceph is an open-source software storage platform that uses the Amazon S3 APIs. Ceph allows for buckets to be named with underscores, but some S3 APIs will fail if they find buckets with underscores. I think everything in `cephtools` will work with underscores in the bucket names, but use hyphens to be safe. [Amazon bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html) and [Ceph bucket naming rules](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/)
  - **Important:** Do not include trailing slashes in bucket names (e.g., avoid `"bucketname/"`). `cephtools` will automatically remove trailing slashes, but bucket names with internal slashes may cause issues and will generate warnings.
- How are relative paths handled?
  - `cephtools` converts relative paths to full length paths using `readlink -m PATHNAME`. This process has an (unfortunate?) consequence of converting paths to `/panfs/roc/groups/INTEGER/MYGROUP`, `/panfs/jay/groups/INTEGER/MYGROUP`, or `/data_delivery/MYGROUP` paths on ceph. The full paths are used on ceph because they inherently show where the original files were once located on panfs (making file collisions less likely).
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
    - There is a discussion here, https://github.umn.edu/lmnp/cephtools/issues/17, for more details.
