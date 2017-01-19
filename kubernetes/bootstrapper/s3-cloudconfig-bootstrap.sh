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
role=$(echo "$instance_profile" | sed 's#${name}-##')

work_dir="/root/cloudinit"
mkdir -m 700 -p "$work_dir"

# CloudInit Locations
cloudinit_src="s3://$bucket/cloudinit/$role"
cloudinit_dst="$work_dir"
cloudinit_common_tls_src="s3://$bucket/cloudinit/common/tls"
cloudinit_tls_dst="$work_dir/tls"

# pull the IMAGE if not loaded
image="quay.io/concur_platform/awscli:0.1.1"
docker history "$image" > /dev/null 2>&1 || docker pull "$image"

# Sync CloudInit
src="$cloudinit_src"
dst="$cloudinit_dst"
cmd="aws --region $region s3 cp --recursive $src $dst"
docker run --rm --name s3cp-cloudinit -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

# Sync Common TLS Assets
src="$cloudinit_common_tls_src"
dst="$cloudinit_tls_dst"
cmd="aws --region $region s3 cp --recursive $src $dst"
docker run --rm --name s3cp-common-tls -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

# Replace placeholders inside cloud-config
sed -i -- 's/\\$private_ipv4/'$private_ipv4'/g; s/\\$public_ipv4/'$public_ipv4'/g' $work_dir/cloud-config.yaml

# Decode TLS Assets
echo "Decoding TLS assets"
for encPemFile in $work_dir/tls/*.pem.enc.base; do
  echo "Decoding $encPemFile"
  cat $encPemFile | base64 -d > $${encPemFile%.base}
done

# Decrypt TLS Assets
docker run --rm --name decrypt-tls \
  -e REGION=$region \
  -e WORK_DIR=$work_dir/tls \
  -v $work_dir/tls:$work_dir/tls \
  quay.io/concur_platform/awscli:0.1.1 /bin/bash \
    -ec \
    'echo Decrypting TLS assets; \
    shopt -s nullglob; \
    for encPemFile in $WORK_DIR/*.pem.enc; do \
      echo Decrypting $encPemFile; \
      /usr/bin/aws \
        --region $REGION kms decrypt \
        --ciphertext-blob fileb://$encPemFile \
        --output text \
        --query Plaintext \
      | base64 -d > $${encPemFile%.enc}; \
    done; \
    cat $WORK_DIR/intermediate-ca.pem $WORK_DIR/root-ca.pem > $WORK_DIR/ca-chain.pem; \
    echo done.'

# Create /etc/quoin-environment
quoin_cluster_environment='/etc/quoin-environment'
if [ ! -f "$quoin_cluster_environment" ];
then
  echo "QUOIN_NAME=${name}" > /etc/quoin-environment
  echo "REGION=$region" >> /etc/quoin-environment
  echo "AVAILABILITY_ZONE=$availability_zone" >> /etc/quoin-environment
fi

# If our role is not etcd, then prepare initial-cluster for proxies
if [ ! $role = "etcd" ]; then
  initial_cluster_src="s3://$bucket/cloudinit/etcd/initial-cluster"
  initial_cluster_dst="$work_dir/initial-cluster"
  
  # Copy initial-cluster
  src="$initial_cluster_src"
  dst="$initial_cluster_dst"
  cmd="aws --region $region s3 cp $src $dst"
  docker run --rm --name s3cp -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"

  # If initial-cluster is not found
  # Run copy again in a loop until initial-cluster is found
  # This is mainly for timing when launching a cluster from scratch
  if [ ! -f "$initial_cluster_dst" ]; then
    until [ -f "$initial_cluster_dst" ]; do
      # Add a small delay before copy to make sure we give the etcd cluster enough time
      # during initial launch
      sleep 360
      docker run --rm --name s3cp -v "$work_dir":"$work_dir" "$image" /bin/bash -c "$cmd"
    done
  fi

  # Copy initial-cluster to the volume that will be picked up by etcd boostraping
  if [ -f "$work_dir/initial-cluster" ] && grep -q ETCD_INITIAL_CLUSTER $work_dir/initial-cluster ;
  then
    mkdir -p /var/run/coreos
    cp "$work_dir/initial-cluster" /var/run/coreos/initial-cluster
  fi
fi

# Clean up and reset for cloudinit
docker ps -aq | xargs -r docker rm
docker volume ls -q | xargs -r docker volume rm
docker images -q | xargs -r docker rmi
systemctl stop docker.service

# Run cloud-init
coreos-cloudinit --from-file="$work_dir/cloud-config.yaml"
