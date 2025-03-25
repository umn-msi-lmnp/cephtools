# Steps To Set Up Data Backup Pipeline

This is a guide for PIs (and those who sudo as a PI) to show them how to set up automatic backup of files in data_delivery to disaster_recovery and Tier2/ceph. 

## Step 1: create a bucket

Run ```cephtools bucketpolicy``` 

This only needs to happen once. The defaut bucket name format is: ```data-delivery-PI_USER_ID``` and the default bucket policy is ```GROUP_READ_WRITE```


## Step 2: Data delivery to disaster recovery

Run ```cephtools dd2dr```. This can be automated using scron. This function copies all data from shared/data_delivery (where it will be deleted after 1 year) to shared/disaster_recovery. 


## Step 3: Data delivery to Ceph/Tier2

Run ```cephtools dd2ceph```. This can be automated using scron. This function copies all data from shared/data_delivery (where it will be deleted after 1 year) to Tier2. This will only copy data from data_delivery, no other locations. 


## Step 4: Keep a list of files that have been backed up. 

Run ```cephtools filesinbackup```. This can be automated using scron. This function generates a list of files in disaster_recovery and a list of files on Tier2 in the data-delivery-PI_USER_ID bucket. 

