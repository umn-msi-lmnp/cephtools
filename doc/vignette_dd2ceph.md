# Cephtools: Transferring `data_delivery` to ceph

## Introduction

Data from various UMN core facilities (e.g. UMGC) export data to a special directory called `data_delivery` for short period of time (~ 1 year). This vignette will describe how to data deposited in `data_delivery` can be easily copied to MSI ceph (tier2) for long term strorage.

## Step 1: Create bucket and set a policy _(completed once, preferably by the MSI group PI)_

Create a bucket that all MSI group members can access.

_The MSI group PI_ (or via sudo) should create a new bucket on ceph, called `data-delivery-GROUP` (replacing GROUP with your MSI group name). Later, a bucket policy can be applied to the bucket, controlling access to the bucket for only certain MSI users. This process will ensure the raw data in the bucket are owned by the group's PI username. This bucket only needs to be created once.

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
   s3cmd mb s3://data-delivery-$MYGROUP
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
   cephtools bucketpolicy -v -b data-delivery-$MYGROUP -p GROUP_READ_WRITE -g $MYGROUP
   ```

## Step 2: Transfer data to ceph _(completed my any group member, repeatedly)_

After the PI's bucket has a group READ/WRITE bucket policy set, _the following methods can be done by any group members_. In fact, the data transfer steps below should be done repeatedly (i.e. after any new datasets are added to `data_delivery` directory). NOTE: the --remote option is optional as cephtools will automatically detect your MSI ceph credentials.

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
   # Run the command (bucket is automatically set to data-delivery-$MYGROUP)
   cephtools dd2ceph -v --group $MYGROUP
   ```

4. Review the output and launch the SLURM job.

   Change into the working directory for this run.

   ```
   cd data-delivery-$MYGROUP___*
   ```

    Review the slurm script (change any parameters you wish) and launch the combined copy and verify job.

    ```
    sbatch dd2ceph_*.1_copy_and_verify.slurm
    ```

5. Monitor your SLURM job and review output files.

   Look for (BEGIN, END, FAIL) emails from the slurm scheduler. Follow the progress in the slurm `stderr` and `stdout` files (located within the working directory). The combined script will:
   
   - Copy all data to ceph (tier2) storage
   - Verify the transfer using rclone check
   - Generate file lists for comparison
   - Log all operations for review
   
   Review the verification log (`dd2ceph_*.1_verify.rclone.log`) to ensure all files were transferred successfully without errors.
