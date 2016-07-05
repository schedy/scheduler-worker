# ####################################################################################################
#
# Docker >= 1.10 is recommended!
#
# To build an image:
# docker build <PATH_TO_FOLDER_OF_THIS_FILE> 
# e.g.
# docker build -t worker-image .
#
# If dnf needs to use a proxy you can configure that with:
# --build-arg=REPO_PROXY_ARG='http://my-proxy:8080'
#
# ####################################################################################################
#
# To build a container:
# docker create -v <PG_DATA_STORE>:/data/:Z -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
#        --hostname <HOSTNAME> --add-host scheduler-server:WWW.XXX.YYY.ZZZ <IMAGE-ID_OR_NAME>
# e.g.
# docker create --name worker-container -v /data/worker/docker-psql:/data/:Z \
#        -v /sys/fs/cgroup:/sys/fs/cgroup:ro --hostname ts003 --add-host scheduler-server:127.0.0.1 worker-image
#
# <PG_DATA_STORE> is the path on the host system to store the
# postgres 'database cluster'. Without '-v <PG_DATA_STORE>:/data/:Z'
# the 'database cluster' will be located inside the container and
# will be lost when the container is deleted!
#
# Alternatively you can also create a Docker 'named volume' and mount
# in /data:
# docker create --privileged -v myDATA:/data/:Z <IMAGE-ID_OR_NAME>
#
# <HOSTNAME> estimator/executor/reporter use the given hostname as worker name, so better
# set it to something meaning full in production.
#
# --add-host: config.rb has the scheduler server set to "scheduler-server", so point it to the IP
#   under which the scheduler server is reachable.
#
# --privileged might be needed for systemd to work! We might need that in future for devices?
# see: http://lwn.net/SubscriberLink/676831/bc927a5c0955d2b7/
#
# to have the journal in tmpfs you need Docker >= 1.10 with the --tmpfs option:
# --tmpfs /run:rw,size=1g
#
# ####################################################################################################
#
# The postgresql db inside the container has it's 'database cluster'
# in /data/postgresql/data.
# You can change that in the file:
# 30-postgres-setup.conf
# 
# NOTE:
# Your filesystem layout should ideally look like:
# /ROOT_OWNED_MOUNTPOINT/POSTGRES_OWNED_DIRECTORY/DATADIR
# see: http://www.postgresql.org/docs/9.4/static/creating-cluster.html
#      https://bugzilla.redhat.com/show_bug.cgi?id=1247477#c1
#
# ####################################################################################################

FROM fedora:23

ARG REPO_PROXY_ARG

ENV container docker
ENV TERM linux

CMD ["/usr/lib/systemd/systemd"]

ADD 30-scheduler-journal.conf /etc/systemd/journald.conf.d/

ADD repo-proxy-setup.sh /usr/local/bin
RUN REPO_PROXY=$REPO_PROXY_ARG /usr/local/bin/repo-proxy-setup.sh

RUN dnf -y --setopt=tsflags=nodocs group install "C Development Tools and Libraries"
RUN dnf -y --setopt=tsflags=nodocs install rubygem-bundler ruby-devel redhat-rpm-config postgresql-devel postgresql-server bash-completion

# Postgres part
ADD postgresql-initdb.service /usr/lib/systemd/system/
ADD postgresql-initdb.sh /usr/libexec/
ADD 30-postgres-setup.conf /etc/systemd/system/postgresql.service.d/
RUN systemctl enable postgresql-initdb.service postgresql.service

# Scheduler-Worker part
RUN useradd --create-home --home-dir /opt/tester --system --user-group tester
ADD scheduler-worker.tar.bz2 /opt/tester/scheduler-worker/
ADD database.rb /opt/tester/scheduler-worker/config/
RUN chown -R tester.tester /opt/tester/scheduler-worker/

USER tester
WORKDIR /opt/tester/scheduler-worker/
RUN bundle install --deployment

USER root

ADD scheduler-worker-init.sh /usr/libexec/

ADD \
    scheduler-worker-cleaner.service \
    scheduler-worker-executor.service \
    scheduler-worker-reporter.service \
    scheduler-worker-init.service \
    /usr/lib/systemd/system/

RUN systemctl enable \
    scheduler-worker-cleaner.service \
    scheduler-worker-executor.service \
    scheduler-worker-reporter.service

