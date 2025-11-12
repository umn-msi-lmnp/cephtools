# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Updated GitHub Actions release workflow to use cephtools-TAG for build directory naming
- Added doc folder to release artifacts

## [3.9.1] - 2025-10-28

### Fixed
- Fixed bash array expansion for set -u compatibility with empty arrays

## [3.9.0] - 2025-10-28

### Fixed
- Fixed plugin discovery for portable tarball deployments by detecting executable location. This will allow tarballs to be generated and saved as a GitHub Release asset (making installation easier). 

## [3.8.0] - 2025-10-28

### Added
- Added GitHub Actions workflow for automated releases

### Fixed
- Fixed rclone symlink error with README.txt in surfs directory
- Stopped attempting to print source data delivery files in dd2dr plugin

## [3.7.0] - 2025-09-24

### Added
- Added symlink handling to dd2dr plugin

### Fixed
- Fixed rclone symlink functionality
- Fixed unbound variable issue
- Fixed empty directory handling approach

### Changed
- Updated empty directory handling to manual approach (vs. using rclone's approach).
- Updated testing scripts

## [3.6.0] - 2025-09-15

### Changed
- Updated default bucket naming to data-delivery-GROUP format

## [3.5.0] - 2025-09-15

### Changed
- Updated handling of empty directories for panfs2ceph

### Fixed
- Fixed variable name issue
- Improved rclone check settings
- Updated terminal messages and test output directories

## [3.4.0] - 2025-09-12

### Changed
- Refactored dd2ceph and panfs2ceph to share code and unify implementation
- Cleaned up test suite significantly

### Fixed
- Fixed rclone version parsing

## [3.2.0] - 2025-09-12

### Added
- Added md5sum outputs to the filesinbackup command
- Added documentation for getting bucket policy information

### Fixed
- Fixed error function to use correct exit method

## [3.1.0] - 2025-09-10

### Added
- Implemented rclone's native copy empty directories flags

### Changed
- Updated rclone dependency to version 1.67.0

## [3.0.0] - 2025-09-08

### Added
- Added dd2dr vignette documentation
- Added verbose functionality with reporting functions

### Changed
- Major refactor for version 3.0.0
- Updated bucketpolicy to use Ceph usernames instead of UMN usernames
- Updated permissions for dd2dr
- Updated panfs2ceph vignette documentation

### Fixed
- Fixed real S3 integration tests
- Cleaned up filesinbackup vignette

## [2.8.1] - 2025-07-10

### Changed
- Updated makefile to skip docs by default
- Removed docs from all makefile target
- Updated install documentation

### Fixed
- Fixed make bucket variable typo
- Fixed bucket policy logic

## [2.7.2] - 2022-12-07

### Changed
- Dynamically choose best SLURM partition for jobs

## [2.7.1] - 2022-11-29

### Changed
- Updated subcommands to use new s3info calls

## [2.7.0] - 2022-03-16

### Added
- Added ability for panfs2ceph to specify a working directory for log files

## [2.6.0] - 2022-03-08

### Added
- Added list option to bucketpolicy command

## [2.5.0] - 2022-02-09

### Added
- Added bucketpolicy vignette documentation
- Added panfs2ceph vignette documentation
- Added FAQ about md5sums
- Added FAQ about storage quotas

### Changed
- Updated bucketpolicy to support creating new buckets
- Changed default threads to 16 for panfs2ceph
- Enhanced getting started documentation significantly

## [2.4.0] - 2022-01-13

### Added
- Added OTHERS_READ public bucket policy option

## [2.3.2] - 2021-12-19

### Changed
- Updated bucket policy methods

### Fixed
- Fixed bucketpolicy readme to show correct usernames

## [2.3.1] - 2021-12-16

### Added
- Added file list sorting for easier diff comparison
- Keep additional file lists after comparison

### Fixed
- Fixed rsync functionality
- Fixed typos and improved sbatch launch documentation

## [2.3.0] - 2021-12-15

### Added
- Added verbose functionality and reporting
- Added dd2ceph manual page
- Added readme output file for bucketpolicy subcommand

### Changed
- Cleaned up heredocs with verbose statements
- Updated readme to include dd2ceph documentation
- Write out blank file when policy is set to NONE

## [2.2.2] - 2021-12-14

### Changed
- Updated bucketpolicy help information

### Fixed
- Fixed bucket policies to allow for different policy types

## [2.2.1] - 2021-12-14

### Added
- Added link to rclone config setup documentation
- Updated makefile to include vignette documentation

### Changed
- Changed options ordering

### Fixed
- Fixed rclone config path
- Updated rclone version checks
- Fixed many small issues

## [2.0.2] - 2021-12-06

### Added
- Added support for symlinks to panfs2ceph

### Changed
- Updated readme to note permissions not preserved on directories after restore
- Added archive date and time to readme
- Set directory permissions on new working directory

### Fixed
- Fixed PREFIX variable location when running make
- Updated install instructions

## [2.0.0] - 2021-11-30

### Added
- Added new subcommand: bucketpolicy
- Added new subcommand: dd2ceph
- Added cephtools man page
- Added makefile with documentation target
- Added MIT license
- Added subcommands architecture

### Changed
- Major refactor to plugin-based architecture
- Updated panfs2ceph to new subcommand format
- Improved readme with better installation information
- Added independent version file

### Removed
- Removed old panfs2ceph single script

## [1.0.0] - 2020-12-08

### Added
- Initial release with panfs2ceph functionality
- Remote and bucket validation
- Rclone integration for Ceph object storage
- Basic verification and installation documentation
