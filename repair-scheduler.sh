#!/bin/bash
# Script to repair cassandra cluster. Shall run on each node, because -pr is used

set -x

LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)

while true; do
    HOUR=$(date +%H)
    DAY=`date +%d`
    DAY_EXPR=`expr $DAY + 0`
    # RUN repair every 2nd day once at night
    if  [ $(($DAY_EXPR % 2)) == 0 ] ; then
        if  [ "03" == "$HOUR" ] ; then
            while true; do
                curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/repairLock?prevExist=false" \
                    -XPUT -d value=${LISTEN_ADDRESS} > /dev/null
                if [ $? -eq 0 ] ;
                then
                    /opt/cassandra/bin/nodetool repair -pr -seq
                    out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/repairLock?prevValue=${LISTEN_ADDRESS} -XDELETE)
                    echo "$out"
                    break
                else
                    echo "Failed to acquire repair lock. Waiting for 5 minutes ..."
                    sleep 5m
                fi
            done
            sleep 36h
        fi
    fi
    sleep 45m
done
