# Slurm Docker Cluster

This is a multi-container Slurm cluster using docker-compose.  The compose file
creates named volumes for persistent storage of MySQL data files as well as
Slurm state and log directories.

## Containers and Volumes

The compose file will run the following containers:

* mysql
* slurmdbd
* slurmctld
* c1 (slurmd)
* c2 (slurmd)

The compose file will create the following named volumes:

* etc_munge         ( -> /etc/munge     )
* etc_slurm         ( -> /etc/slurm     )
* slurm_jobdir      ( -> /data          )
* var_lib_mysql     ( -> /var/lib/mysql )
* var_log_slurm     ( -> /var/log/slurm )

## Building the Docker Image

Build the image locally:

```console
docker build -t slurm-docker-cluster:21.08.6 .
```

Build a different version of Slurm using Docker build args and the Slurm Git
tag:

```console
docker build --build-arg SLURM_TAG="slurm-19-05-2-1" -t slurm-docker-cluster:19.05.2 .
```

Or equivalently using `docker-compose`:

```console
SLURM_TAG=slurm-19-05-2-1 IMAGE_TAG=19.05.2 docker-compose build
```


## Starting the Cluster

Run `docker-compose` to instantiate the cluster:

```console
IMAGE_TAG=19.05.2 docker-compose up -d
```

## Register the Cluster with SlurmDBD

To register the cluster to the slurmdbd daemon, run the `register_cluster.sh`
script:

```console
./register_cluster.sh
```

> Note: You may have to wait a few seconds for the cluster daemons to become
> ready before registering the cluster.  Otherwise, you may get an error such
> as **sacctmgr: error: Problem talking to the database: Connection refused**.
>
> You can check the status of the cluster by viewing the logs: `docker-compose
> logs -f`

## Accessing the Cluster

Use `docker exec` to run a bash shell on the controller container:

```console
docker exec -it slurmctld bash
```

From the shell, execute slurm commands, for example:

```console
[root@slurmctld /]# sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 5-00:00:00      2   idle c[1-2]
```

## Submitting Jobs

The `slurm_jobdir` named volume is mounted on each Slurm container as `/data`.
Therefore, in order to see job output files while on the controller, change to
the `/data` directory when on the **slurmctld** container and then submit a job:

```console
[root@slurmctld /]# cd /data/
[root@slurmctld data]# sbatch --wrap="hostname"
Submitted batch job 2
[root@slurmctld data]# ls
slurm-2.out
[root@slurmctld data]# cat slurm-2.out
c1
```

## Stopping and Restarting the Cluster

```console
docker-compose stop
docker-compose start
```

## Deleting the Cluster

To remove all containers and volumes, run:

```console
docker-compose stop
docker-compose rm -f
docker volume rm slurm-docker-cluster_etc_munge slurm-docker-cluster_etc_slurm slurm-docker-cluster_slurm_jobdir slurm-docker-cluster_var_lib_mysql slurm-docker-cluster_var_log_slurm
```
## Updating the Cluster

If you want to change the `slurm.conf` or `slurmdbd.conf` file without a rebuilding you can do so by calling
```console
./update_slurmfiles.sh slurm.conf slurmdbd.conf
```
(or just one of the files).
The Cluster will automatically be restarted afterwards with
```console
docker-compose restart
```
This might come in handy if you add or remove a node to your cluster or want to test a new setting.

## Additional Scitech Specific Modifications

This setup in addition 

* Mounts nfs filesystem in the containers at `/nfs`. 
* The home filesystem is mounted out of a volume named `user_home`. 
* Sets up a `bamboo` user in the dockerized setup
* The public key for the bamboo user on scitech machines is picked up from `bamboo_slurm_id_rsa.pub`, and used for setup of the bamboo user in the slurm cluster setup. 
* The SSH server set on the `slurmctld` container binds to `2222` on the host machine.
* The public key `workflow_id_rsa.pub` is used for transferring data into the slurm cluster


### HTCondor Setup on Workflow Submit Node

By default, BOSCO submits job via port 22. There is no knob to change the port.
To use a different port, on your bosco install, apply the patch file `bosco_cluster-901.patch` 
using the patch command as root

```console
cd /usr/bin
patch -i /path/to/bosco_cluster-901.patch 
```
Also you need to edit /usr/sbin/remote_gahp and update the ssh port to 2222 from 22

### Add cluster in Bosco on the Workflow Submit Node

Before running any jobs via BOSCO, we set up this docker slurm cluster on the workflow
submit node from where jobs will be submitted to this SLURM cluster.

You need to run these commands as the user that submits the jobs. In SciTech case, that
is user `bamboo`

```console
[bamboo@bamboo ~]$ bosco_cluster --add slurm-pegasus.isi.edu slurm
Cluster slurm-pegasus.isi.edu already installed
Reinstalling on slurm-pegasus.isi.edu
Enter the password to copy the ssh keys to slurm-pegasus.isi.edu:
Enter passphrase for key '/scitech/shared/home/bamboo/.ssh/id_rsa': 
Downloading release build for slurm-pegasus.isi.edu.
Unpacking.
You are not running as the factory user. Glideins disabled.
Installing on cluster slurm-pegasus.isi.edu.
Installation complete
The cluster slurm-pegasus.isi.edu has been added for remote submission
It is available to run jobs submitted with the following values:
> universe = grid
> grid_resource = batch slurm slurm-pegasus.isi.edu
[bamboo@bamboo ~]$ 
```

To check cluster is added
```console
[bamboo@bamboo ~]$ bosco_cluster --list
corbusier.isi.edu/slurm
slurm-pegasus.isi.edu/slurm
```

You can test the setup by
```console
[bamboo@bamboo ~]$ bosco_cluster --test slurm-pegasus.isi.edu
Testing ssh to slurm-pegasus.isi.edu...Passed!
Testing remote submission...Passed!
Submission and log files for this job are in /scitech/shared/home/bamboo/bosco-test/boscotest.zBVeb
Waiting for jobmanager to accept job...Passed
```

The corresponding test condor job can be found in the directory ~/bosco_test
```
bamboo@bamboo boscotest.zBVeb]$ pwd
/scitech/shared/home/bamboo/bosco-test/
```

