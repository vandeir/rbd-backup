# rbd-backup
This script was made based on the script avaliable in this
URL: https://www.rapide.nl/blog/item/ceph_-_rbd_replication.html

It is used to create snapshots of Ceph RBD images e then export those snaps
to be imported in images on another Ceph cluster.

The diference in this script relies on its hability to keep just
a defined number of snapshots, removing older ones.

Its necessary to change only those variables:

SOURCEPOOL: name of source pool containing the images to be backup
DESTPOOL: name of destination pool where to put the images
DESTHOST: in format username@DestinationHost, needs a username and hostname
to connect thought ssh and do the rbd imports. This user 
needs privileges on destination pool where backup images will be stored
and can connect throught ssh using no password.
IMAGES: file containing rbd images names to backup, one per line.
