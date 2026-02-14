FROM rockylinux:8

LABEL org.opencontainers.image.source="https://github.com/giovtorres/slurm-docker-cluster" \
      org.opencontainers.image.title="slurm-docker-cluster" \
      org.opencontainers.image.description="Slurm Docker cluster on Rocky Linux 8" \
      org.label-schema.docker.cmd="docker-compose up -d" \
      maintainer="Giovanni Torres"


ARG SLURM_TAG=slurm-21-08-6-1
ARG GOSU_VERSION=1.11

# the bamboo user
ARG BAMBOO_USER=bamboo
ARG BAMBOO_USER_ID=996
ARG BAMBOO_GROUP=scitech
ARG BAMBOO_GROUP_ID=996

# number of slurm workers to update slurm config
ARG SLURM_NUM_NODES=3
# memory assigned in MB
ARG SLURM_NODE_MEMORY=2000

#### ENV Variables For Packages ####
ENV PEGASUS_VERSION "pegasus-5.1.3-dev.0"
ENV PEGASUS_VERSION_NUM "5.1.3-dev.0"

RUN <<EOT
# Create user ASAP so teh uid/gid do not get used by other installed packages.
set -x
groupadd -r --gid=$BAMBOO_GROUP_ID $BAMBOO_GROUP
useradd -m -g $BAMBOO_GROUP --password '\$1\$INpOHe38\$RghIh80Eg41A4L/xsdsbxI/'  --uid=$BAMBOO_USER_ID $BAMBOO_USER
EOT

RUN set -ex \
    && dnf makecache \
    && dnf -y update \
    && dnf -y install dnf-plugins-core \
    && dnf config-manager --set-enabled powertools \
    && dnf -y install \
       wget \
       bzip2 \
       perl \
       gcc \
       gcc-c++\
       git \
       gnupg \
       make \
       munge \
       munge-devel \
       python3-devel \
       python3-pip \
       python3 \
       mariadb-server \
       mariadb-devel \
       psmisc \
       bash-completion \
       vim-enhanced \
       http-parser-devel \
       json-c-devel \
       rsync \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN alternatives --set python /usr/bin/python3

RUN pip3 install Cython nose

RUN set -ex \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && rm -rf "${GNUPGHOME}" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true

RUN set -x \
    && git clone -b ${SLURM_TAG} --single-branch --depth=1 https://github.com/SchedMD/slurm.git \
    && pushd slurm \
    && ./configure --enable-debug --prefix=/usr --sysconfdir=/etc/slurm \
        --with-mysql_config=/usr/bin  --libdir=/usr/lib64 \
    && make install \
    && install -D -m644 etc/cgroup.conf.example /etc/slurm/cgroup.conf.example \
    && install -D -m644 etc/slurm.conf.example /etc/slurm/slurm.conf.example \
    && install -D -m644 etc/slurmdbd.conf.example /etc/slurm/slurmdbd.conf.example \
    && install -D -m644 contribs/slurm_completion_help/slurm_completion.sh /etc/profile.d/slurm_completion.sh \
    && popd \
    && rm -rf slurm \
    && groupadd -r --gid=990 slurm \
    && useradd -r -g slurm --uid=990 slurm \
    && mkdir /etc/sysconfig/slurm \
        /var/spool/slurmd \
        /var/run/slurmd \
        /var/run/slurmdbd \
        /var/lib/slurmd \
        /var/log/slurm \
        /data \
    && touch /var/lib/slurmd/node_state \
        /var/lib/slurmd/front_end_state \
        /var/lib/slurmd/job_state \
        /var/lib/slurmd/resv_state \
        /var/lib/slurmd/trigger_state \
        /var/lib/slurmd/assoc_mgr_state \
        /var/lib/slurmd/assoc_usage \
        /var/lib/slurmd/qos_usage \
        /var/lib/slurmd/fed_mgr_state \
    && chown -R slurm:slurm /var/*/slurm* \
    && /sbin/create-munge-key

COPY slurm.conf /etc/slurm/slurm.conf
COPY slurmdbd.conf /etc/slurm/slurmdbd.conf
RUN set -x \
    && chown slurm:slurm /etc/slurm/slurmdbd.conf \
    && chmod 600 /etc/slurm/slurmdbd.conf



#### Update slurm.conf to increase memory available on nodes ####
RUN perl -pi.bak -e "s/^NodeName=c\[1-2\] RealMemory=1000 State=UNKNOWN/NodeName=c\[1-$SLURM_NUM_NODES\] RealMemory=$SLURM_NODE_MEMORY State=UNKNOWN/" /etc/slurm/slurm.conf \
    && perl -pi -e "s/^PartitionName=normal Default=yes Nodes=c\[1-2\]/PartitionName=normal Default=yes Nodes=c\[1-$SLURM_NUM_NODES\]/" /etc/slurm/slurm.conf


RUN <<EOT
#### Installing and configuring SSH server ####
dnf -y install openssh-server openssh-clients
perl -pi -e 's/^#RSAAuthentication yes/RSAAuthentication yes/' /etc/ssh/sshd_config
perl -pi -e 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
perl -pi -e 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
perl -pi -e 's/^#UsePAM no/UsePAM no/' /etc/ssh/sshd_config
perl -pi -e 's/^UsePAM yes/#UsePAM yes/' /etc/ssh/sshd_config
/usr/bin/ssh-keygen -A

#### Install NFS client and create the mount dir ####
dnf install -y nfs-utils
mkdir /nfs

#### Install libraries required for Condor BLAHP to work ####
dnf install -y libtool-ltdl python3

#### Setup Bamboo User ####
chown -R $BAMBOO_USER:$BAMBOO_GROUP /data
mkdir -p /nfs/$BAMBOO_USER
chown -R $BAMBOO_USER:$BAMBOO_GROUP /nfs/$BAMBOO_USER

#### Install Pegasus from tarball ####
curl -o /opt/${PEGASUS_VERSION}.tar.gz http://download.pegasus.isi.edu/pegasus/${PEGASUS_VERSION_NUM}/pegasus-binary-${PEGASUS_VERSION_NUM}-x86_64_rhel_8.tar.gz
tar -xzvf /opt/${PEGASUS_VERSION}.tar.gz -C /opt
rm -f /opt/${PEGASUS_VERSION}.tar.gz
chmod 755 -R /opt/${PEGASUS_VERSION}
(cd /opt && ln -s ${PEGASUS_VERSION} pegasus)



#### Install globus-url-copy and CA certificates ####
dnf -y install 'dnf-command(config-manager)'
dnf -y install https://downloads.globus.org/globus-connect-server/stable/installers/repo/rpm/globus-repo-latest.noarch.rpm
dnf -y install globus-gass-copy-progs
curl -o /tmp/certs.tgz https://download.pegasus.isi.edu/containers/certificates.tar.gz
mkdir -p /etc/grid-security
tar -zxvf /tmp/certs.tgz -C /etc/grid-security/
rm -f /tmp/certs.tgz

#### Install Montage from tarball ####
dnf install -y libnsl2-devel
mkdir -p /opt/software/montage
curl -o /opt/montage.tar.gz http://montage.ipac.caltech.edu/download/Montage_v6.0.tar.gz
tar -xzvf /opt/montage.tar.gz -C /opt/software/montage
rm -f /opt/montage.tar.gz
(cd /opt/software/montage/Montage && make)
(cd /opt/software/montage && mv Montage 6.0 && ln -s 6.0 current)
chmod 755 -R /opt/software/montage/current/bin/
dnf install -y freetype
EOT

ENV PATH "/opt/${PEGASUS_VERSION}/bin:$PATH"
ENV PYTHONPATH "/opt/${PEGASUS_VERSION}/lib64/python3.6/site-packages:/opt/${PEGASUS_VERSION}/lib64/pegasus/externals/python:$PYTHONPATH"
ENV PERL5LIB "/opt/${PEGASUS_VERSION}/lib64/pegasus/perl:$PERL5LIB"

#### Configure SSH for Bamboo User ####
USER $BAMBOO_USER
RUN mkdir /home/$BAMBOO_USER/.ssh
COPY bamboo_slurm_id_rsa.pub /home/$BAMBOO_USER/.ssh/
RUN cat /home/$BAMBOO_USER/.ssh/bamboo_slurm_id_rsa.pub > /home/$BAMBOO_USER/.ssh/authorized_keys
COPY workflow_id_rsa.pub /home/$BAMBOO_USER/.ssh/
RUN cat /home/$BAMBOO_USER/.ssh/workflow_id_rsa.pub >> /home/$BAMBOO_USER/.ssh/authorized_keys
RUN chmod 700 /home/$BAMBOO_USER/.ssh/authorized_keys

USER root
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["slurmdbd"]
