# cephtools installation instructions

## Introduction

There are three ways to install and use cephtools:

1. **Download a pre-built release** (Recommended) - Download a release tarball or zip file from GitHub, extract it, and use it immediately. No build process required.
2. **Clone the repo and build** - For developers or users who need specific commits or want to customize the tool.
3. **Load a module** - Only available for members of the `lmnp` MSI project.

Cephtools is not installed in a common location that is accessible to all MSI users like MSI-supported software. Choose the installation method that best fits your needs.

## Method 1: Download a Pre-Built Release (Recommended)

This is the easiest way to install cephtools. Pre-built releases are available on GitHub and require no compilation.

### tl;dr

```bash
# Download the latest release
wget https://github.com/umn-msi-lmnp/cephtools/releases/download/3.10.0/cephtools-3.10.0.tar.gz

# Extract the archive
tar -xzf cephtools-3.10.0.tar.gz

# Add to PATH
export PATH="${PWD}/cephtools-3.10.0/bin:${PATH}"

# Test it
cephtools --help
```

### Download a Release

1. Visit the [releases page](https://github.com/umn-msi-lmnp/cephtools/releases) to see all available versions
2. Download either the `.tar.gz` or `.zip` file for your desired version
3. Extract the archive:

```bash
# For tar.gz files
tar -xzf cephtools-VERSION.tar.gz

# For zip files
unzip cephtools-VERSION.zip
```

### Update your PATH variable

Add the cephtools `bin` directory to your PATH:

```bash
# If you extracted in your current directory
export PATH="${PWD}/cephtools-VERSION/bin:${PATH}"

# Or specify the full path
export PATH="/path/to/cephtools-VERSION/bin:${PATH}"
```

To make this permanent, add the export command to your `~/.bashrc` file:

```bash
echo 'export PATH="/path/to/cephtools-VERSION/bin:${PATH}"' >> ~/.bashrc
source ~/.bashrc
```

### Verify installation

```bash
cephtools --help
cephtools --version
```

## Method 2: Clone the Repo and Build

This method is recommended for developers or users who need access to specific commits, unreleased features, or want to contribute to development.

### tl;dr

```bash
git clone git@github.com:umn-msi-lmnp/cephtools.git
# OR, if you do not have ssh key set up, try the https approach:
# git clone https://github.com/umn-msi-lmnp/cephtools.git
cd cephtools
make
export PATH="${PWD}/build/bin:${PATH}"
cephtools --help
```

### Clone the repository

- The cephtools repo is a public repo on GitHub, allowing anyone with access to [github.com](https://github.com) to view or clone the files.
- Cloning from GitHub can be done in two ways: using ssh keys or via https. The https method may require you to authenticate.

```bash
git clone git@github.com:umn-msi-lmnp/cephtools.git
# OR, if you do not have ssh key set up, try the https approach:
# git clone https://github.com/umn-msi-lmnp/cephtools.git
cd cephtools
```

### Choose a version

Cloning the repo gives you full access to all tags and commits. Tagged versions should be stable, but the main branch contains the most current (possibly unstable) code.

```bash
# List available tags
git tag

# List recent commits
git log

# Switch to a specific tag or commit
git checkout tags/<tag_name>
git checkout <commit>
```

### Build the tool

The repo contains a makefile that will build the final program. By default, running `make` creates a `build` directory inside the cephtools directory.

```bash
make
```

If you want to build the program in a different location, specify a build/install directory by setting a PREFIX variable:

```bash
make PREFIX=/my/fav/build/dir
```

### Update your PATH variable

Update your PATH variable to include the cephtools bin directory:

```bash
# If you built the tool with default build prefix
export PATH="${PWD}/build/bin:${PATH}"

# Or, if you specified a PREFIX
export PATH="${PREFIX}/bin:${PATH}"
```

If you are still located in the `cephtools` directory and you built the tool with default build prefix (`./build`), you can use the modulefile:

```bash
module load ./modulefile
module unload ./modulefile
```




## Method 3: Load a Module (lmnp MSI project members only)

Cephtools is installed as a module inside the `lmnp` MSI project space. Only members of this project can access files in that project. Therefore, this approach will only work for lmnp project members.

### Load the default version

```bash
MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools
```

### Check available versions or load a specific version

```bash
MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module avail cephtools

MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools/2.0.0
```

> Technical note:
>
> If you include `MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH"` before running the `module` commands (e.g. `avail`, `load`, etc.), the `MODULEPATH` variable will be prepended to include this personal modulefile path, in addition to the default MSI modulefile paths normally included in the `MODULEPATH` variable. Doing this will not export or permanently change your `MODULEPATH` variable -- it only changes your `MODULEPATH` variable for the single `module` command, run on the same line.
