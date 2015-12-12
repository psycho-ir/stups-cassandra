#!/bin/bash
# Script to process backup and restore functionallity in AWS
# Maintainer: malte.pickhan@zalando.de
backupFolder=$/var/cassandra/data/$keySpaceName/
DATE=`date +%Y-%m-%d:%H:%M:%S`
IP=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)

commando=$1
keySpaceName=$2
bucket=$3

if [ "$commando" == "help" ]; then
	echo "### Cassandra Snapshotter"
	echo "commando: backup [keySpaceName] [bucket] -- Creates a snapshot of the Cassandra Custer and the given keySpaceName and moves it to the S3 bucket"
	exit 0;
fi

if [ -z "$commando" ]; then
	echo "Missing argument [commando]"
	exit 0;
fi

if [ -z "$bucket" ]; then
	echo "Missing argument [bucket]"
	exit 0;
fi

if [ -z "$keySpaceName" ]; then
	echo "Missing argument [keySpaceName]"
	exit 0;
fi

if [ "$commando" != "backup" ] && [ "$commando" != "help" ]; then
	echo "Wrong usage of argument [commando] --> help"
	exit 0;
fi 

if [ "$commando" == "backup" ]; then
        echo "Creating snapshot for keyspace $keySpaceName"
        /opt/cassandra/bin/nodetool snapshot
        echo "Moving file to S3 Bucket $bucket"
        aws s3 cp /var/cassandra/data/$keySpaceName s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP --recursive
        echo "Cleanup"
        `rm -f $backupFolder/snapshot/*`
        echo "Done with snapshot"
else
		echo "Quit Script"
		exit 0;
fi
