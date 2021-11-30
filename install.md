# cephtools installation instructions

## Introduction

There are multiple ways to start using cephtools. 

1. Load an available module
1. Clone the repo and checkout any version tag or commit


### Load an available module

```
# Check available versions
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module avail cephtools

# Load a module
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles" module load cephtools/2.0.0
```



### Clone the repo and checkout any version tag or commit

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


# Update paths
# Add these to your ~/.bashrc if you want cephtools available in every new shell
export PATH="${PWD}/build/bin:${PATH}"
export MANPATH="${PWD}/build/share/man:${MANPATH}"
```


