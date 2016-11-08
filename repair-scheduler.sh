#!/bin/bash
# Script to repair cassandra cluster. Shall run on each node, because -pr is used

set -x

while true; do
    HOUR=$(date +%H)
    set -x
    DAY=`date +%d`
    DAY_EXPR=`expr $DAY + 0`
    # RUN repair every 2nd day once at night
    if  [ $(($DAY_EXPR % 2)) == 0 ] ; then
        if  [ "03" == "$HOUR" ] ; then
            /opt/cassandra/bin/nodetool repair -pr
            `sleep 2d`
        fi
    fi
    `sleep 45m`
done
