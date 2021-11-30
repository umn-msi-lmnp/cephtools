# cephtools

## Introduction

`cephtools` is a bash script that facilitates transferring data from `panfs` to `ceph`. It has only a few options and is fairly strict in functionality. Cephtools has various subcommands (e.g. `panfs2ceph`) that perform specific tasks. More subcommands will be added soon (e.g. transferring fastqs from `data_delivery` and setting bucket access policies). See the documentation below for details.
    


## Installation

There are multiple ways to start using cephtools. See [./install.md](./install.md) for details.


## Examples



## Documentation

You can see the program or subcommand help pages using the following:

```
cephtools
cephtools -h
cephtools --help

cephtools panfs2ceph
cephtools help panfs2ceph
```

The program man pages contain detailed information about how each command or subcommand works. These pages can be also be viewed on GitHub as `.ronn` files ([which are nearly equivalent to markdown](https://github.com/apjanke/ronn-ng/blob/master/man/ronn.1.ronn)) here: 

* [./doc/cephtools.1.ronn](./doc/cephtools.1.ronn)
* [./doc/cephtools-panfs2ceph.1.ronn](./doc/cephtools-panfs2ceph.1.ronn)


```
man cephtools
man cephtools panfs2ceph
```


## Contributing

If you would like to make `cephtools` better, please help! Send an email to Todd Knutson [knut0297@umn.edu](mailto:knut0297@umn.edu) or submit a GitHub issue. Thanks!
