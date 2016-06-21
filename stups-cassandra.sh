#!/bin/bash
# CLUSTER_NAME
# DATA_DIR
# COMMIT_LOG_DIR
# LISTEN_ADDRESS

# for the nodetool
#nodetool status | tail -n +6 | tee | awk '{print $1$2;}'
set -x

export CASSANDRA_INCLUDE=${CASSANDRA_HOME}/bin/cassandra.in.sh

# sed -i '' 's/^dc_suffix=.*/dc_suffix=DC666/' cassandra-rackdc_template.properties # use this line when executing on a Mac!
sed -i 's/^dc_suffix=.*/dc_suffix=${DCSUFFIX}/' /opt/cassandra/conf/cassandra-rackdc_template.properties

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
        SEED_COUNT_IN_VDC=$(curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds" | jq '.node.nodes '| grep -c ${DCSUFFIX})
	# registering new node as seed: if seeds still needed and NOT a replacement node
        if [ $SEED_COUNT_IN_VDC -lt $NEEDED_SEEDS ];
        then
           if [ -z "$DEAD_NODE_ADDRESS" ] ;
	        then
               echo "Registering this node as the seed for zone ${NODE_ZONE} with TTL ${TTL}..."
               curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds/${NODE_HOSTNAME}"  -XPUT -d value="{\"host\":\"${LISTEN_ADDRESS}\",\"availabilityZone\":\"${NODE_ZONE}\",\"dcSuffix\":\"${DCSUFFIX}\"}" -d ttl=${TTL} > /dev/null
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

echo "Generating configuration from template ..."
python -c "import os; print os.path.expandvars(open('/opt/cassandra/conf/cassandra_template.yaml').read())" > /opt/cassandra/conf/cassandra.yaml
python -c "import os; print os.path.expandvars(open('/opt/cassandra/conf/cassandra-rackdc_template.properties').read())" > /opt/cassandra/conf/cassandra-rackdc.properties
#python -c "import pystache, os; print(pystache.render(open('/opt/cassandra/conf/cassandra_template.yaml').read(), dict(os.environ)))" > /opt/cassandra/conf/cassandra.yaml


echo "Starting Cassandra ..."
/opt/cassandra/bin/cassandra \
    -R \
    -Dcassandra.logdir=/var/cassandra/log \
    -Dcassandra.cluster_name=${CLUSTER_NAME} \
    -Dcassandra.listen_address=${LISTEN_ADDRESS} \
    -Dcassandra.broadcast_rpc_address=${LISTEN_ADDRESS} \
    -Djava.rmi.server.hostname=${LISTEN_ADDRESS} \
    ${REPLACE_ADDRESS_PARAM}

if [ "$RECOVERY" -eq 1 ] ;
then
	/opt/cassandra/bin/recovery.sh
fi
