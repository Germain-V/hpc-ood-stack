#!/bin/bash
#
# Cluster init configuration script
#

#
# wait for cloud-init completion on the controller host
#
execution=1

if [ -n "$1" ]; then
  playbook=$1
else
  playbook="/opt/oci-hpc/playbooks/site.yml"
fi

if [ -n "$2" ]; then
  inventory=$2
else
  inventory="/etc/ansible/hosts"
fi


if [ -f /opt/oci-hpc/playbooks/inventory ] ; then 
  sudo mv /opt/oci-hpc/playbooks/inventory /etc/ansible/hosts
fi 

if [ -f /tmp/configure.conf ] ; then
        configure=$(cat /tmp/configure.conf)
else
        configure=true
fi

if [[ $configure != true ]] ; then
        echo "Do not configure is set. Exiting"
        exit
fi


username=`cat $inventory | grep compute_username= | tail -n 1| awk -F "=" '{print $2}'`
if [ "$username" == "" ]
then
username=$USER
fi

# Wait for compute hosts with a configurable timeout; if it fails, proceed with controller-only
limit_arg=""
wait_timeout_seconds=${WAIT_FOR_HOSTS_TIMEOUT_SECONDS:-900}
if ! timeout --foreground "${wait_timeout_seconds}s" /opt/oci-hpc/bin/wait_for_hosts.sh /tmp/hosts "$username"; then
  echo "wait_for_hosts failed or timed out after ${wait_timeout_seconds}s; proceeding with controller-only configuration"
  limit_arg="-l controller"
fi

# Update the forks to a 8 * threads


#
# Ansible will take care of key exchange and learning the host fingerprints, but for the first time we need
# to disable host key checking.
#

if [[ $execution -eq 1 ]] ; then
  ANSIBLE_HOST_KEY_CHECKING=False ansible all ${limit_arg} --private-key ~/.ssh/cluster.key -m setup --tree /tmp/ansible > /dev/null 2>&1
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${limit_arg} --private-key ~/.ssh/cluster.key -i $inventory $playbook
else

        cat <<- EOF > /tmp/motd
        At least one of the cluster nodes has been innacessible during installation. Please validate the hosts and re-run:
        ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --private-key ~/.ssh/cluster.key /opt/oci-hpc/playbooks/site.yml
EOF

sudo mv /tmp/motd /etc/motd

fi
