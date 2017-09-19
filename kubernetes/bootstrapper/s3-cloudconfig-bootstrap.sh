#!/usr/bin/env bash

# This is a CoreOS Cluster Bootstrap script. It is passed in as 'user-data' file during the machine build.
# Then the script is excecuted to download the CoreOs "cloud-config.yaml" file  and "intial-cluster" files.
# These files  will configure the system to join the CoreOS cluster. The second stage cloud-config.yaml can
# be changed to allow system configuration changes without having to rebuild the system. All it takes is a reboot.
# If this script changes, the machine will need to be rebuild (user-data change)

# Convention:
# 1. A bucket should exist that contains role-based cloud-config.yaml
#  e.g. concur-<cluster-name>-cloudinit/<roleProfile>/cloud-config.yaml
# 2. All machines should have instance role profile, with a policy that allows readonly access to this bucket.

# Placement
region="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document/ | jq -r '.region')"
availability_zone="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document/ | jq -r '.availabilityZone')"

# Instance Profile
instance_profile="$(curl -s http://169.254.169.254/latest/meta-data/iam/info \
  | jq -r '.InstanceProfileArn' \
  | grep -Eo 'instance-profile/([a-zA-Z0-9.-]+)' \
  | sed 's#instance-profile/##')"

# Bucket
bucket="concur-${name}"

# Determine our role
role=$(echo "$instance_profile" | sed 's#${name}-##' | sed 's/-.*//')

work_dir="/root/cloudinit"
mkdir -m 700 -p "$work_dir"

# CloudInit Locations
cloudinit_src="s3://$bucket/cloudinit/$role"
cloudinit_dst="$work_dir"
cloudinit_common_tls_src="s3://$bucket/cloudinit/common/tls"
cloudinit_etcd_tls_src="s3://$bucket-etcd/cloudinit/common/tls"
cloudinit_tls_dst="$work_dir/tls"

# Set proxy for Docker to use. If no proxy is supplied, this will be blank
${docker_service_proxy}

# Set environment variables for Docker to use. If no variables are supplied, file will be empty
echo -e "${docker_environment}" > /etc/docker-environment.env

# pull the IMAGE if not loaded
image="quay.io/concur_platform/awscli:0.1.1"
rc=-1
until [ $rc -eq 0 ]
do
  docker history "$image" > /dev/null 2>&1 || docker pull "$image" && break
  rc=$?
  sleep 15
done

# Sync CloudInit
src="$cloudinit_src"
dst="$cloudinit_dst"
cmd="aws --region $region s3 cp --recursive $src $dst"
docker run --rm --name s3cp-cloudinit --env-file /etc/docker-environment.env -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

# Sync Common TLS Assets
src="$cloudinit_common_tls_src"
dst="$cloudinit_tls_dst"
cmd="aws --region $region s3 cp --recursive $src $dst"
docker run --rm --name s3cp-common-tls --env-file /etc/docker-environment.env -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

# Sync Etcd TLS Assets
src="$cloudinit_etcd_tls_src"
dst="$cloudinit_tls_dst"
cmd="aws --region $region s3 cp --recursive $src $dst"
docker run --rm --name s3cp-common-tls --env-file /etc/docker-environment.env -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

# Retrieving Etcd instances
cmd="aws autoscaling describe-auto-scaling-groups --region $region --auto-scaling-group-name ${name}-etcd | jq -r '.AutoScalingGroups | length'"
while [ $(docker run --rm --name etcd-instances --env-file /etc/docker-environment.env \
  "$image" /bin/bash -c "$cmd") -eq 0 ]
do
  sleep 3m
done

cmd="aws autoscaling describe-auto-scaling-groups --region $region --auto-scaling-group-name ${name}-etcd | jq -r '.AutoScalingGroups[0].Instances[] | select(.LifecycleState  == \"InService\") | .InstanceId' | xargs"
etcd_instance_ids=$(docker run --rm --name etcd-instances --env-file /etc/docker-environment.env \
  "$image" /bin/bash -c "$cmd")

cmd="aws ec2 describe-instances --region $region --instance-ids $etcd_instance_ids | jq -r '.Reservations[].Instances | map(\"https://\" + .PrivateDnsName + \":2379\")[]' | xargs | sed 's/  */,/g'"
etcd_endpoint_urls=$(docker run --rm --name etcd-urls --env-file /etc/docker-environment.env \
  "$image" /bin/bash -c "$cmd")

# Replace placeholders inside cloud-config
sed -i -- 's;\$etcd_endpoint_urls;'$etcd_endpoint_urls';g' $work_dir/cloud-config.yaml

sed -i -- 's;\$k8s_cluster_name;'$bucket';g' $work_dir/cloud-config.yaml

sed -i -- 's/\\$private_ipv4/'$private_ipv4'/g; s/\\$public_ipv4/'$public_ipv4'/g' $work_dir/cloud-config.yaml

# Create /etc/quoin-environment
quoin_cluster_environment='/etc/quoin-environment'
if [ ! -f "$quoin_cluster_environment" ];
then
  echo "QUOIN_NAME=${name}" > /etc/quoin-environment
  echo "REGION=$region" >> /etc/quoin-environment
  echo "AVAILABILITY_ZONE=$availability_zone" >> /etc/quoin-environment
fi

# Clean up and reset for cloudinit
docker ps -aq | xargs -r docker rm
docker volume ls -q | xargs -r docker volume rm
docker images -q | xargs -r docker rmi
systemctl stop docker.service
rm -rf /etc/systemd/system/docker.service.d
rm /etc/docker-environment.env

# Run cloud-init
coreos-cloudinit --from-file="$work_dir/cloud-config.yaml"
