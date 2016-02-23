#!/bin/bash

function getSeedCandidate {
   SEED_COUNT=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq '.node.nodes | length')
    if [ $SEED_COUNT -lt $NEEDED_SEEDS ];
    then
        AVAILABLE_NODES_STR=$(nodetool status | tail -n +6 | grep '^U.' | awk '{print $2}' | tr "\n" " ")
        temp=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq -r  '.node.nodes[].value')
        AVAILABLE_SEEDS_STR=$(echo ${temp//\\} | jq -r '.host'| tr "\n" " ")


        read -a AVAILABLE_NODES <<< $AVAILABLE_NODES_STR
        read -a AVAILABLE_SEEDS <<< $AVAILABLE_SEEDS_STR

        echo "Available nodes are: ${AVAILABLE_NODES[@]}"
        echo "Available Seeds are: ${AVAILABLE_SEEDS[@]}"

        NON_SEED_AVAILABLE_NODES=()

        for i in "${AVAILABLE_NODES[@]}"; do
            skip=
            for j in "${AVAILABLE_SEEDS[@]}"; do
                [[ $i == $j ]] && { skip=1; break;}
            done
            [[ -n $skip ]] || NON_SEED_AVAILABLE_NODES+=($i)
        done
        echo "non seeds nodes are: ${NON_SEED_AVAILABLE_NODES[@]}"
        #lock seeds
        #lock choose proper number of nodes and put the in seeds
        if [ ${#NON_SEED_AVAILABLE_NODES[@]} -eq 0 ];
        then
            return ''
        fi
        return ${NON_SEED_AVAILABLE_NODES[0]}
    fi
}

export CASSANDRA_HOME=/opt/cassandra
export CASSANDRA_INCLUDE=${CASSANDRA_HOME}/bin/cassandra.in.sh
TTL=${TTL:-30}
NEEDED_SEEDS=$((CLUSTER_SIZE >= 3 ? 3 : 1))


curl -Lsf "${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/_seed-keeper?prevExist=false" -XPUT -d value=${LISTEN_ADDRESS} -d ttl=${TTL} > /dev/null
if [ $? -eq 0 ] ;
then
    echo "Acquired seed-keeper lock. Refreshing nodes ..."
    SEED_COUNT=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq '.node.nodes | length')
    if [ $SEED_COUNT -lt $NEEDED_SEEDS ];
    then
        AVAILABLE_NODES_STR=$(nodetool status | tail -n +6 | grep '^U.' | awk '{print $2}' | tr "\n" " ")
        temp=$(curl -Ls ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/seeds | jq -r  '.node.nodes[].value')
        AVAILABLE_SEEDS_STR=$(echo ${temp//\\} | jq -r '.host'| tr "\n" " ")


        read -a AVAILABLE_NODES <<< $AVAILABLE_NODES_STR
        read -a AVAILABLE_SEEDS <<< $AVAILABLE_SEEDS_STR

        echo "Available nodes are: ${AVAILABLE_NODES[@]}"
        echo "Available Seeds are: ${AVAILABLE_SEEDS[@]}"

        NON_SEED_AVAILABLE_NODES=()

        for i in "${AVAILABLE_NODES[@]}"; do
            skip=
            for j in "${AVAILABLE_SEEDS[@]}"; do
                [[ $i == $j ]] && { skip=1; break;}
            done
            [[ -n $skip ]] || NON_SEED_AVAILABLE_NODES+=($i)
        done
        echo "non seeds nodes are: ${NON_SEED_AVAILABLE_NODES[@]}"
        #lock seeds
        #lock choose proper number of nodes and put the in seeds
        REQUIRED_SEEDS=$(($NEEDED_SEEDS - $SEED_COUNT))
        echo "Number of required  seeds: $REQUIRED_SEEDS"
        for i in `seq 0 $(($REQUIRED_SEEDS -1))`; do
            echo "put seed"
        done
    fi
fi
