#!/bin/bash
# Script to process backup and restore functionallity in AWS
# Maintainer: malte.pickhan@zalando.de
DATE=`date +%Y-%m-%d:%H`
IP=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)

set -x

commando=$1
keySpaceName=$2
bucket=$3
snapshot_dir=$4
backupFolder=/var/cassandra/data/$keySpaceName

if [ -z "$LISTEN_ADDRESS" ] ;
then
    export LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
fi

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

	region=`aws s3api get-bucket-location --bucket $bucket | jq -r '.LocationConstraint'`
  echo "Describe keyspace $keySpaceName"
  mkdir -p /opt/recovery/meta/
  $CASSANDRA_HOME/bin/cqlsh $IP -e "DESC $keySpaceName" > /opt/recovery/meta/$keySpaceName-$DATE.cql
	aws s3 --region $region cp /opt/recovery/meta/$keySpaceName-$DATE.cql s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP/$keySpaceName.cql
 	rm -rfv /opt/recovery/meta/$keySpaceName-$DATE.cql

  echo "Moving file to S3 Bucket $bucket"
  for table_dir in `ls -d $backupFolder/* | grep -v feedbacks | grep -v indirectcontextitems` ;
  do
      table_name=`echo $table_dir | grep -o "[^\/]*$"`
      aws s3 --region $region cp $table_dir/snapshots/$snaphshot_dir s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP/$keySpaceName/$table_name --recursive
  done


  echo "Done with snapshot"
else
	echo "Quit Script"
	exit 0;
fi
