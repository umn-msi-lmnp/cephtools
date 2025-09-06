# cephtools

## Introduction

[`cephtools`](https://github.umn.edu/lmnp/cephtools) is a bash script with various subcommand functions. Their goals are to facilitate interactions between MSI's high performance storage (called panfs, vast, or tier1) and MSI block storage (called [Ceph](https://docs.ceph.com/en/pacific/), or tier2). By default, MSI users can interact with ceph using the [`s3cmd`](https://s3tools.org/usage) command, which was developed for accessing S3-like storage (e.g. Amazon S3, ceph, etc.). Another widely available tool, called [`rclone`](https://rclone.org), can facilitate data transfer between various cloud-like storage resources (e.g. Google Drive, ceph, S3, etc.).

In general, `cephtools` creates slurm job scripts that use these standard tools to transfer or modify data on MSI's ceph.

## Installation

There are a few ways to start using cephtools. See the [Install Options](./install.md) file for details.

## Examples

- See the [Getting Started Guide](./doc/vignette_getting_started.md) for a basic workflow using the cephtools subcommands and FAQs.
- See the [Data Delivery Archive](./doc/vignette_dd2ceph.md) tutorial for how to transfer data (e.g. fastqs) from "data_delivery" to ceph.
- See the [Directory Backup](./doc/vignette_panfs2ceph.md) tutorial for how to transfer a single directory (e.g. project) to ceph.
- See the [Bucket Access Control](./doc/vignette_bucketpolicy.md) tutorial for how to change ceph bucket policies to share data between groups or the public.
- See the [Files in Backup](./doc/vignette_filesinbackup.md) tutorial for how to create file lists from your ceph bucket or disaster_recovery dir.

## Documentation

### Quick Command Help

Built-in help provides detailed information about each command and its options:

```
cephtools --help

cephtools help panfs2ceph
cephtools help dd2ceph
cephtools help bucketpolicy
cephtools help dd2dr
cephtools help filesinbackup
```


## Contributing

If you would like to make `cephtools` better, please help! Send an email to [lmp-help@msi.umn.edu](mailto:lmp-help@msi.umn.edu) or submit a GitHub issue. Thanks!
