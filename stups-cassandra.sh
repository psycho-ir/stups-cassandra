#!/bin/bash
# CLUSTER_NAME
# DATA_DIR
# COMMIT_LOG_DIR
# LISTEN_ADDRESS

# for the nodetool
#nodetool status | tail -n +6 | tee | awk '{print $1$2;}'
set -x

export CASSANDRA_HOME=/opt/cassandra
export CASSANDRA_INCLUDE=${CASSANDRA_HOME}/bin/cassandra.in.sh

sed -i '' 's/^dc_suffix=.*/dc_suffix=${DCSUFFIX}/' /opt/cassandra/conf/cassandra-rackdc_template.properties

EC2_META_URL=http://169.254.169.254/latest/meta-data

NODE_HOSTNAME=$(curl -s ${EC2_META_URL}/local-hostname)
NODE_ZONE=$(curl -s ${EC2_META_URL}/placement/availability-zone)
#-Dcassandra.consistent.rangemovement=false

#check if we are likely a replacement node
REPLACE_ADDRESS_PARAM=''
temp=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq -r '.node.nodes[0].value')
if [ $temp != "null" ] ;
then
    ONE_OF_SEED_NODES=${temp//\\}
    SEED_HOST=$(echo $ONE_OF_SEED_NODES | jq -r '.host' )
    if nodetool -h $SEED_HOST status | grep '^D. \|^\?. ' | head -n 1 >/tmp/nodetool-remote-status ;
    then
         DEAD_NODE_ADDRESS=$(grep '^D. ' </tmp/nodetool-remote-status | awk '{print $2; exit}')
        if [ -n "$DEAD_NODE_ADDRESS" ] ;
        then
          echo "There was a dead node at ${DEAD_NODE_ADDRESS}, will try to replace it ..."
          REPLACE_ADDRESS_PARAM=-Dcassandra.replace_address=${DEAD_NODE_ADDRESS}
        fi
    fi

fi

# http://docs.datastax.com/en/cassandra/2.0/cassandra/architecture/architectureGossipAbout_c.html
# "...it is recommended to use a small seed list (approximately three nodes per data center)."
NEEDED_SEEDS=$((CLUSTER_SIZE >= 3 ? 3 : 1))
TTL=${TTL:-30}
TTL_REC=$(($TTL*2))

if [ -z "$ETCD_URL" ] ;
then
    echo "etcd URL is not defined."
    exit 1
fi
echo "Using $ETCD_URL to access etcd ..."

if [ -z "$CLUSTER_NAME" ] ;
then
    echo "Cluster name is not defined."
    exit 1
fi

# TODO: use public-ipv4 if multi-region
if [ -z "$LISTEN_ADDRESS" ] ;
then
    export LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
fi

echo "Node IP address is $LISTEN_ADDRESS ..."

# TODO: Use diff. Snitch if Multi-Region
if [ -z $SNITCH ] ;
then
    export SNITCH="Ec2Snitch"
fi

if [ -z "$OPSCENTER" ] ;
then
    export OPSCENTER=$(curl -Ls -m 4 ${ETCD_URL}/v2/keys/cassandra/opscenter | jq -r '.node.value')
fi

export DATA_DIR=${DATA_DIR:-/var/cassandra/data}
export COMMIT_LOG_DIR=${COMMIT_LOG_DIR:-/var/cassandra/data/commit_logs}

curl -s "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/size?prevExist=false" \
    -XPUT -d value=${CLUSTER_SIZE} > /dev/null

if [ -n "$BACKUP_BUCKET" ] ;
then
    curl -s "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/snapshot_pattern/" \
      -XPUT -d value='05 ?' > /dev/null
fi

while true; do
    curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/_bootstrap?prevExist=false" -XPUT -d value=${LISTEN_ADDRESS} -d ttl=${TTL} > /dev/null
    if [ $? -eq 0 ] ;
    then
        echo "Acquired bootstrap lock. Setting up node ..."
        # SEED_COUNT=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq '.node.nodes | length')
        SEED_COUNT_IN_VDC=$(curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds" | jq '. node.nodes '| grep -c ${DCSUFFIX})
	# registering new node as seed: if seeds still needed and NOT a replacement node
        if [ $SEED_COUNT_IN_VDC -lt $NEEDED_SEEDS ];
        then
           if [ -z "$DEAD_NODE_ADDRESS" ] ;
	        then
               echo "Registering this node as the seed for zone ${NODE_ZONE} with TTL ${TTL}..."
               curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds/${NODE_HOSTNAME}"  -XPUT -d value="{\"host\":\"${LISTEN_ADDRESS}\",\"availabilityZone\":\"${NODE_ZONE}\",\"dcSuffix\":\"${DCSUFFIX}\"}" -d ttl=${TTL} > /dev/null
           fi
	    fi

        # Register the cluster with OpsCenter if there's already at least 1 seed node
        if [ -n $OPSCENTER -a $SEED_COUNT_IN_VDC -gt 0 ] ;
        then
            curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/opscenter_ip?prevExist=false" \
                -XPUT -d value=${OPSCENTER} > /dev/null
            if [ $? -eq 0 ] ;
            then
                # First seed node is fine, it should allow opscenter to discover the rest
                SEED=$(curl -sL ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | \
                    jq -r '.node.nodes[0].value')
                echo "Registering cluster with OpsCenter $OPSCENTER using seed $SEED ..."
                PAYLOAD="{\"cassandra\":{\"seed_hosts\":\"$SEED\"},\"cassandra_metrics\":{},\"jmx\":{\"port\":\"7199\"}}"
                curl -ksL http://${OPSCENTER}:8888/cluster-configs -X POST -d $PAYLOAD > /dev/null
            fi
        fi

        break
    else
        echo "Failed to acquire boostrap lock. Waiting for 5 seconds ..."
        sleep 5
    fi
done

echo "Finished bootstrapping node."
# Add route 53record seed1.${CLUSTER_NAME}.domain.tld ?

if [ -n "$OPSCENTER" ] ;
then
    echo "Configuring OpsCenter agent ..."
    echo "stomp_interface: $OPSCENTER" >> /var/lib/datastax-agent/conf/address.yaml
    echo "hosts: [\"$LISTEN_ADDRESS\"]" >> /var/lib/datastax-agent/conf/address.yaml
    echo "cassandra_conf: /opt/cassandra/conf/cassandra.yaml" >> /var/lib/datastax-agent/conf/address.yaml
    echo "Starting OpsCenter agent in the background ..."
    service datastax-agent start > /dev/null
fi

echo "Generating configuration from template ..."
python -c "import os; print os.path.expandvars(open('/opt/cassandra/conf/cassandra_template.yaml').read())" > /opt/cassandra/conf/cassandra.yaml
python -c "import os; print os.path.expandvars(open('/opt/cassandra/conf/cassandra-rackdc_template.properties').read())" > /opt/cassandra/conf/cassandra-rackdc.properties
#python -c "import pystache, os; print(pystache.render(open('/opt/cassandra/conf/cassandra_template.yaml').read(), dict(os.environ)))" > /opt/cassandra/conf/cassandra.yaml

if [ "$RECOVERY" -eq 0 ] ;
then

echo "Starting Cassandra ..."
/opt/cassandra/bin/cassandra -f \
    -Dcassandra.logdir=/var/cassandra/log \
    -Dcassandra.cluster_name=${CLUSTER_NAME} \
    -Dcassandra.listen_address=${LISTEN_ADDRESS} \
    -Dcassandra.broadcast_rpc_address=${LISTEN_ADDRESS} \
    -Djava.rmi.server.hostname=${LISTEN_ADDRESS} \
    ${REPLACE_ADDRESS_PARAM}

else
    TTL=$TTL_REC
    # This loop assigns order number for each node (to distribute snapshots afterwards)
    while true; do
        curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryLock?prevExist=false" \
            -XPUT -d value=${LISTEN_ADDRESS} -d ttl=${TTL} > /dev/null
        if [ $? -eq 0 ] ;
        then
            prev_order=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryOrder | jq -r '.node.value')
            if [ "$prev_order" = "null" ] ;
            then
                my_order=1
                out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryOrder?prevExist=false \
                    -XPUT -d value=1 -d ttl=${TTL})
                echo "$out"

            else
                my_order=$((prev_order+1))
                out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryOrder?prevValue=$prev_order \
                    -XPUT -d value=$my_order -d ttl=${TTL} | jq -r '.errorCode')
                if [ "$out" != "null" ] ;
                then
                    echo "ERROR!"
                    echo "$out"
                fi
            fi
            out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryLock?prevValue=${LISTEN_ADDRESS} \
                -XDELETE)
            echo "$out"

            break
        else
            echo "Failed to acquire recovery lock. Waiting for 10 seconds ..."
            sleep 10
        fi
    done


    echo "Starting Cassandra ..."
    /opt/cassandra/bin/cassandra \
        -Dcassandra.logdir=/var/cassandra/log \
        -Dcassandra.cluster_name=${CLUSTER_NAME} \
        -Dcassandra.listen_address=${LISTEN_ADDRESS} \
        -Dcassandra.broadcast_rpc_address=${LISTEN_ADDRESS} \
        ${REPLACE_ADDRESS_PARAM}

    S3_DIR=/opt/recovery/s3
    mkdir -p $S3_DIR
    aws s3 cp "s3://cassandra-release-backup/cassandra-snapshot/$recovery_snapshot" $S3_DIR --recursive

    snapshot_count=`ls $S3_DIR | wc -l`

    if [ $my_order -gt $snapshot_count ]; then
        #if number of nodes is greater than number of snapshots
        #try to recover from snapshot which is already used by another node.
        #otherwise data distribution may become not balanced
        my_order=$(($my_order-$snapshot_count))
    fi

    node_folder=`ls $S3_DIR | sed -n ${my_order}p`
    node_folder="$S3_DIR/$node_folder"

    for cql_file in `ls $node_folder/*.cql`;
    do
        cout=`cqlsh $LISTEN_ADDRESS -f $cql_file 2>&1`
        exists=`echo $cout | grep already | wc -l`
        # cout=`cqlsh $LISTEN_ADDRESS -f $SCHEMA_DEFINITION`
        result_status=$?
        echo $result_status:$cout
        count=0
        while [ $result_status -ne 0 ]; do
            if [ $exists -ne 0 ]; then
                echo "Already Exists...break"
                break
            fi
            echo "Sleep 10s..."
            sleep 10s
            cout=`cqlsh $LISTEN_ADDRESS -f $cql_file 2>&1`
            result_status=$?
            echo $result_status:$cout
        done
    done
    for snapshot_dir in `ls -d $node_folder/*/*/`;
    do
        cout=`/opt/cassandra/bin/sstableloader -d ${LISTEN_ADDRESS} $snapshot_dir 2>&1`
        result_status=$?
        echo $result_status:$cout
        while [ $result_status -ne 0 ]; do
            echo "Sleep 10s..."
            sleep 10s
            cout=`/opt/cassandra/bin/sstableloader -d ${LISTEN_ADDRESS} $snapshot_dir 2>&1`
            result_status=$?
            echo $result_status:$cout
        done
    done

    /opt/cassandra/bin/nodetool -h $LISTEN_ADDRESS repair
fi
