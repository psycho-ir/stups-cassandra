#!/bin/bash
# Script to process backup and restore functionallity in AWS
# Maintainer: malte.pickhan@zalando.de

set -x 
while [ -n "$BACKUP_BUCKET" ] ; do
                #Get pattern from etcd and split into array
                EXECUTE_PATTERN=($(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/snapshot_pattern | jq -r '.node.value'))
                MINUTE=$(date +%M)
                LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
                HOUR=$(date +%H)
                KEYSPACES=` /opt/cassandra/bin/cqlsh $LISTEN_ADDRESS -e "DESCRIBE KEYSPACES;" | tr ' ' '\n' | grep -v kairosdb | grep -v system | grep -v '^$'`
                echo "$KEYSPACES"               
                for i in `echo $KEYSPACES`
                do
                        if [ $HOUR == "05" ]; then
                #       if  [[ "${EXECUTE_PATTERN[0]}" == "?" || "${EXECUTE_PATTERN[0]}" == "$MINUTE" ]] ; then    
                       #        if [[ "${EXECUTE_PATTERN[1]}" == "?" || "${EXECUTE_PATTERN[1]}" == "$HOUR" ]] ; then
                                        TABLES_FULL=`cqlsh $LISTEN_ADDRESS -e "describe keyspace $i" | grep "CREATE TABLE" | awk '{print $3}' | grep -v feedbacks | grep -v indirectcontextitems | tr '\n' ','`
                                        TABLE_NAMES=`cqlsh $LISTEN_ADDRESS -e "describe keyspace $i" | grep "CREATE TABLE" | awk '{print $3}' | grep -v feedbacks | grep -v indirectcontextitems |  awk -F'.' '{print $2}' | tr '\n' ' '`
                                        echo "nodetool flush $i $TABLE_NAMES"
                                        nodetool flush $i $TABLE_NAMES
                                        echo "snapshot_dir=`nodetool snapshot -kt $TABLES_FULL | tail -1| grep -o \"[0-9]*\"`"
                                        snapshot_dir=`nodetool snapshot -kt $TABLES_FULL | tail -1| grep -o "[0-9]*"`
                                        echo "Executing snapshot"
                                        flock -x -n /var/lock/cassandraSnapshotter.lock /opt/cassandra/bin/cassandra-snapshotter.sh backup $i $BACKUP_BUCKET $snapshot_dir
                                        nodetool clearsnapshot
                #               fi
                        fi
                done
        `sleep 45m`
done
