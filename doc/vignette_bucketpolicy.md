# Cephtools: Allow others to access your ceph (tier2) bucket

## Introduction

By default, new ceph buckets can only be accessed by the owner. The purpose of this subcommand is create and apply a "bucket policy" that can change how other ceph users (or even public Internet users) can access files in your bucket. This tool will (1) write a bucket policy (json file), (2) write a readme file describing the changes, and (3) apply the policy to the bucket.

A few bucket policy presets exist:

- `NONE`: Removes any policy currently set.
- `GROUP_READ`: This policy gives all current users of an MSI group read-only access to all files in bucket. This is great for sharing data with coworkers.
- `GROUP_READ_WRITE`: This policy gives all current users of an MSI group read and write access to all files in bucket. This is great for allowing coworkers to write files into your bucket.
- `OTHERS_READ`: Allows anyone read-only access to the bucket (i.e. world public read-only access). This policy will expose all files in the bucket to the entire Internet for viewing or downloading. This can be a good option for hosting a public static website (or simple R markdown report, etc.).

## Set up environment

Check your current primary (default) group. The primary group for some users is not what they expect.

```
# Check current group
id -ng
```

If necessary, run `newgrp GROUPNAME` to change your current group and set a MYGROUP variable.

```
# Set a variable for group name
MYGROUP=$(id -ng)
```

Load `cephtools` software.

```
MODULEPATH="/projects/standard/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools
```

## Create a bucket

After a bucket is created (that you own), a bucket policy can be applied.

What should I name my bucket? The [Ceph bucket naming rules](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/) can be found here.

```
BUCKET_NAME="my-unique-bucket-name"
s3cmd mb s3://$BUCKET_NAME
```

### Use `cephtools` to set a bucket policy

For example, it can be helpful to allow anyone in your MSI group read-only access to the archived projects bucket. Running this tool will generate two files (the json bucket policy and a readme), so you should put these files in common location. Re-run the bucket policy command after MSI members are added or removed from group.

```
# Change into a common place to store policies
mkdir -p $HOME/ceph/$BUCKET_NAME
cd $HOME/ceph/$BUCKET_NAME

cephtools bucketpolicy -v --bucket $BUCKET_NAME --policy GROUP_READ --group $MYGROUP
```
