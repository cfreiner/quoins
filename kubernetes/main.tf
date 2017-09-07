/**
* This module creates an opinionated [Kubernetes][kubernetes] cluster in AWS. Currently, this
* quoin only supports the AWS provider and has only been tested in the us-west-2 and eu-central-1
* regions.
*
* Although terraform is capable of maintaining and altering state of infrastructure, this Quoin is
* only intended to stand up new clusters. Please do not attempt to alter the configuration of
* existing clusters. We treat our clusters as immutable resources.
*
* [kubernetes]: http://kubernetes.io
*
* The way the cluster is provisioned is by using Terraform configs to create the
* appropriate resources in AWS. From that point, we use CoreOS, Auto Scaling Groups
* with Launch Configurations to launch the Kubernetes cluster. The cluster is launched in
* an air gapped way using only AWS API's, therefore, by default, there isn't a way to SSH
* directly to an instance without a bastion. We use our Bastion Quoin to launch on-demand
* bastions when the need arises. Currently we launch version 1.2.4 of Kubernetes.
*
* ## What's Inside
*
* * One public subnet and one private subnet in each availability zone.
* * Subnets are dynamic and react to the number of availability zones within the region.
* * A NAT gateway in each availability zone.
* * Reference to a security group for bastions to use.
* * CoreOS is used as the host operating system for all instances.
* * The certificates are used to completely secure the communication between etcd, controllers, and nodes.
* * Creates a dedicated etcd cluster within the private subnets using an auto scaling group.
*   * EBS Volumes:
*     * Root block store device
*     * Encrypted block store for etcd data mounted at /var/lib/etcd2
* * Creates a Kubernetes control plane within the private subnets using an auto scaling group.
*   * An ELB attached to each instance to allow external access to the API.
*   * EBS Volumes:
*     * Root block store device
*     * Encrypted block store for Docker mounted at /var/lib/docker
* * Creates a Kubernetes nodes within the private subnets using an auto scaling group.
*   * EBS Volumes:
*     * Root block store device
*     * Encrypted block store for Docker mounted at /var/lib/docker
*     * Encrypted block store for data mounted at /opt/data
*     * Encrypted block store for logging mounted at /opt/logging
* * Systemd timer to garbage collect docker images and containers daily.
* * Systemd timer to logrotate docker logs hourly.
* * Creates an ssh key pair for the cluster using the passed in public key.
* * s3 bucket for the cluster where configs are saved for ASG and also allows the cluster to use it for backups.
* * IAM roles to give instances permission to access resources based on their role
* * Fluent/ElasticSearch/Kibana runs within the cluster to ship all logs to a central location. Only thing needed by the developer is to log to stdout or stderr.
*
* ## Note
*
* __The TLS assets that you supply, must be encrypted with the supplied KMS Key ARN and encoded with base64.__
*
* Example:
*
* ```
* aws --region us-west-2 kms encrypt \
*    --key-id 709b95f1-90b0-46d3-b1d3-619fb4dfb82a \
*    --plaintext fileb://$PWD/root-ca.pem \
*    --output text --query CiphertextBlob > "root-ca.pem.enc.base"
* ```
*
* Usage:
*
* ```hcl
* module "kubernetes" {
*   source                                = "github.com/concur/quoins//kubernetes"
*   name                                  = "prod"
*   role_type                             = "app1"
*   cost_center                           = "1"
*   region                                = "us-west-2"
*   vpc_id                                = "vpc-1234565"
*   vpc_cidr                              = "172.16.0.0/16"
*   availability_zones                    = "us-west-2a,us-west-2b,us-west-2c"
*   elb_subnet_ids                        = "subnet-3b018d72,subnet-3bdcb65c,subnet-066e8b5d"
*   internal_subnet_ids                   = "subnet-3b018d72,subnet-3bdcb65c,subnet-066e8b5d"
*   public_key                            = "${file(format("%s/keys/%s.pub", path.cwd, var.name))}"
*   tls_provision                         = "${file(format("%s/../provision.sh", path.cwd))}"
*   etcd_instance_type                    = "m3.medium"
*   etcd_min_size                         = "1"
*   etcd_max_size                         = "9"
*   etcd_desired_capacity                 = "1"
*   etcd_root_volume_size                 = "12"
*   etcd_data_volume_size                 = "12"
*   controller_instance_type              = "m3.medium"
*   controller_min_size                   = "1"
*   controller_max_size                   = "3"
*   controller_desired_capacity           = "1"
*   controller_root_volume_size           = "12"
*   controller_docker_volume_size         = "12"
*   node_instance_type                    = "m3.medium"
*   node_min_size                         = "1"
*   node_max_size                         = "18"
*   node_desired_capacity                 = "1"
*   node_root_volume_size                 = "12"
*   node_docker_volume_size               = "12"
*   node_data_volume_size                 = "12"
*   node_logging_volume_size              = "12"
*   kubernetes_hyperkube_image_repo       = "quay.io/coreos/hyperkube"
*   kubernetes_version                    = "v1.6.2_coreos.0"
*   kubernetes_service_cidr               = "10.3.0.1/24"
*   kubernetes_dns_service_ip             = "10.3.0.10"
*   kubernetes_pod_cidr                   = "10.2.0.0/16"
*   bastion_security_group_id             = "sg-xxxxxxxx"
* }
*
* provider "aws" {
*   region = "us-west-2"
* }
* ```
*
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "The name of your quoin."
}

variable "version" {
  description = "The version number of your infrastructure, used to aid in zero downtime deployments of new infrastructure."
  default     = "latest"
}

variable "region" {
  description = "Region where resources will be created."
}

variable "role_type" {
  description = "The role type to attach resource usage."
}

variable "cost_center" {
  description = "The cost center to attach resource usage."
}

variable "tls_provision" {
  description = "The TLS ca and assets provision script."
}

variable "kubernetes_hyperkube_image_repo" {
  description = "The hyperkube image repository to use."
  default     = "quay.io/coreos/hyperkube"
}

variable "kubernetes_version" {
  description = "The version of the hyperkube image to use. This is the tag for the hyperkube image repository"
  default     = "v1.6.2_coreos.0"
}

variable "kubernetes_service_cidr" {
  description = "A CIDR block that specifies the set of IP addresses to use for Kubernetes services."
  default     = "10.3.0.1/24"
}

variable "kubernetes_dns_service_ip" {
  description = "The IP Address of the Kubernetes DNS service. NOTE: Must be contained by the Kubernetes Service CIDR."
  default     = "10.3.0.10"
}

variable "kubernetes_pod_cidr" {
  description = "A CIDR block that specifies the set of IP addresses to use for Kubernetes pods."
  default     = "10.2.0.0/16"
}

variable "bastion_security_group_id" {
  description = "Security Group ID for bastion instance with external SSH allows ssh connections on port 22"
}

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "vpc_cidr" {
  description = "A CIDR block for the VPC that specifies the set of IP addresses to use."
}

variable "availability_zones" {
  description = "Comma separated list of availability zones for a region."
}

variable "elb_subnet_ids" {
  description = "A comma-separated list of subnet ids to use for the k8s API."
}

variable "internal_subnet_ids" {
  description = "A comma-separated list of subnet ids to use for the instances."
}

variable "assume_role_principal_service" {
  description = "Principal service used for assume role policy. More information can be found at https://docs.aws.amazon.com/general/latest/gr/rande.html#iam_region."
  default     = "ec2.amazonaws.com"
}

variable "arn_region" {
  description = "Amazon Resource Name based on region, aws for most regions and aws-cn for Beijing"
  default = "aws"  
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Kubernetes Security Group
resource "aws_security_group" "kubernetes" {
  name       = "${format("%s-kubernetes-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id     = "${var.vpc_id}"
  depends_on = ["aws_security_group.balancers"]

  # All any traffic with this security group
  # Allows controllers to talk to controllers
  # Allows controllers to talk to nodes
  # Allows nodes to talk to nodes
  # Allows nodes to talk to controllers
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow SSH from the bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${var.bastion_security_group_id}"]
  }

  # Allow HTTP traffic from load balancers
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = ["${aws_security_group.balancers.id}"]
  }

  # Allow HTTP traffic to port 8080 from load balancers. Used for health check
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = ["${aws_security_group.balancers.id}"]
  }

  # Allow HTTPS traffic from load balancers
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.balancers.id}"]
  }

  # Allow connections to kubernetes services from load balancers
  # The default port range is: 30000-32767
  ingress {
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = ["${aws_security_group.balancers.id}"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name              = "${format("%s-kubernetes", var.name)}"
    KubernetesCluster = "${var.name}"
  }
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Certificates Provision Script
resource "aws_s3_bucket_object" "tls_provision" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/tls-provision.sh"
  content = "${var.tls_provision}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

data "template_file" "s3_cloudconfig_bootstrap" {
  template = "${file(format("%s/bootstrapper/s3-cloudconfig-bootstrap.sh", path.module))}"

  vars {
    name = "${var.name}"
  }
}

# Latest stable CoreOS AMI
data "aws_ami" "coreos_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CoreOS-stable-*-hvm"]
  }
}

data "template_file" "assume_role_policy" {
  template = "${file(format("%s/policies/assume-role-policy.json", path.module))}"

  vars {
    assume_role_principal_service = "${var.assume_role_principal_service}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The name of our quoin
output "name" {
  value = "${var.name}"
}

# The region where the quoin lives
output "region" {
  value = "${var.region}"
}

# The CoreOS AMI ID
output "coreos_ami" {
  value = "${data.aws_ami.coreos_ami.id}"
}
