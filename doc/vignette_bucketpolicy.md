# Cephtools: Allow others to access your ceph (tier2) bucket


## Introduction

By default, new ceph buckets can only be accessed by the owner. The purpose of this subcommand is create and apply a "bucket policy" that can change how other ceph users (or even public Internet users) can access files in your bucket. This tool will (1) write a bucket policy (json file), (2) write a readme file describing the changes, and (3) apply the policy to the bucket.  

A few bucket policy presets exist:

* `NONE`: Removes any policy currently set.
* `GROUP_READ`: This policy gives all current users of an MSI group read-only access to all files in bucket. This is great for sharing data with coworkers. 
* `GROUP_READ_WRITE`: This policy gives all current users of an MSI group read and write access to all files in bucket. This is great for allowing coworkers to write files into your bucket.
* `OTHERS_READ`: Allows anyone read-only access to the bucket (i.e. world public read-only access). This policy will expose all files in the bucket to the entire Internet for viewing or downloading. This can be a good option for hosting a public static website (or simple R markdown report, etc.). 




## Set up environment


If necessary, run `newgrp` and set the MYGROUP variable. Then load `cephtools`.


```
# newgrp GROUPNAME
MYGROUP=$(id -ng)

# Load cephtools
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools
```





### Use `cephtools` to set a bucket policy 

For example, it can be helpful to allow anyone in your MSI group read-only access to the archived projects bucket. Running this tool will generate two files (the json bucket policy and a readme), so you should put these files in common location. Re-run the bucket policy command after MSI members are added or removed from group.

```
BUCKET_NAME="my-unique-bucket-name"
```


```
# Change into a common place to store policies
mkdir -p $HOME/ceph/$BUCKET_NAME
cd $HOME/ceph/$BUCKET_NAME

cephtools bucketpolicy --bucket $MYGROUP-$USER-tier1-archive --policy GROUP_READ --group $MYGROUP
```







