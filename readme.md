# panfs2ceph

## Introduction

`panfs2ceph` is a bash script that facilitates transferring data from `panfs` to `ceph`. It has only a few options and is fairly strict in functionality. Its sole purpose is to copy a single directory from tier 1 (`panfs`) storage to tier 2 (`ceph`). 



The script does not actually transfer any data. It simply examines a single input dir on `panfs` and creates five files: 

1. file list (relative file names converted to absolute path names)
2. slurm jobscript (copy data from `panfs` to `ceph`)
3. slurm jobscript (delete data from `panfs`)
4. slurm jobscript (restore data from `ceph` back to `panfs`)
5. a detailed readme file. 

The slurm jobscripts must be launched manually. This allows for time to review the readme, scripts, and file list.



## Details

* All data is copied using `rclone`, which uses MD5 checksums and auto retries on every file transfer to ensure data integrity. 
* The data is not compressed or tar archived (e.g. `.tar.gz`) before transfer. This is intentional. If all files from a large project (i.e. > 1 TB) were concatenated with `tar`, a small data corruption in this huge single file could make recovery of any underlying files difficult. Instead, individual files should be compressed on `panfs` prior to transfer to `ceph`. 
* Uploading individual files allows for easier data browsing directly on `ceph` and/or restoring individual files.
* Each file is transferred to `ceph` as an absolute path name. This creates a lot of "pseudo" dirs on `ceph`, but it helps indicate where the data originally came from on `panfs`
* You must have a properly configured `rclone` installation running on `panfs`. For help setting up `rclone`, see: [https://github.umn.edu/knut0297org/software_tips/tree/master/rclone](https://github.umn.edu/knut0297org/software_tips/tree/master/rclone)
* A new dir is created next to the original input that contains the archive-related files and scripts. This dir is named using the same input path with a suffix (including date and time). 
* Empty directories are copied to ceph by default. Ceph and other bucket-based storage platforms (e.g. `S3`) do not support empty dirs, so `panfs2ceph` creates a hidden file (`.empty_dir`) inside the _previously_ empty dir on `panfs`. This trick ensures empty dirs are preserved in `ceph`. If you do not want to do this, you can set an option `-e`. In which case, no `.empty_dir` files will get created and empty dirs will not be copied to ceph.
* Setting the `--threads` option will create slurm jobscripts using this thread count. `rclone` can transfer data in a multi-threaded way. So this can dramatically increase your overall transfer speed.
* If a bucket does not already exist on `ceph`, it will get created automatically.
* In my experience, creating a unique bucket for each group I work with (e.g. `groupname_knut0297` allows me to separate my archived data and (possibly) apply different access control to each bucket.
* After the data is transferred to `ceph`, the files are verified. Files on `ceph` are listed by rclone and compared against the original input file list. If differences occur, an error will occur. This process occurs at the end of the "copy" jobscript.



## Potential safeguards

* If an input dir already exists on `ceph` in the bucket you provide, the program will stop. This is to ensure you do not accidentally overwrite any data on `ceph`.
* If you try to restore data from `ceph` back to `panfs` and the input dir still exists on `panfs`, the program will stop. This is to ensure you do not accidentally overwrite any data on `panfs`.


## How to install

I have created a module on `panfs` that is accessible by anyone at MSI. You can simply load the module (see below) or clone the GitHub repo and use the script.


## Usage Example

Load the software:

```
module load /home/lmnp/knut0297/software/modulesfiles/panfs2ceph/1.0
```

Generic example:

```
panfs2ceph --help
panfs2ceph --remote <rclone-remote-name> --bucket <ceph-bucket-name> --threads 24 <panfs-path>
```

Specific examples:

```
panfs2ceph --remote todds_umn_ceph --bucket todd /home/lmnp/knut0297/test
panfs2ceph --remote todds_umn_ceph --bucket todd /panfs/roc/scratch/knut0297/test
panfs2ceph --remote todds_umn_ceph --bucket todd ~/test

```

## Help

If you have any questions or discover bugs, please let me know! Send email to Todd Knutson [knut0297@umn.edu](knut0297@umn.edu) or post an issue on the GitHub repo: [https://github.umn.edu/knut0297org/panfs2ceph](https://github.umn.edu/knut0297org/panfs2ceph)

## Disclaimer

This "software" has not been extensively tested. Please be careful and review all scripts and files. Please report any problems. Thanks!
