FROM centos:7

LABEL org.opencontainers.image.source="https://github.com/giovtorres/slurm-docker-cluster" \
      org.opencontainers.image.title="slurm-docker-cluster" \
      org.opencontainers.image.description="Slurm Docker cluster on CentOS 7" \
      org.label-schema.docker.cmd="docker-compose up -d" \
      maintainer="Giovanni Torres"

ARG SLURM_TAG=slurm-19-05-1-2
ARG GOSU_VERSION=1.11

# the bamboo user
ARG BAMBOO_USER=bamboo
ARG BAMBOO_USER_ID=996
ARG BAMBOO_GROUP=scitech
ARG BAMBOO_GROUP_ID=996

#### ENV Variables For Packages ####
ENV PEGASUS_VERSION "pegasus-5.0.0"
ENV PEGASUS_VERSION_NUM "5.0.0"

RUN set -ex \
    && yum makecache fast \
    && yum -y update \
    && yum -y install epel-release \
    && yum -y install \
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
       python-devel \
       python-pip \
       python34 \
       python34-devel \
       python34-pip \
       mariadb-server \
       mariadb-devel \
       psmisc \
       bash-completion \
       vim-enhanced \
    && yum clean all \
    && rm -rf /var/cache/yum
    
RUN ln -s /usr/bin/python3.4 /usr/bin/python3

RUN pip install Cython nose && pip3.4 install Cython nose

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
    && git clone https://github.com/SchedMD/slurm.git \
    && pushd slurm \
    && git checkout tags/$SLURM_TAG \
    && ./configure --enable-debug --prefix=/usr --sysconfdir=/etc/slurm \
        --with-mysql_config=/usr/bin  --libdir=/usr/lib64 \
    && make install \
    && install -D -m644 etc/cgroup.conf.example /etc/slurm/cgroup.conf.example \
    && install -D -m644 etc/slurm.conf.example /etc/slurm/slurm.conf.example \
    && install -D -m644 etc/slurmdbd.conf.example /etc/slurm/slurmdbd.conf.example \
    && install -D -m644 contribs/slurm_completion_help/slurm_completion.sh /etc/profile.d/slurm_completion.sh \
    && popd \
    && rm -rf slurm \
    && groupadd -r --gid=995 slurm \
    && useradd -r -g slurm --uid=995 slurm \
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

#### Update slurm.conf to increase memory available on nodes ####
RUN perl -pi -e 's/^NodeName=c\[1-2\] RealMemory=1000 State=UNKNOWN/NodeName=c\[1-2\] RealMemory=2000 State=UNKNOWN/' /etc/slurm/slurm.conf

#### Installing and configuring SSH server ####
RUN yum -y install openssh-server openssh-clients
RUN perl -pi -e 's/^#RSAAuthentication yes/RSAAuthentication yes/' /etc/ssh/sshd_config
RUN perl -pi -e 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
RUN perl -pi -e 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
RUN perl -pi -e 's/^#UsePAM no/UsePAM no/' /etc/ssh/sshd_config
RUN perl -pi -e 's/^UsePAM yes/#UsePAM yes/' /etc/ssh/sshd_config
RUN   /usr/bin/ssh-keygen -A

#### Install NFS client and create the mount dir ####
RUN set -x \
    && yum install -y nfs-utils \
    &&  mkdir /nfs

#### Install libraries required for Condor BLAHP to work ####
RUN set -x \
    && yum install -y \
       libtool-ltdl \
       python3

#### Setup Bammboo User ####
RUN set -x \
    && groupadd -r --gid=$BAMBOO_GROUP_ID $BAMBOO_GROUP \
    && useradd -m -g $BAMBOO_GROUP --password '\$1\$INpOHe38\$RghIh80Eg41A4L/xsdsbxI/'  --uid=$BAMBOO_USER_ID $BAMBOO_USER \
    && chown -R $BAMBOO_USER:$BAMBOO_GROUP /data \
    && mkdir -p /nfs/$BAMBOO_USER \
    && chown -R $BAMBOO_USER:$BAMBOO_GROUP /nfs/$BAMBOO_USER

#### Install Pegasus from tarball ####
RUN curl -o /opt/${PEGASUS_VERSION}.tar.gz http://download.pegasus.isi.edu/pegasus/${PEGASUS_VERSION_NUM}/pegasus-binary-${PEGASUS_VERSION_NUM}-x86_64_rhel_7.tar.gz && \
    tar -xzvf /opt/${PEGASUS_VERSION}.tar.gz -C /opt && \
    rm /opt/${PEGASUS_VERSION}.tar.gz && \
    chmod 755 -R /opt/${PEGASUS_VERSION} && \
    (cd /opt && ln -s ${PEGASUS_VERSION} pegasus)

ENV PATH "/opt/${PEGASUS_VERSION}/bin:$PATH"
ENV PYTHONPATH "/opt/${PEGASUS_VERSION}/lib64/python3.6/site-packages:/opt/${PEGASUS_VERSION}/lib64/pegasus/externals/python:$PYTHONPATH"
ENV PERL5LIB "/opt/${PEGASUS_VERSION}/lib64/pegasus/perl:$PERL5LIB"

#### Install globus-url-copy and CA certificates ####
RUN yum -y install globus-gass-copy-progs
RUN curl -o /tmp/certs.tgz https://download.pegasus.isi.edu/containers/certificates.tar.gz && \
    mkdir -p /etc/grid-security && \
    tar -zxvf /tmp/certs.tgz -C /etc/grid-security/ && \
    rm /tmp/certs.tgz

#### Install Montage from tarball ####
RUN mkdir -p /opt/software/montage && \
    curl -o /opt/montage.tar.gz http://montage.ipac.caltech.edu/download/Montage_v6.0.tar.gz &&  \
    tar -xzvf /opt/montage.tar.gz -C /opt/software/montage && \
    rm /opt/montage.tar.gz && \
    (cd /opt/software/montage/Montage && make ) && \
    (cd /opt/software/montage &&  mv Montage 6.0 && ln -s 6.0 current) && \ 
    chmod 755 -R /opt/software/montage/current/bin/ && \
    yum install -y freetype
   
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
