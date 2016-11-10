#!/bin/bash
# Script to repair cassandra cluster. Shall run on each node, because -pr is used

set -x

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
                    /opt/cassandra/bin/nodetool repair -pr
                    out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/repairLock?prevValue=${LISTEN_ADDRESS} -XDELETE)
                    echo "$out"
                    break
                else
                    echo "Failed to acquire repair lock. Waiting for 60 seconds ..."
                    sleep 10s
                fi
            done

        fi
    fi
    sleep 45m
done
