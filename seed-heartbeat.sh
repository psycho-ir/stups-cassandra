#!/bin/bash
# Script to refresh the ttl for seeds, or add current node as seed if seeds are missing
# Maintainer: sorin.stirbu@zalando.de
# ETCD_URL
# CLUSTER_NAME
# CLUSTER_SIZE

# for the nodetool
export CASSANDRA_HOME=/opt/cassandra
export CASSANDRA_INCLUDE=${CASSANDRA_HOME}/bin/cassandra.in.sh

if [ -z "$LISTEN_ADDRESS" ] ;
then
    export LISTEN_ADDRESS=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
fi

EC2_META_URL=http://169.254.169.254/latest/meta-data
NODE_HOSTNAME=$(curl -s ${EC2_META_URL}/local-hostname)
NODE_ZONE=$(curl -s ${EC2_META_URL}/placement/availability-zone)

NEEDED_SEEDS=$((CLUSTER_SIZE >= 3 ? 3 : 1))

SLEEP=10
TTL=30


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



# endless loop
while true ; do

	# check if node is registerd as seed
       SEED_ADDR=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds/${NODE_HOSTNAME} | grep -v 'errorCode":100')

       # refresh TTL if seed
       if [ -n "$SEED_ADDR" ] ;
       then
               curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds/${NODE_HOSTNAME}" \
                   -XPUT -d ttl=${TTL} -d value="{\"host\":\"${LISTEN_ADDRESS}\",\"availabilityZone\":\"${NODE_ZONE}\",\"dcSuffix\":\"${DCSUFFIX}\"}" > /dev/null
       fi

       # check if missing seeds 
       if [ -z "$SEED_ADDR" ] ;
       then
           SEED_COUNT_IN_VDC=$(curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds" | jq -r '.node.nodes '| grep -c ${DCSUFFIX})
           if [ $SEED_COUNT_IN_VDC -lt $NEEDED_SEEDS ];
           then
                  #check if no seed in availability zone and DC!
                  SEED_FOR_ZONE=$(curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds" | jq -r '.node.nodes '| grep -cE ${NODE_ZONE}.*${DCSUFFIX})
                  if [ "$SEED_FOR_ZONE" -eq 0 ]
		              then
                         # check if node in UN state (and can become seed)
                         NODE_IP=`hostname | sed  's/ip-//' | sed 's/-/./g'`
                         IS_NODE_NORMAL=''
                         IS_NODE_NORMAL=`nodetool -h $LISTEN_ADDRESS status | grep '^UN' | grep ${NODE_IP}`

                         # REGISTER AS SEED FOR ZONE
                         if [ -n "$IS_NODE_NORMAL" ]
                         then
                                 curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds/${NODE_HOSTNAME}" \
                                      -XPUT -d value="{\"host\":\"${LISTEN_ADDRESS}\",\"availabilityZone\":\"${NODE_ZONE}\",\"dcSuffix\":\"${DCSUFFIX}\"}" -d ttl=${TTL} > /dev/null
                         fi
                  fi
           fi
       fi


       `sleep ${SLEEP}`
done

