# Cephtools: Getting Started

## Introduction

This vignette describes the basic purpose for each of the `cephtools` subcommand functions. 



## `panfs2ceph`: Transfer a directory from panfs (tier1) to ceph (tier2)


The purpose of this subcommand is to backup a single directory, and all its contents, from panfs to ceph. The tool will create a working directory and output a filelist and slurm job scripts to complete the steps. By default, the working directory is created at the same path as the original input directory, with a suffix name. For example, if the input is `/home/group/shared/project`, the working directory will be created at `/home/group/shared/project___panfs2ceph_archive_DATE`. 

Inside the working directory:

* A `PREFIX.1_copy.slurm` job file can be launched to copy all the data to a ceph bucket. 
* A `PREFIX.2_delete.slurm` job file can be launched to delete all the data from panfs. 
* A `PREFIX.3_restore.slurm` job file can be launched to copy all the data back from ceph to panfs, if you ever need to restore the project directory to the original location.
* Finally, a `PREFIX.readme.md` file is created to describe the process and where to find the original data on ceph.








## `bucketpolicy`: Allow others to access your ceph (tier2) bucket

By default, new ceph buckets can only be accessed by the owner. The purpose of this subcommand is create and apply a "bucket policy" that can change how other ceph users (or even public Internet users) can access files in your bucket. This tool will (1) write a bucket policy (json file), (2) write a readme file describing the changes, and (3) apply the policy to the bucket.  

A few bucket policy presets exist:

* `NONE`: Removes any policy currently set.
* `GROUP_READ`: This policy gives all current users of an MSI group read-only access to all files in bucket. This is great for sharing data with coworkers. 
* `GROUP_READ_WRITE`: This policy gives all current users of an MSI group read and write access to all files in bucket. This is great for allowing coworkers to write files into your bucket.
* `OTHERS_READ`: Allows anyone read-only access to the bucket (i.e. world public read-only access). This policy will expose all files in the bucket to the entire Internet for viewing or downloading. This can be a good option for hosting a public static website (or simple R markdown report, etc.). 









## `dd2ceph`: Backup all files in a group's data_delivery folder to ceph (tier2)















