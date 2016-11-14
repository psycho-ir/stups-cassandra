FROM registry.opensource.zalan.do/stups/openjdk:8u91-b14-1-22

MAINTAINER Zalando <team-mop@zalando.de>

# Storage Port, JMX, Jolokia Agent, Thrift, CQL Native, OpsCenter Agent
# Left out: SSL
EXPOSE 7000 7199 8778 9042 9160

ENV DEBIAN_FRONTEND=noninteractive
RUN echo "deb http://debian.datastax.com/community stable main" | tee -a /etc/apt/sources.list.d/datastax.community.list
RUN curl -sL https://debian.datastax.com/debian/repo_key | apt-key add -
RUN apt-get -y update && apt-get -y -o Dpkg::Options::='--force-confold' --fix-missing dist-upgrade
RUN apt-get -y install curl python wget jq sysstat python-pip supervisor && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Needed for transferring snapshots
RUN pip install awscli

ENV CASSIE_VERSION=3.8
#ADD http://archive.apache.org/dist/cassandra/${CASSIE_VERSION}/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz /tmp/
ADD http://ftp.fau.de/apache/cassandra/${CASSIE_VERSION}/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz /tmp/
#RUN echo "cb77a8e3792a7e8551af6602ac5f11df /tmp/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz" > /tmp/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz.md5
#RUN md5sum --check /tmp/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz.md5

RUN tar -xzf /tmp/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz -C /opt && ln -s /opt/apache-cassandra-${CASSIE_VERSION} /opt/cassandra
RUN rm -f /tmp/apache-cassandra-${CASSIE_VERSION}-bin.tar.gz*

RUN mkdir -p /var/cassandra/data
RUN mkdir -p /opt/jolokia/

ADD http://search.maven.org/remotecontent?filepath=org/jolokia/jolokia-jvm/1.3.1/jolokia-jvm-1.3.1-agent.jar /opt/jolokia/jolokia-jvm-agent.jar
#RUN echo "ca7c3eab12c8c3c5227d6fb4e51984bc /opt/jolokia/jolokia-jvm-agent.jar" > /tmp/jolokia-jvm-agent.jar.md5
#RUN md5sum --check /tmp/jolokia-jvm-agent.jar.md5
#RUN rm -f /tmp/jolokia-jvm-agent.jar.md5

ADD cassandra_template.yaml /opt/cassandra/conf/
ADD cassandra-rackdc_template.properties /opt/cassandra/conf/
# Slightly modified in order to run jolokia
ADD cassandra-env.sh /opt/cassandra/conf/

RUN rm -f /opt/cassandra/conf/cassandra.yaml && chmod 0777 /opt/cassandra/conf/
RUN ln -s /opt/cassandra/bin/nodetool /usr/bin && ln -s /opt/cassandra/bin/cqlsh /usr/bin

#ADD https://bintray.com/artifact/download/lmineiro/maven/cassandra-etcd-seed-provider-1.0.jar /opt/cassandra/lib/
ADD cassandra-etcd-seed-provider-1.1.1.jar /opt/cassandra/lib/
#RUN echo "37367e314fdc822f7c982f723336f07e /opt/cassandra/lib/cassandra-etcd-seed-provider-1.0.jar" > /tmp/cassandra-etcd-seed-provider-1.0.jar.md5
#RUN md5sum --check /tmp/cassandra-etcd-seed-provider-1.0.jar.md5
#RUN rm -f /tmp/cassandra-etcd-seed-provider-1.0.jar.md5

COPY cassandra-snapshotter.sh /opt/cassandra/bin/cassandra-snapshotter.sh
COPY snapshot-scheduler.sh /opt/cassandra/bin/snapshot-scheduler.sh
COPY repair-scheduler.sh /opt/cassandra/bin/repair-scheduler.sh
COPY seed-heartbeat.sh /opt/cassandra/bin/seed-heartbeat.sh

RUN chmod 0777 /opt/cassandra/bin/cassandra-snapshotter.sh && chmod 0777  /opt/cassandra/bin/snapshot-scheduler.sh && chmod 0777 /opt/cassandra/bin/seed-heartbeat.sh && chmod 0777 /opt/cassandra/conf/cassandra-env.sh

COPY stups-cassandra.sh /opt/cassandra/bin/
COPY recovery.sh /opt/cassandra/bin/
RUN chmod +x /opt/cassandra/bin/recovery.sh

# Create supervisor log folder
RUN mkdir -p /var/log/supervisor && chmod 0777 /var/log/supervisor
RUN touch /var/log/snapshot_cron.log && chmod 0777 /var/log/snapshot_cron.log

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY scm-source.json /scm-source.json

RUN mkdir -p /opt/recovery
ENV CASSANDRA_HOME=/opt/apache-cassandra-${CASSIE_VERSION}
ENV PATH=${CASSANDRA_HOME}/bin:$PATH

RUN echo 'deb mirror://mirrors.ubuntu.com/mirrors.txt precise main restricted universe multiverse' >> /etc/apt/sources.list
RUN apt-get update
RUN apt-get install -y vim --allow-unauthenticated

CMD ["/usr/bin/supervisord"]
