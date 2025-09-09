# Cephtools: Transferring `data_delivery` to ceph

## Introduction

Data from various UMN core facilities (e.g. UMGC) export data to a special directory called `data_delivery` for short period of time (~ 1 year). This vignette will describe how to data deposited in `data_delivery` can be easily copied to MSI ceph (tier2) for long term strorage.

## Step 1: Create bucket and set a policy _(completed once, preferably by the MSI group PI)_

Create a bucket that all MSI group members can access.

_The MSI group PI_ (or via sudo) should create a new bucket on ceph, called `GROUP-data-archive` (replacing GROUP with your MSI group name). Later, a bucket policy can be applied to the bucket, controlling access to the bucket for only certain MSI users. This process will ensure the raw data in the bucket are owned by the group's PI username. This bucket only needs to be created once.

> NOTE: Before completing these steps, you can check to see whether the bucket you plan to create already exists. Running `s3cmd ls s3://BUCKETNAME` will return an ERROR if it does not exist or if you cannot access it. If it exists and you can access it, no error is given. [Skip to **Step 2** below](#step-2-transfer-data-to-ceph-completed-my-any-group-member-repeatedly).

1. Set up environment.

   The PI should log into MSI and check their current primary (default) group. The primary group for some PIs is not their own group (i.e. sometimes a PI has their group set to a different group).

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
   module load cephtools
   ```

2. Create the ceph (tier2) bucket.

   ```
   s3cmd mb s3://$MYGROUP-data-archive
   ```

3. Create working directory.

   Keep a record of all data transfers in shared (common) location. Make sure group permissions are set at this folder.

   ```
   mkdir -m ug+rwxs -p /projects/standard/$MYGROUP/shared/dd2ceph
   cd /projects/standard/$MYGROUP/shared/dd2ceph
   ```

4. Set bucket policy

   Use `cephtools` to set a bucket policy that will allow all MSI group members read and write access. Re-run the bucket policy command above after MSI members are added or removed from group.

   ```
   cephtools bucketpolicy -v -b $MYGROUP-data-archive -p GROUP_READ_WRITE -g $MYGROUP
   ```

## Step 2: Transfer data to ceph _(completed my any group member, repeatedly)_

After the PI's bucket has a group READ/WRITE bucket policy set, _the following methods can be done by any group members_. In fact, the data transfer steps below should be done repeatedly (i.e. after any new datasets are added to `data_delivery` directory). NOTE: you will need to supply your `rclone` remote name in the command below. [To learn more about rclone remotes and how to set one up, see this tips page](https://github.umn.edu/lmnp/tips/tree/main/rclone#umn-tier2-ceph).

1. Set up environment.

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
   module load cephtools
   ```

2. Change into the working directory (created above).

   ```
   cd /projects/standard/$MYGROUP/shared/dd2ceph
   ```

3. Run the `cephtools dd2ceph` command.

   ```
   # Explore the tool's options
   cephtools dd2ceph
   ```

   ```
   # Run the command
   cephtools dd2ceph -v --bucket $MYGROUP-data-archive --remote ceph --path /projects/standard/$MYGROUP/data_delivery
   ```

4. Review the output and launch the SLURM job.

   Change into the working directory for this run.

   ```
   cd $MYGROUP-data-archive___*
   ```

   Review the slurm script (change any parameters you wish) and launch the data transfer job.

   ```
   sbatch dd2ceph_*.1_copy.slurm
   ```

5. Monitor your SLURM job and review output files.

   Look for (BEGIN, END, FAIL) emails from the slurm scheduler. Follow the progress in the slurm `stderr` and `stdout` files (located within the working directory.
