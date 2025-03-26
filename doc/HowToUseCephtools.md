# Steps To Set Up Data Backup Pipeline

This is a guide for PIs (and those who sudo as a PI) to show them how to set up automatic backup of files in data_delivery to disaster_recovery and Tier2/ceph. 

## Step 1: create a bucket

Run ```cephtools bucketpolicy``` 

This only needs to happen once. The defaut bucket name format is: ```data-delivery-PI_USER_ID``` and the default bucket policy is ```GROUP_READ_WRITE```


## Step 2: Data delivery to disaster recovery

Run ```cephtools dd2dr```. This can be automated using scron. This function copies all data from /home/USER/shared/data_delivery (where it will be deleted after 1 year) to /home/USER/shared/disaster_recovery. 


## Step 3: Data delivery to Ceph/Tier2

Run ```cephtools dd2ceph```. This can be automated using scron. This function copies all data from /home/USER/shared/data_delivery (where it will be deleted after 1 year) to Tier2. This will only copy data from data_delivery, no other locations. 


## Step 4: Keep a list of files that have been backed up. 

Run ```cephtools filesinbackup```. This can be automated using scron. This function generates a list of files in disaster_recovery and a list of files on Tier2 in the data-delivery-PI_USER_ID bucket and will email the user text files of these two lists. 


# Frequently Asked Questions

Why is GROUP_READ_WRITE recommended as a bucket policy? 

  This policy give all members of an MSI group the ability to read and write files to a bucket on Tier 2, which means that others in your group can add files to the group bucket. It is better to have more data organized in one place, so it's easier to keep track of what data are where and what has been backed up. 


What if I want to copy other data (not in data_delivery) to Tier 2? 

  You can use ```panf2ceph```. See [this](https://github.umn.edu/lmnp/cephtools/blob/main/doc/vignette_panfs2ceph.md) vignette for more information. 


How frequently will/should data be automatically backed up? 

  We recommend setting up scron jobs to back up data_delivery to disaster_recovery and Tier 2 every day or at least every week. This will allow analysts to source raw data files from disaster_recovery, making it easier to return to the same project after time has passed. Lists of files in disaster_recovery and on Tier 2 should be compiled every month or at least once a quarter. 


