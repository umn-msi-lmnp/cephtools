# cephtools installation instructions

## Introduction

There are two ways to access cephtools. Cephtools is not installed in a common location that is accessible to all MSI users, like MSI-supported software. Therefore, the primary way you can access cephtools is by downloading the code, and building the tool in your MSI project space. If you are a member of the `lmnp` MSI project, you can load one of my pre-built modules (but that is possible for only a few people). 

## Clone the repo and checkout any version tag or commit

### tl;dr

```
git clone git@github.com:umn-msi-lmnp/cephtools.git
# OR, if you do not have ssh key set up, try the https approach (entering your UMN username/password when prompted):
# git clone https://github.com/umn-msi-lmnp/cephtools.git
cd cephtools
make
export PATH="${PWD}/build/bin:${PATH}"
cephtools --help
```

### Download

- The cephtools repo is a public repo on the UMN GitHub site, allowing anyone with access to [github.com](https://github.com) to view or clone the files. 
- To clone any repo from the UMN GitHub site, you need to initialize your UMN GitHub account by visiting [github.com](https://github.com) and logging-in using your UMN Internet ID and password.
- If you're reading this, you've likely already done that step! However, if you are helping someone else try to clone the repo from the command line (i.e. a PI), make sure they have initialized their GitHub account first (otherwise you'll see unclear permissions errors).
- Cloning from GitHub can be done in two ways, using ssh keys or via https. The https method requires you to enter your UMN Internet ID/password on the command line to download. 

```
git clone git@github.com:umn-msi-lmnp/cephtools.git
# OR, if you do not have ssh key set up, try the https approach:
# git clone https://github.com/umn-msi-lmnp/cephtools.git
cd cephtools
```


### Choose a version

Cloning the repo gives you full access to all the tags and commits. The tagged versions should be stable, but the main branch should contain the most current (possibly unstable) code.

```
# List available tags
git tag

# List recent commits
git log

# Switch to a specific tag or commit
git checkout tags/<tag_name>
git checkout <commit>
```

### Build the tool

The repo contains a makefile that will build the final bash script for you. By default, running `make` will create a new dir named "build" inside the cephtools dir that will contain the program. Make sure you change into the cephtools directory, then run make.

```
make
```

If you want to build the program in a different location, specify an build/install directory by setting a PREFIX variable when running `make`.

```
make PREFIX=/my/fav/build/dir
```


### Update your PATH variable

Update your PATH variable to include the cephtools bin dir.

```
# If you built the tool with default build prefix
export PATH="${PWD}/build/bin:${PATH}"

# Or, if you specified a PREFIX
export PATH="${PREFIX}/bin:${PATH}"
```

If you are still located in the `cephtools` dir, and you built the tool with default build prefix (`./build`), then running the following commands will add/remove cephtools from your PATH variable. 

```
module load ./modulefile
module unload ./modulefile
```




## Load a module *(only if you are a member of the `lmnp` MSI project/group)*

Cephtools was installed as a module inside the `lmnp` MSI project space. Only members of this project can access files in that project. Therefore, this approach will only work for lmnp project members.

### Load the default version (i.e. most current).

```
MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools
```

### Check available versions or load a specific version

```
MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module avail cephtools

MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools/2.0.0
```

> Technical note:
>
> If you include `MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH"` before running the `module` commands (e.g. `avail`, `load`, etc.), the `MODULEPATH` variable will be prepended to include this personal modulefile path, in addition to the default MSI modulefile paths normally included in the `MODULEPATH` variable. Doing this will not export or permanently change your `MODULEPATH` variable -- it only changes your `MODULEPATH` variable for the single `module` command, run on the same line.
