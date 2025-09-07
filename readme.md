# cephtools

## Introduction

[`cephtools`](https://github.umn.edu/lmnp/cephtools) is a bash script with various subcommand functions. Their goals are to facilitate interactions between MSI's high performance storage (called panfs, vast, or tier1) and MSI block storage (called [Ceph](https://docs.ceph.com/en/pacific/), or tier2). By default, MSI users can interact with ceph using the [`s3cmd`](https://s3tools.org/usage) command, which was developed for accessing S3-like storage (e.g. Amazon S3, ceph, etc.). Another widely available tool, called [`rclone`](https://rclone.org), can facilitate data transfer between various cloud-like storage resources (e.g. Google Drive, ceph, S3, etc.).

In general, `cephtools` creates slurm job scripts that use these standard tools to transfer or modify data on MSI's ceph, but does *not* automatically launch or run those job scripts. This is a design philosophy, to give you a chance to review the job commands and understand or modify them before running.   

## Installation

There are a couple ways to install cephtools. See the [Install Options](./install.md) file for details.

## Tutorials

- See the [Getting Started Guide](./doc/vignette_getting_started.md) for a basic workflow using the cephtools subcommands and FAQs.
- See the [Directory Backup](./doc/vignette_panfs2ceph.md) tutorial for using `pandfs2ceph` to transfer a single directory (e.g. project) to ceph.
- See the [Data Delivery Transfer to Tier 1](./doc/vignette_dd2dr.md) tutorial for using `dd2dr` to copy files from "data_delivery" to your Tier 1 shared/disaster_recovery dir.
- See the [Data Delivery Archive to Tier 2](./doc/vignette_dd2ceph.md) tutorial for using `dd2ceph` to transfer data (e.g. fastqs) from "data_delivery" to ceph.
- See the [Bucket Access Control](./doc/vignette_bucketpolicy.md) tutorial for using `bucketpolicy` to change ceph bucket policies to enable easy data sharing data between groups or the public.
- See the [Files in Backup](./doc/vignette_filesinbackup.md) tutorial for using `filesinbackup` to create file lists from your ceph bucket or disaster_recovery dir.

## Documentation

### Quick Command Help

Built-in help pages provide detailed information about each command and its options:

```
cephtools --help

cephtools help panfs2ceph
cephtools help dd2dr
cephtools help dd2ceph
cephtools help bucketpolicy
cephtools help filesinbackup
```


## Contributing

If you would like to make `cephtools` better, please help! Send an email to [lmp-help@msi.umn.edu](mailto:lmp-help@msi.umn.edu) or submit a GitHub issue. Thanks!
