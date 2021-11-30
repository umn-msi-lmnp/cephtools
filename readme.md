# cephtools

## Introduction


Submit an Issue.


## Installation

There are three ways to start using cephtools. 

1. Load an available module
1. Download an archived version
1. Clone the repo and checkout any version/commit

### Load an available module

```
# Check available versions
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module avail cephtools

# Load a module
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module load cephtools/2.0.0
```


### Download an archived version

Find available versions here: [https://github.umn.edu/knut0297org/cephtools/tags](https://github.umn.edu/knut0297org/cephtools/tags)

```
# Download a version
cephtools_ver="v2.0.0"
wget https://github.umn.edu/knut0297org/cephtools/archive/${cephtools_ver}.tar.gz

# Update paths
# Add these to your ~/.bashrc if you want cephtools available in every new shell
export PATH="${PWD}/cephtools/build/bin:${PATH}"
export MANPATH="${PWD}/cephtools/build/share/man:${MANPATH}"
```



### Clone the repo

```
git clone wget https://github.umn.edu/knut0297org/cephtools
git checkout tags/<tag_name>
git checkout <commit>

# Update paths
# Add these to your ~/.bashrc if you want cephtools available in every new shell
export PATH="${PWD}/cephtools/build/bin:${PATH}"
export MANPATH="${PWD}/cephtools/build/share/man:${MANPATH}"
```



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
