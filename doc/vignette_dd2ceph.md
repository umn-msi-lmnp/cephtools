# Cephtools: Transferring `data_delivery` to ceph


## Introduction

Data from various UMN core facilities (e.g. UMGC) export data to a special directory called `data_delivery` for short period of time (~ 1 year). This vignette will describe how to data deposited in `data_delivery` can be easily copied to MSI ceph (tier2) for long term strorage. 



## Create a bucket that all MSI group members can access

*The MSI group PI* (or via sudo) should create a new bucket on ceph, called `GROUP-data-archive` (replacing GROUP with your MSI group name). Later, a bucket policy can be applied to the bucket, controlling access to the bucket for only certain MSI users. This process will ensure the raw data in the bucket are owned by the group's PI username. 

This bucket only needs to be created once. FYI, your current group name can be found by running: `id -ng` on the command line. 




```
MYGROUP=$(id -ng)
s3cmd mb s3://$MYGROUP-data-archive
```

Keep a record of data transfers in shared (common) location (and make sure group permissions are set at this folder):

```
mkdir -p -m ug+rwxs,o-rwx /home/$MYGROUP/shared/dd2ceph
cd /home/$MYGROUP/shared/dd2ceph
```


Use cephtools to set a bucket policy (allow group read and write). 

```
cephtools bucketpolicy -b $MYGROUP-data-archive -p GROUP_READ_WRITE -g $MYGROUP
```


Re-run the bucket policy command after MSI members are added or removed from group




## Transfer data from `data_delivery` to ceph

After the PI's bucket has an READ/WRITE bucket policy set for group member, *the following methods can be done by any group members*. In fact, the data transfer steps below should repeatedly (i.e. after any new datasets are added to `data_delivery` directory). NOTE: you will need to supply your `rclone` remote name in the command below. To learn more about rclone remotes, [see this tips page](https://github.umn.edu/knut0297org/software_tips/tree/main/rclone#umn-tier2-ceph).



As a regular group member (i.e. not the PI), run `newgrp` and set the MYGROUP variable if necessary. Then load `cephtools`.

```
# newgrp GROUPNAME
MYGROUP=$(id -ng)

# Load cephtools
MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$MODULEPATH" module load cephtools
```

Keep a record of data transfers in a common location (make sure permissions are set at this folder). Change into this directory and run `cephtools`.

```
cd /home/$MYGROUP/shared/dd2ceph
# Run with explicit options
# cephtools dd2ceph --bucket $MYGROUP-data-archive --remote ceph --path /home/$MYGROUP/data_delivery

# Run with defaults (same as above)
cephtools dd2ceph -r ceph
```



Review the slurm script (change any parameters you wish) and launch the data transfer job.

```
cd $MYGROUP-data-archive___*
sbatch dd2ceph_*.1_copy.slurm
```




