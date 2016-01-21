#!/bin/bash
# Script to process backup and restore functionallity in AWS
# Maintainer: malte.pickhan@zalando.de

while [ -n "$BACKUP_BUCKET" ] ; do
                #Get pattern from etcd and split into array
                EXECUTE_PATTERN=($(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/snapshot_pattern | jq -r '.node.value'))
                MINUTE=$(date +%M)
                LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
                HOUR=$(date +%H)
                KEYSPACES=($(/opt/cassandra/bin/cqlsh $LISTEN_ADDRESS -e "DESCRIBE KEYSPACES;"))
                #Remove cassandra default keyspaces
                KEYSPACES=("${KEYSPACES[@]/system_traces}")
                KEYSPACES=("${KEYSPACES[@]/system}")
                        if  [[ "${EXECUTE_PATTERN[0]}" == "?" || "${EXECUTE_PATTERN[0]}" == "$MINUTE" ]] ; then
                                if [[ "${EXECUTE_PATTERN[1]}" == "?" || "${EXECUTE_PATTERN[1]}" == "$HOUR" ]] ; then
                                #Execute the actual script for taking a snapshot                              
                                for i in "${KEYSPACES[@]}"
                                        do
                                        echo "Executing snapshot"
                                        flock -x -n /var/lock/cassandraSnapshotter.lock /opt/cassandra/bin/cassandra-snapshotter.sh backup $i $BACKUP_BUCKET >> /var/log/snapshot_cron.log
                                        done
                                fi
                        fi
`sleep 1m`
done
