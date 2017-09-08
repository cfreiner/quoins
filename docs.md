# Bastion

This module creates a bastion instance. The bastion host acts as the
"jump point" for the rest of the infrastructure. Since most of our
instances aren't exposed to the external internet, the bastion acts as
the gatekeeper for any direct SSH access. The bastion is provisioned using
the key name that you pass to the module (and hopefully have stored somewhere).
If you ever need to access an instance directly, you can do it by
"jumping through" the bastion.

Usage:

```hcl
module "bastion" {
  source                = "github.com/concur/quoins//bastion"
  bastion_ami_id        = "ami-*****"
  bastion_instance_type = "t2.micro"
  bastion_key_name      = "ssh-key"
  security_groups       = "sg-*****,sg-*****"
  subnet_id             = "pub-1"
  cost_center           = "1000"
  role_type             = "abcd"
  name                  = "quoin-bastion"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| bastion_ami_id | The ID Amazon Machine Image (AMI) to use for the instance. | - | yes |
| bastion_instance_type | Instance type, see a list at: https://aws.amazon.com/ec2/instance-types/ | `t2.micro` | no |
| bastion_key_name | The name of the SSH key pair to use for the bastion. | - | yes |
| security_group_ids | A comma separated lists of security group IDs | - | yes |
| availability_zone | An availability zone to launch the instance. | - | yes |
| subnet_id | An external subnet id. | - | yes |
| name | A name to prefix the bastion tag. | - | yes |
| role_type | The role type to attach resource usage. | - | yes |
| cost_center | The cost center to attach resource usage. | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| bastion_external_ip | Bastion external IP address |

# ELB External

This module creates an elastic load balancer to be used by instances for exposing services.

Usage:

```hcl
module "elb-unsecure" {
  source        = "github.com/concur/quoins//elb-external"
  name          = "elb-unsecure"
  vpc_id        = "vpc-123456"
  subnet_ids    = "subnet-123456,subnet-123457,subnet-123458"
  lb_port       = "80"
  instance_port = "30000"
  healthcheck   = "/health"
  protocol      = "HTTP"
}

module "elb-secure" {
  source             = "github.com/concur/quoins//elb-external"
  name               = "elb-secure"
  vpc_id             = "vpc-123456"
  subnet_ids         = "subnet-123456,subnet-123457,subnet-123458"
  lb_port            = "443"
  instance_port      = "30000"
  healthcheck        = "/health"
  protocol           = "HTTPS"
  ssl_certificate_id = "arn:aws:..."
}

provider "aws" {
  region = "us-west-2"
}
```

# ELB Internal

This module creates an internal elastic load balancer to be used by instances for exposing services.

Usage:

```hcl
module "elb-unsecure" {
  source        = "github.com/scipian/quoins//elb-internal"
  name          = "elb-unsecure"
  vpc_id        = "vpc-123456"
  subnet_ids    = "subnet-123456,subnet-123457,subnet-123458"
  lb_port       = "80"
  instance_port = "30000"
  healthcheck   = "/health"
  protocol      = "HTTP"
}

module "elb-secure" {
  source             = "github.com/scipian/quoins//elb-internal"
  name               = "elb-secure"
  vpc_id             = "vpc-123456"
  subnet_ids         = "subnet-123456,subnet-123457,subnet-123458"
  lb_port            = "443"
  instance_port      = "30000"
  healthcheck        = "/health"
  protocol           = "HTTPS"
  ssl_certificate_id = "arn:aws:..."
}

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| name | ELB name, e.g cdn | - | yes |
| vpc_id | The ID of the VPC to create the resources within. | - | yes |
| subnet_ids | Comma separated list of subnet IDs | - | yes |
| lb_port | Load balancer port | - | yes |
| instance_port | Instance port | - | yes |
| healthcheck | Healthcheck path | - | yes |
| protocol | Protocol to use, HTTP or TCP | - | yes |
| ssl_certificate_id | The ARN of an SSL certificate you have uploaded to AWS IAM. | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| name | The ELB name. |
| id | The ELB ID. |
| dns | The ELB dns_name. |

# External/Internal Layout

This module creates a network layout with the following resources
inside a network:

1. An external subnet for each availability zone in a region.
2. An internal subnet for each availability zone in a region.
3. An nat gateway to route traffic from the internal subnets to the internet.

Usage:

```hcl
module "network_layout" {
  source              = "github.com/concur/quoins//external-internal-layout"
  vpc_id              = "vpc-*****"
  internet_gateway_id = "igw-*****"
  availability_zones  = "us-west-2a,us-west-2b,us-west-2c"
  external_subnets    = "172.16.0.0/24,172.16.1.0/24,172.16.2.0/24"
  internal_subnets    = "172.16.3.0/24,172.16.4.0/24,172.16.5.0/24"
  name                = "prod-us-network-layout"
}

provider "aws" {
  region = "us-west-2"
}
```

# Internal Layout

This module creates an internal network layout only with the following resources
inside a network:

1. An internal subnet for each availability zone in a region.

Usage:

```hcl
module "internal_layout" {
  source              = "github.com/concur/quoins//internal-layout"
  vpc_id              = "vpc-*****"
  availability_zones  = "us-west-2a,us-west-2b,us-west-2c"
  internal_subnets    = "172.16.3.0/24,172.16.4.0/24,172.16.5.0/24"
  name                = "prod-us-network-layout"
  k8_cluster_name     = <kubernetes-quoin-name>
}

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| vpc_id | The ID of the VPC to create the resources within. | - | yes |
| internet_gateway_id | The ID of the internet gateway that belongs to the VPC. | - | yes |
| availability_zones | Comma separated list of availability zones for a region. | - | yes |
| external_subnets | Comma separated list of CIDR's to use for the external subnets. | - | yes |
| internal_subnets | Comma separated list of CIDR's to use for the internal subnets. | - | yes |
| name | A name to tag the resources. | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| availability_zones | A comma-separated list of availability zones for the network. |
| external_subnet_ids | A comma-separated list of subnet ids for the external subnets. |
| external_rtb_id | The external route table ID. |
| internal_subnet_ids | A comma-separated list of subnet ids for the internal subnets. |
| internal_rtb_ids | The internal route table ID. |

# Key Pair

This module creates a key pair to be used by instances.

Usage:

```hcl
module "ssh_key_pair" {
  source = "github.com/concur/quoins//key-pair"
  key_name   = "quoin-bastion"
  public_key = "ssh-rsa skdlfjkljasfkdjjkas;dfjksakj ... email@domain.com"
}

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| key_name | A name to give the key pair. | - | yes |
| public_key | Public key material in a format supported by AWS: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#how-to-generate-your-own-key-and-import-it-to-aws | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| key_name | Key name given to key pair |
| fingerprint | Fingerprint of given public key |

# Kubernetes

This module creates an opinionated [Kubernetes][kubernetes] cluster in AWS. Currently, this
quoin only supports the AWS provider and has only been tested in the us-west-2 and eu-central-1
regions.

Although terraform is capable of maintaining and altering state of infrastructure, this Quoin is
only intended to stand up new clusters. Please do not attempt to alter the configuration of
existing clusters. We treat our clusters as immutable resources.

[kubernetes]: http://kubernetes.io

The way the cluster is provisioned is by using Terraform configs to create the
appropriate resources in AWS. From that point, we use CoreOS, Auto Scaling Groups
with Launch Configurations to launch the Kubernetes cluster. The cluster is launched in
an air gapped way using only AWS API's, therefore, by default, there isn't a way to SSH
directly to an instance without a bastion. We use our Bastion Quoin to launch on-demand
bastions when the need arises. Currently we launch version 1.2.4 of Kubernetes.

## What's Inside

* A security group for bastions to use.
* CoreOS is used as the host operating system for all instances.
* The certificates are used to completely secure the communication between etcd, controllers, and nodes.
* Creates a dedicated etcd cluster within the private subnets using an auto scaling group.
  * EBS Volumes:
    * Root block store device
    * Encrypted block store for etcd data mounted at /var/lib/etcd2
* Creates a Kubernetes control plane within the private subnets using an auto scaling group.
  * An ELB attached to each instance to allow external access to the API.
  * EBS Volumes:
    * Root block store device
    * Encrypted block store for Docker mounted at /var/lib/docker
* Creates a Kubernetes nodes within the private subnets using an auto scaling group.
  * EBS Volumes:
    * Root block store device
    * Encrypted block store for Docker mounted at /var/lib/docker
    * Encrypted block store for data mounted at /opt/data
    * Encrypted block store for logging mounted at /opt/logging
* Systemd timer to garbage collect docker images and containers daily.
* Systemd timer to logrotate docker logs hourly.
* Creates an ssh key pair for the cluster using the passed in public key.
* s3 bucket for the cluster where configs are saved for ASG and also allows the cluster to use it for backups.
* IAM roles to give instances permission to access resources based on their role
* Fluent/ElasticSearch/Kibana runs within the cluster to ship all logs to a central location. Only thing needed by the developer is to log to stdout or stderr.

Usage:

```hcl
module "kubernetes" {
  source                                = "github.com/concur/quoins//kubernetes"
  name                                  = "prod"
  k8_cluster_name                       = "prod"
  role_type                             = "app1"
  cost_center                           = "1"
  region                                = "us-west-2"
  vpc_id                                = "vpc-*****"
  vpc_cidr                              = "172.16.0.0/16"
  availability_zones                    = "us-west-2a,us-west-2b,us-west-2c"
  elb_subnet_ids                        = "subnet-3b018d72,subnet-3bdcb65c,subnet-066e8b5d"
  internal_subnet_ids                   = "subnet-3b018d72,subnet-3bdcb65c,subnet-066e8b5d"
  public_key                            = "${file(format("%s/keys/%s.pub", path.cwd, var.name))}"
  root_cert                             = "${file(format("%s/certs/root-ca.pem.enc.base", path.cwd))}"
  intermediate_cert                     = "${file(format("%s/certs/intermediate-ca.pem.enc.base", path.cwd))}"
  etcd_server_cert                      = "${file(format("%s/certs/etcd-server.pem.enc.base", path.cwd))}"
  etcd_server_key                       = "${file(format("%s/certs/etcd-server-key.pem.enc.base", path.cwd))}"
  etcd_client_cert                      = "${file(format("%s/certs/etcd-client.pem.enc.base", path.cwd))}"
  etcd_client_key                       = "${file(format("%s/certs/etcd-client-key.pem.enc.base", path.cwd))}"
  etcd_peer_cert                        = "${file(format("%s/certs/etcd-peer.pem.enc.base", path.cwd))}"
  etcd_peer_key                         = "${file(format("%s/certs/etcd-peer-key.pem.enc.base", path.cwd))}"
  etcd_instance_type                    = "m3.medium"
  etcd_min_size                         = "1"
  etcd_max_size                         = "9"
  etcd_desired_capacity                 = "1"
  etcd_root_volume_size                 = "12"
  etcd_data_volume_size                 = "12"
  api_server_cert                       = "${file(format("%s/certs/apiserver.pem.enc.base", path.cwd))}"
  api_server_key                        = "${file(format("%s/certs/apiserver-key.pem.enc.base", path.cwd))}"
  controller_instance_type              = "m3.medium"
  controller_min_size                   = "1"
  controller_max_size                   = "3"
  controller_desired_capacity           = "1"
  controller_root_volume_size           = "12"
  controller_docker_volume_size         = "12"
  node_cert                             = "${file(format("%s/certs/node.pem.enc.base", path.cwd))}"
  node_key                              = "${file(format("%s/certs/node-key.pem.enc.base", path.cwd))}"
  api_server_client_cert                = "${file(format("%s/certs/apiserver-client.pem.enc.base", path.cwd))}"
  api_server_client_key                 = "${file(format("%s/certs/apiserver-client-key.pem.enc.base", path.cwd))}"
  node_instance_type                    = "m3.medium"
  node_min_size                         = "1"
  node_max_size                         = "18"
  node_desired_capacity                 = "1"
  node_root_volume_size                 = "12"
  node_docker_volume_size               = "12"
  node_data_volume_size                 = "12"
  node_logging_volume_size              = "12"
  kubernetes_hyperkube_image_repo       = "gcr.io/google_containers/hyperkube"
  kubernetes_version                    = "v1.2.4"
  kubernetes_service_cidr               = "10.3.0.1/24"
  kubernetes_dns_service_ip             = "10.3.0.10"
  kubernetes_pod_cidr                   = "10.2.0.0/16"
  bastion_security_group_id             = "sg-xxxxxxxx"
}

Note: This quoin can be used to build a k8 cluster using either the external-internal-layout quoin, or the internal-layout quoin, depending on the use case.

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| node_cert | The public certificate to be used by k8s nodes encoded in base64 format. | - | yes |
| node_key | The private key to be used by k8s nodes encoded in base64 format. | - | yes |
| api_server_client_cert | The public client certificate to be used for authenticating against k8s api server encoded in base64 format. | - | yes |
| api_server_client_key | The client private key to be used for authenticating against k8s api server encoded in base64 format. | - | yes |
| node_instance_type | The type of instance to use for the node cluster. Example: 'm3.medium' | `m3.medium` | no |
| node_min_size | The minimum size for the node cluster. | `1` | no |
| node_max_size | The maximum size for the node cluster. | `12` | no |
| node_desired_capacity | The desired capacity of the node cluster. | `1` | no |
| node_root_volume_size | Set the desired capacity for the root volume in GB. | `12` | no |
| node_docker_volume_size | Set the desired capacity for the docker volume in GB. | `12` | no |
| node_data_volume_size | Set the desired capacity for the data volume in GB. | `12` | no |
| node_logging_volume_size | Set the desired capacity for the logging volume in GB. | `12` | no |
| api_server_cert | The public certificate to be used by k8s api servers encoded in base64 format. | - | yes |
| api_server_key | The private key to be used by k8s api servers encoded in base64 format. | - | yes |
| controller_instance_type | The type of instance to use for the controller cluster. Example: 'm3.medium' | `m3.medium` | no |
| controller_min_size | The minimum size for the controller cluster. | `1` | no |
| controller_max_size | The maximum size for the controller cluster. | `3` | no |
| controller_desired_capacity | The desired capacity of the controller cluster. | `1` | no |
| controller_root_volume_size | Set the desired capacity for the root volume in GB. | `12` | no |
| controller_docker_volume_size | Set the desired capacity for the docker volume in GB. | `12` | no |
| etcd_server_cert | The public certificate to be used by etcd servers encoded in base64 format. | - | yes |
| etcd_server_key | The private key to be used by etcd servers encoded in base64 format. | - | yes |
| etcd_client_cert | The public client certificate to be used for authenticating against etcd encoded in base64 format. | - | yes |
| etcd_client_key | The client private key to be used for authenticating against etcd encoded in base64 format. | - | yes |
| etcd_peer_cert | The public certificate to be used by etcd peers encoded in base64 format. | - | yes |
| etcd_peer_key | The private key to be used by etcd peers encoded in base64 format. | - | yes |
| etcd_instance_type | The type of instance to use for the etcd cluster. Example: 'm3.medium' | `m3.medium` | no |
| etcd_min_size | The minimum size for the etcd cluster. NOTE: Use odd numbers. | `1` | no |
| etcd_max_size | The maximum size for the etcd cluster. NOTE: Use odd numbers. | `9` | no |
| etcd_desired_capacity | The desired capacity of the etcd cluster. NOTE: Use odd numbers. | `1` | no |
| etcd_root_volume_size | Set the desired capacity for the root volume in GB. | `12` | no |
| etcd_data_volume_size | Set the desired capacity for the data volume used by etcd in GB. | `12` | no |
| public_key | The public key to apply to instances in the cluster. | - | yes |
| name | The name of your quoin. | - | yes |
| region | Region where resources will be created. | - | yes |
| role_type | The role type to attach resource usage. | - | yes |
| cost_center | The cost center to attach resource usage. | - | yes |
| root_cert | The root certificate authority that all certificates belong to encoded in base64 format. | - | yes |
| intermediate_cert | The intermediate certificate authority that all certificates belong to encoded in base64 format. | - | yes |
| kubernetes_hyperkube_image_repo | The hyperkube image repository to use. | `gcr.io/google_containers/hyperkube` | no |
| kubernetes_version | The version of the hyperkube image to use. This is the tag for the hyperkube image repository | `v1.2.4` | no |
| kubernetes_service_cidr | A CIDR block that specifies the set of IP addresses to use for Kubernetes services. | `10.3.0.1/24` | no |
| kubernetes_dns_service_ip | The IP Address of the Kubernetes DNS service. NOTE: Must be contained by the Kubernetes Service CIDR. | `10.3.0.10` | no |
| kubernetes_pod_cidr | A CIDR block that specifies the set of IP addresses to use for Kubernetes pods. | `10.2.0.0/16` | no |
| vpc_id | The ID of the VPC to create the resources within. | - | yes |
| vpc_cidr | A CIDR block for the VPC that specifies the set of IP addresses to use. | - | yes |
| internet_gateway_id | The ID of the internet gateway that belongs to the VPC. | - | yes |
| availability_zones | Comma separated list of availability zones for a region. | - | yes |
| elb_subnet_ids | A comma-separated list of subnet ids to use for the instances. | - | yes |
| internal_subnet_ids | A comma-separated list of subnet ids to use for the instances. | - | yes |
| bastion_security_group_id | Reference to a security group for bastions to use. | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| bastion_security_group_id | The bastion security group ID |
| kubernetes_api_dns | The ELB DNS in which you can access the Kubernetes API. |
| key_pair_name | The name of the key pair |
| name | The name of our quoin |
| region | The region where the quoin lives |
| coreos_ami | The CoreOS AMI ID |
| availability_zones | A comma-separated list of availability zones for the network. |
| external_subnet_ids | A comma-separated list of subnet ids for the external subnets. |
| external_rtb_id | The external route table ID. |
| internal_subnet_ids | A comma-separated list of subnet ids for the internal subnets. |
| internal_rtb_ids | The internal route table ID. |

# Network

This module creates a single virtual network and routes traffic in and out of
the network by creating an internet gateway within a given region.

Usage:

```hcl
module "network" {
  source = "github.com/concur/quoins//network"
  cidr   = "172.16.0.0/16"
  name   = "prod-us-network"
}

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| cidr | A CIDR block for the network. | `172.16.0.0/16` | no |
| enable_dns_support | Enable/Disable DNS support in the VPC. | `true` | no |
| enable_dns_hostnames | Enable/Disable DNS hostnames in the VPC. | `true` | no |
| name | A name to tag the network. | `quoin-network` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | The Network ID |
| vpc_cidr | The CIDR used for the network |
| default_security_group_id | The Network Security Group ID |
| internet_gateway_id | The Internet Gateway ID |

# Security Groups

This module creates basic security groups to be used by instances.

Usage:

```hcl
module "security_groups" {
  source = "github.com/concur/quoins//security-groups"
  vpc_id = "vpc-*****"
  name   = "quoin"
}

provider "aws" {
  region = "us-west-2"
}
```

## Inputs

| Name | Description | Default | Required |
|------|-------------|:-----:|:-----:|
| name | A name to prefix security groups. | - | yes |
| vpc_id | The ID of the VPC to create the security groups on. | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| external_ssh | External SSH allows ssh connections on port 22 |
| external_win_remote | External Windows Remote allows remote connections on ports 3389, 5986, & 5985 |
