#!/bin/bash

# by Vandeir Eduardo

# This script was made based on the script available on this
# URL: https://www.rapide.nl/blog/item/ceph_-_rbd_replication.html

#Souce pool name
SOURCEPOOL="SourcePoolName"
#Destination pool name
DESTPOOL="DestinationPoolName"
#Destination host where to put backups
DESTHOST="root@CephHostBackup"
#Maximum number of snapshots to keep
MAX_SNAPS=10
#File that contains image names to backup (one per line)
IMAGE_NAMES_FILE="rbd_images_to_backup.txt"

if [[ -e $IMAGE_NAMES_FILE ]]; then
	IMAGES=`cat $IMAGE_NAMES_FILE`
else
	echo "Error: file containing image names to backup does not exist."
	exit 1
fi

#Obs: snapshots will be named following this pattern:
# image_name@YYYY-MM-DD_n_X
# where: YYY-MM-DD is the date when the snapshot was created
#        _n_ is just a string to separe the date and the id number
#        X is the identification number of the snapshot. It will be incremented as
#        snapshots are created

function remove_older_snaps {

	#remove older snaps if number of snaps are bigger than MAX_SNAPS on source pool
	local NUM_SNAPS=`rbd ls -l ${SOURCEPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | wc -l`
	while [ "$NUM_SNAPS" -gt "$MAX_SNAPS" ]; do
		local OLDEST_SRC_SNAP_LINE=`rbd ls -l ${SOURCEPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | awk -F '_n_' 'BEGIN { min=999999999 }; $2 < min { min=$2; line=$0 }; END { print line }'`
		echo "Info: removing snapshot ${SOURCEPOOL}/${OLDEST_SRC_SNAP_LINE} from source pool"
		rbd snap rm ${SOURCEPOOL}/${OLDEST_SRC_SNAP_LINE}
		NUM_SNAPS=`rbd ls -l ${SOURCEPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | wc -l`
	done

	#remove older snaps if number of snaps are bigger than MAX_SNAPS on destination pool
	local COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | wc -l"
	NUM_SNAPS=$($COMMAND)
	while [ "$NUM_SNAPS" -gt "$MAX_SNAPS" ]; do
		COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | awk -F '_n_' 'BEGIN { min=999999999 }; \$2 < min { min=\$2; line=\$0 }; END { print line }'"
		local OLDEST_DST_SNAP_LINE=$($COMMAND)
		echo "Info: removing ${DESTPOOL}/${OLDEST_DST_SNAP_LINE} from destination pool"
		COMMAND="ssh -c blowfish ${DESTHOST} rbd snap rm ${DESTPOOL}/${OLDEST_DST_SNAP_LINE}"
		$($COMMAND)
		COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | wc -l"
		NUM_SNAPS=$($COMMAND)
	done
}

#what is today's date?
TODAY=`date +"%Y-%m-%d"`

for IMAGE_NAME in ${IMAGES}; do

	#check whether remote host/pool has image
	if [[ -z $(ssh -c blowfish ${DESTHOST} rbd ls ${DESTPOOL} | egrep ^${IMAGE_NAME}$) ]]; then
		echo "Info: image ${DESTHOST}/${IMAGE_NAME} does not exist in destination pool. Creating a new one."
		COMMAND="ssh -c blowfish ${DESTHOST} rbd create ${DESTPOOL}/${IMAGE_NAME} -s 1"
		RESULT=$($COMMAND 2>&1)
		if [[ -n $RESULT ]]; then
			echo "Error: executing ${COMMAND}. Output: ${RESULT}."
			exit 1
		fi
	fi

	#initialize variable that keep date of last snapshot on source pool
	LAST_SRC_SNAP_DATE=`date +"%Y-%m-%d"`
	if [[ -z $(rbd ls -l ${SOURCEPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$) ]]; then
		#if true, there is no snapshots created
		LAST_SRC_SNAP_NUM=0
	else
		#if false, get line of last snapshot created
		LAST_SRC_SNAP_LINE=`rbd ls -l ${SOURCEPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | awk -F '_n_' 'BEGIN { max=0 }; $2 > max { max=$2; line=$0 }; END { print line }'`
		#get date of last snapshot
		LAST_SRC_SNAP_DATE=`echo ${LAST_SRC_SNAP_LINE} | sed 's/^\(.*\)@\(.*\)_n_\(.*\)$/\2/g'`
		#get number id of last snapshot
		LAST_SRC_SNAP_NUM=`echo ${LAST_SRC_SNAP_LINE} | sed 's/^\(.*\)@\(.*\)_n_\(.*\)$/\3/g'`
	fi
	#number id of next snapshot
	NXT_SRC_SNAP_NUM=$(($LAST_SRC_SNAP_NUM + 1))

	#initialize variable that stores date of last snapshot on destination pool
	LAST_DST_SNAP_DATE=`date +"%Y-%m-%d"`
	#command to execute remotelly
	COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1  |egrep ^${IMAGE_NAME}@.*_n_[0-9]*$"
	#same logic to get date and number id of last snapshot on destination pool
	if [[ -z $($COMMAND) ]]; then
		LAST_DST_SNAP_NUM=0
	else
		COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@.*_n_[0-9]*$ | awk -F '_n_' 'BEGIN { max=0 }; \$2 > max { max=\$2; line=\$0 }; END { print line }'"
		LAST_DST_SNAP_LINE=$($COMMAND)
		LAST_DST_SNAP_DATE=`echo ${LAST_DST_SNAP_LINE} | sed 's/^\(.*\)@\(.*\)_n_\(.*\)$/\2/g'`
		LAST_DST_SNAP_NUM=`echo ${LAST_DST_SNAP_LINE} | sed 's/^\(.*\)@\(.*\)_n_\(.*\)$/\3/g'`
	fi
	NXT_DST_SNAP_NUM=$(($LAST_DST_SNAP_NUM + 1))

	echo "Info: creating source snapshot ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM}"
	#create snapshot on source pool
	rbd snap create ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM}

	# check whether to do a init or a full
	if [[ -z $(ssh -c blowfish ${DESTHOST} rbd snap ls ${DESTPOOL}/${IMAGE_NAME}) ]]; then
		echo "Info: no snapshots found for $DESTPOOL/$IMAGE_NAME on destination pool. Doing init."
		#rbd export-diff also creates a snapshot on destionation pool automatically
		rbd export-diff ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM} - | ssh -c blowfish ${DESTHOST} rbd import-diff - ${DESTPOOL}/${IMAGE_NAME}
	else
		#check last snapshot exists at remote pool
		COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@${LAST_DST_SNAP_DATE}_n_${LAST_DST_SNAP_NUM}$"
		if [[ -z $(${COMMAND}) ]]; then
				echo "Error: --from-snap ${IMAGE_NAME}@${LAST_DST_SNAP_DATE}_n_${LAST_DST_SNAP_NUM} does not exist on remote pool."
				exit 1
		fi

		#check next snapshot already exists at remote pool
		COMMAND="ssh -c blowfish ${DESTHOST} rbd ls -l ${DESTPOOL} | cut -d' ' -f1 | egrep ^${IMAGE_NAME}@${TODAY}_n_${NXT_DST_SNAP_NUM}"
		if [[ -z $(${COMMAND}) ]]; then
			echo "Info: Doing export-diff between snaps ${SOURCEPOOL}/${IMAGE_NAME}@${LAST_SRC_SNAP_DATE}_n_${LAST_SRC_SNAP_NUM} and ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM}"
			rbd export-diff --from-snap ${LAST_SRC_SNAP_DATE}_n_${LAST_SRC_SNAP_NUM} ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM} - | ssh -c blowfish ${DESTHOST} rbd import-diff - ${DESTPOOL}/${IMAGE_NAME}

			#comparing changed extents between source and destination
			SOURCE_HASH=`rbd diff --from-snap ${LAST_SRC_SNAP_DATE}_n_${LAST_SRC_SNAP_NUM} ${SOURCEPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_SRC_SNAP_NUM} --format json | md5sum | cut -d ' ' -f 1`
			COMMAND="ssh -c blowfish ${DESTHOST} rbd diff --from-snap ${LAST_DST_SNAP_DATE}_n_${LAST_DST_SNAP_NUM} ${DESTPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_DST_SNAP_NUM} --format json | md5sum | cut -d ' ' -f 1"
			DEST_HASH=$($COMMAND)
			if [ $SOURCE_HASH == $DEST_HASH ]; then
				echo "Info: changed extents hash check ok."
			else
				echo "Error: changed extents hash on source and destination don't match: ${SOURCE_HASH} not equals ${DEST_HASH}."
			fi
		else
			echo "Error: snapshot ${DESTPOOL}/${IMAGE_NAME}@${TODAY}_n_${NXT_DST_SNAP_NUM} already exists, skipping"
			exit 1
		fi
	fi

	#call function to remove older snapshots
	remove_older_snaps

done
