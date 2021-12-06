# cephtools installation instructions

## Introduction

There are multiple ways to start using cephtools. 

1. Load an available module
1. Clone the repo and checkout any version tag or commit


### Load an available module

```
# Check available versions
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module avail cephtools

# Load the default (i.e. most current) version
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module load cephtools

# Load a specific version
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module load cephtools/2.0.0
```



### Clone the repo and checkout any version tag or commit

#### Download
The repo is located on the UMN GitHub site, but is public to anyone with access to [github.umn.edu](github.umn.edu). However, using `wget` with https does not work because you need to authenticate using your UMN GitHub credentials. 


```
git clone git@github.umn.edu:knut0297org/cephtools.git
cd cephtools

# List available tags
git tag

# List recent commits
git log

git checkout tags/<tag_name>
git checkout <commit>

```



#### Build the tool

The repo contains a makefile that will build the final bash script and manual pages. By default, a "build" dir is created inside the cephtools repo that will contain the program.
 
```
# Move into the repo dir (cephtools) and run make
make

# Update paths
# Add these to your ~/.bashrc if you want cephtools available in every new shell
export PATH="${PWD}/build/bin:${PATH}"
export MANPATH="${PWD}/build/share/man:${MANPATH}"
```



If you want to build the program in a different location, specify an build/install directory by setting a PREFIX variable when running `make`.


```
# Move into the repo dir (cephtools) and run make
PREFIX=/my/fav/build/dir make

# Update paths
# Add these to your ~/.bashrc if you want cephtools available in every new shell
export PATH="${PREFIX}/build/bin:${PATH}"
export MANPATH="${PREFIX}/build/share/man:${MANPATH}"
```



