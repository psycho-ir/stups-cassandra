# This loop assigns order number for each node (to distribute snapshots afterwards)

CASSANDRA_2_HOME=/opt/cassandra
CASSANDRA_3_HOME=/opt/apache-cassandra-3.3
CASSANDRA_HOME=$CASSANDRA_3_HOME

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
                -XPUT -d value=1 )
            echo "$out"

        else
            my_order=$((prev_order+1))
            out=$(curl -Lsf ${ETCD_URL}/v2/keys/cassandra/${CLUSTER_NAME}/recoveryOrder?prevValue=$prev_order \
                -XPUT -d value=$my_order | jq -r '.errorCode')
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

S3_DIR=/var/cassandra/s3
mkdir -p $S3_DIR
snapshot_count=`aws s3 ls "s3://cassandra-release-backup/cassandra-snapshot/$recovery_snapshot/" | wc -l`

if [ $my_order -le $snapshot_count ]; then
    
    #list available snaphsots | print only folder name | take my_order 'th snapshot
    #result will be smth like '172.31.123.321/'
	node_folder=`aws s3 ls "s3://cassandra-release-backup/cassandra-snapshot/$recovery_snapshot/" | awk '{print $2;}' | sed -n ${my_order}p`
	aws s3 cp "s3://cassandra-release-backup/cassandra-snapshot/$recovery_snapshot/$node_folder" $S3_DIR/$node_folder --recursive

    # my_order=$(($my_order-$snapshot_count))
	

	# node_folder=`ls $S3_DIR | sed -n ${my_order}p`
	node_folder="$S3_DIR/$node_folder"

	for cql_file in `ls $node_folder*.cql`;
	do
	    cout=`$CASSANDRA_HOME/bin/cqlsh $LISTEN_ADDRESS -f $cql_file 2>&1`
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
	        cout=`$CASSANDRA_HOME/bin/cqlsh $LISTEN_ADDRESS -f $cql_file 2>&1`
	        result_status=$?
	        echo $result_status:$cout
	    done
	done
	for snapshot_dir in `ls -d $node_folder*/*/`;
	do
	    cout=`$CASSANDRA_HOME/bin/sstableloader -d ${LISTEN_ADDRESS} $snapshot_dir 2>&1`
	    result_status=$?
	    echo $result_status:$cout
	    while [ $result_status -ne 0 ]; do
	        echo "Sleep 10s..."
	        sleep 10s
	        cout=`$CASSANDRA_HOME/bin/sstableloader -d ${LISTEN_ADDRESS} $snapshot_dir 2>&1`
	        result_status=$?
	        echo $result_status:$cout
	    done
	done

	`$CASSANDRA_HOME/bin/nodetool -h $LISTEN_ADDRESS repair`
fi