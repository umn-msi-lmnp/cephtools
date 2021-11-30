# cephtools installation instructions

## Introduction

There are multiple ways to start using cephtools. 

1. Load an available module
1. Download an archived version
1. Clone the repo and checkout any version tag or commit


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


