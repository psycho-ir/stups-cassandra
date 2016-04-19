#!/bin/bash
# Script to process backup and restore functionallity in AWS
# Maintainer: malte.pickhan@zalando.de
DATE=`date +%Y-%m-%d:%H`
IP=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)

commando=$1
keySpaceName=$2
bucket=$3
backupFolder=/var/cassandra/data/$keySpaceName/*

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

        echo "Describe keyspace $keySpaceName"
        mkdir -p /opt/recovery/meta/
        $CASSANDRA_HOME/bin/cqlsh $IP -e "DESC $keySpaceName" > /opt/recovery/meta/$keySpaceName-$DATE.cql
		aws s3 cp /opt/recovery/meta/$keySpaceName-$DATE.cql s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP/$keySpaceName.cql
       	rm -rfv /opt/recovery/meta/$keySpaceName-$DATE.cql

		echo "Get tokens"
        mkdir -p /opt/recovery/meta
        $CASSANDRA_HOME/bin/nodetool -h $LISTEN_ADDRESS ring | grep $IP | awk '{print $NF ","}' | xargs > /opt/recovery/meta/tokens-$DATE.list
        aws s3 cp /opt/recovery/meta/tokens-$DATE.list s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP/tokens.list
        rm -rfv /opt/recovery/meta/tokens-$DATE.list

        echo "Creating snapshot for keyspace $keySpaceName"
        $CASSANDRA_HOME/bin/nodetool  -h $LISTEN_ADDRESS flush
        $CASSANDRA_HOME/bin/nodetool  -h $LISTEN_ADDRESS snapshot

        echo "Moving file to S3 Bucket $bucket"
 		aws s3 cp /var/cassandra/data/$keySpaceName s3://$bucket/$APPLICATION_ID-snapshot/$DATE/$IP/$keySpaceName --recursive

        echo "Cleanup"
 		rm -rfv $backupFolder/snapshots/*
        echo "Done with snapshot"
else
		echo "Quit Script"
		exit 0;
fi
