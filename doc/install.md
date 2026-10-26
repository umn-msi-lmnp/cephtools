# cephtools installation instructions

> **Note:** If you're reading this on GitHub, the `@SEMANTIC_VERSION@` placeholder below is replaced automatically at build time. To find the current version, visit the [latest release](https://github.com/umn-msi-lmnp/cephtools/releases).

## Introduction

There are two ways to install and use cephtools:

1. **Download a pre-built release** (Recommended) - Download a release tarball from GitHub, extract it, and use it immediately. No build process required.
2. **Clone the repo and build** - For developers or users who need specific commits or want to customize the tool.

Cephtools is not installed in a common location that is accessible to all MSI users like MSI-supported software. Choose the installation method that best fits your needs.

## Method 1: Download a Pre-Built Release (Recommended)

This is the easiest way to install cephtools. Pre-built releases are available on GitHub and require no compilation.

### Download a Release

1. Visit the [releases page](https://github.com/umn-msi-lmnp/cephtools/releases) to see all available versions
2. Download the `.tar.gz` file for your desired version
3. Extract the archive:

```bash
# Download the release. To install a different release, change only CEPHTOOLS_VERSION.
CEPHTOOLS_VERSION=@SEMANTIC_VERSION@
wget "https://github.com/umn-msi-lmnp/cephtools/releases/download/${CEPHTOOLS_VERSION}/cephtools-${CEPHTOOLS_VERSION}.tar.gz"

# Extract the tar.gz file
tar -xzf "cephtools-${CEPHTOOLS_VERSION}.tar.gz"
```

### Update your PATH variable

Add the cephtools `bin` directory to your PATH:

```bash
# If you extracted in your current directory
export PATH="${PWD}/cephtools-${CEPHTOOLS_VERSION}/bin:${PATH}"
```

To make this permanent, add the export command to your `~/.bashrc` file:

```bash
echo "export PATH=\"${PWD}/cephtools-${CEPHTOOLS_VERSION}/bin:\${PATH}\"" >> ~/.bashrc
source ~/.bashrc
```

Enable Bash command line completion for cephtools commands and options:

```bash
CEPHTOOLS_BIN="$(command -v cephtools)"
CEPHTOOLS_ROOT="$(cd "$(dirname "${CEPHTOOLS_BIN}")/.." && pwd)"

mkdir -p "${HOME}/.local/share/bash-completion/completions"
ln -sfn "${CEPHTOOLS_ROOT}/share/bash-completion/completions/cephtools" "${HOME}/.local/share/bash-completion/completions/cephtools"
source "${HOME}/.local/share/bash-completion/completions/cephtools"
```

### Verify installation

```bash
cephtools --help
```

## Method 2: Clone the Repo and Build

This method is recommended for developers or users who need access to specific commits, unreleased features, or want to contribute to development.

### Clone the repository

- The cephtools repo is a public repo on GitHub, allowing anyone with access to [github.com](https://github.com) to view or clone the files.
- Cloning from GitHub can be done in two ways: using ssh keys or via https. The https method may require you to authenticate.

```bash
git clone git@github.com:umn-msi-lmnp/cephtools.git

# Or, if you do not have ssh key set up, try the https approach:
# git clone https://github.com/umn-msi-lmnp/cephtools.git

# Change into the source dir
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
export PATH="/my/fav/build/dir/bin:${PATH}"
```

To make the default build path permanent, add the export command to your `~/.bashrc` file:

```bash
echo "export PATH=\"${PWD}/build/bin:\${PATH}\"" >> ~/.bashrc
source ~/.bashrc
```

Enable Bash command line completion for cephtools commands and options:

```bash
CEPHTOOLS_BIN="$(command -v cephtools)"
CEPHTOOLS_ROOT="$(cd "$(dirname "${CEPHTOOLS_BIN}")/.." && pwd)"

mkdir -p "${HOME}/.local/share/bash-completion/completions"
ln -sfn "${CEPHTOOLS_ROOT}/share/bash-completion/completions/cephtools" "${HOME}/.local/share/bash-completion/completions/cephtools"
source "${HOME}/.local/share/bash-completion/completions/cephtools"
```
