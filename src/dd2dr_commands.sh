#!/bin/env bash

# This script will use rsync to copy files from 
# data delivery (dd) to disaster recovery (dr) on a recurring basis

# ---------------------------------------------------------------------
# set variables
# ---------------------------------------------------------------------
GROUP="$1"
DATESTAMP="$2"

# ---------------------------------------------------------------------
# Print some info
# ---------------------------------------------------------------------
echo "$GROUP sync starting..."
echo "${DATESTAMP}"
#exit 6
umask u=rwx,g=rx,o=

# ---------------------------------------------------------------------
# Check for any space issues
# ---------------------------------------------------------------------

# should I rely on groupquota or are there other lower level system tools that I could use...
groupquota -g $GROUP -p -U 'G' -c
AVAIL=$( groupquota -g $GROUP -p -U '' -cH | awk 'BEGIN { FS=",";OFS=","} {print $3-$2}' )
AVAILH=$( groupquota -g $GROUP -p -U 'G' -cH | sed 's/G//g' | awk 'BEGIN { FS=",";OFS=","} {print $3-$2}' )

echo "${AVAILH}G remaining in /home/${GROUP} total quota"

# ---------------------------------------------------------------------
# Check data_delivery
# ---------------------------------------------------------------------

DDTOTAL=$(du -Lhc /home/$GROUP/data_delivery | tail -1 | cut -f1)
echo "$DDTOTAL in /home/$GROUP/data_delivery"
### must use -b to get bytes that are comparable to $AVAIL from groupquota
DDBYTES=$(du -Lbc /home/$GROUP/data_delivery |tail -1 | cut -f1)
echo "$DDBYTES bytes in data_delivery"

# ---------------------------------------------------------------------
# Total size of files that will be transfered
# ---------------------------------------------------------------------

DDBYTES_TRANSFER=$(rsync -Lvru --dry-run --stats /home/$GROUP/data_delivery /home/$GROUP/shared/disaster_recovery/ | grep "Total transferred file size:" | tr " " "\t" | cut -f 5 | sed 's/\,//g')
echo "$DDBYTES_TRANSFER bytes to be transferred"

# ---------------------------------------------------------------------
# Transfer the files
# ---------------------------------------------------------------------

if [ "$DDBYTES_TRANSFER" -lt "$AVAIL" ]; then
    echo "$DDBYTES_TRANSFER < $AVAIL, syncing data_delivery to disaster_recovery"
    #echo "$DDBYTES < $AVAIL, syncing data_delivery to disaster_recovery"
    # -L is critical to copy links as files...
    rsync -Lvru /home/$GROUP/data_delivery /home/$GROUP/shared/disaster_recovery/
    # add a check here to make sure the rsync finished successfully.
    if [ "$?" -eq 0 ]; then
       echo "rsync finished successfully!"
    else
       echo "rsync did not finish successfully"
       exit 5
    fi
    
    AVAILHNEW=$( groupquota -g $GROUP -U 'G' -cH | sed 's/G//g' | awk 'BEGIN { FS=",";OFS=","} {print $3-$2}' )
    echo "Previous space available was ${AVAILH}"
    echo "New space available is ${AVAILHNEW}"
    echo "Sync complete"
else
    echo "$DDBYTES > $AVAIL Not enough space for syncing!"
    echo "Checking disaster_recovery data_delivery size..."
    DDDRBYTES=$(du -Lbc /home/$GROUP/data_delivery |tail -1 | cut -f1)
    echo "$DDDRBYTES in disaster_recovery data_delivery"
    if [ "$DDBYTES" -eq "$DDDRBYTES" ]; then
	echo "$DDBYTES (dd size) equal to $DDDRBYTES (dddr size)"
	echo "Nothing needs to transfer, but space is not available"
    else
	# need to update here to deal with the scenario where dd data has rolled off the system
	# dd could be smaller than dddr but data needs to sync
	# can dd be larger than dddr - possibly, but under what conditions?
    	# maybe the best thing to do is check to see if the most recent data transferred successfully
      	NEW=$(du -Lbc /home/$GROUP/shared/disaster_recovery/data_delivery |tail -4 | head -1)
      	QUARTER=$(echo $NEW | cut -d '/' -f 8)
      	NEWSIZE=$(du -Lbc /home/$GROUP/shared/disaster_recovery/data_delivery |tail -4 | head -1 | cut -f1)
      	MATCHSIZE=$(du -Lbc /home/$GROUP/data_delivery/*/$QUARTER | tail -1 | cut -f1 ) 
     if [ "$NEWSIZE" -eq "$MATCHSIZE" ]; then
	 echo "Most recent data has been synced, warning that space is not available to sync, exit code 10"
	 exit 10
     else
	echo "Newest data has not been synced and space is not available, exiting with code 20"
	exit 20
     fi 
    fi

fi



