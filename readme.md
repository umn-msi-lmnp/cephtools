# cephtools

## Introduction

[`cephtools`](https://github.umn.edu/knut0297org/cephtools) is a bash script with various subcommand functions. Their goals are to facilitate interactions between MSI's high performance storage (called panfs, or tier1) and MSI block storage (called [Ceph](https://docs.ceph.com/en/pacific/), or tier2). By default, MSI users can interact with ceph using the [`s3cmd`](https://s3tools.org/usage) command, which was developed for accessing S3-like storage (e.g. Amazon S3, ceph, etc.). Another widely available tool, called [`rclone`](https://rclone.org), can facilitate data transfer between various cloud-like storage resources (e.g. Google Drive, ceph, S3, etc.).

In general, `cephtools` creates slurm job scripts that use these standard tools to transfer or modify data on MSI's ceph.
    


## Installation

There are multiple ways to start using cephtools. See the [Install Options](./install.md) file for details.


## Examples


* See the [Getting Started](./doc/vignette_getting_started.md) vignette for a basic workflow using the cephtools subcommands and FAQs.
* See the [Data Delivery Archive](./doc/vignette_dd2ceph.md) vignette for how to transfer data (e.g. fastqs) from "data_delivery" to ceph.



## Documentation


The program manuals contain detailed information about how each command or subcommand works. These pages can be also be viewed on GitHub as `.ronn` files ([which are nearly equivalent to markdown](https://github.com/apjanke/ronn-ng/blob/master/man/ronn.1.ronn)) here: 

* [cephtools.1](./doc/cephtools.1.ronn)
* [cephtools-dd2ceph.1](./doc/cephtools-dd2ceph.1.ronn)
* [cephtools-panfs2ceph.1](./doc/cephtools-panfs2ceph.1.ronn)
* [cephtools-bucketpolicy.1](./doc/cephtools-bucketpolicy.1.ronn)


```
man cephtools
man cephtools dd2ceph
man cephtools panfs2ceph
man cephtools bucketpolicy
```


Basic command and subcommand help pages can be viewed by running:

```
cephtools --help

cephtools panfs2ceph
cephtools help dd2ceph
cephtools help panfs2ceph
cephtools help bucketpolicy
```



## Contributing

If you would like to make `cephtools` better, please help! Send an email to Todd Knutson [knut0297@umn.edu](mailto:knut0297@umn.edu) or submit a GitHub issue. Thanks!
