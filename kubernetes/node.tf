/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "node_cert" {
  description = "The public certificate to be used by k8s nodes encoded in base64 format."
}

variable "node_key" {
  description = "The private key to be used by k8s nodes encoded in base64 format."
}

variable "api_server_client_cert" {
  description = "The public client certificate to be used for authenticating against k8s api server encoded in base64 format."
}

variable "api_server_client_key" {
  description = "The client private key to be used for authenticating against k8s api server encoded in base64 format."
}

variable "node_instance_type" {
  description = "The type of instance to use for the node cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "node_min_size" {
  description = "The minimum size for the node cluster."
  default     = "1"
}

variable "node_max_size" {
  description = "The maximum size for the node cluster."
  default     = "12"
}

variable "node_desired_capacity" {
  description = "The desired capacity of the node cluster."
  default     = "1"
}

variable "node_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "node_docker_volume_size" {
  description = "Set the desired capacity for the docker volume in GB."
  default     = "12"
}

variable "node_data_volume_size" {
  description = "Set the desired capacity for the data volume in GB."
  default     = "12"
}

variable "node_logging_volume_size" {
  description = "Set the desired capacity for the logging volume in GB."
  default     = "12"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "node" {
  name                 = "${format("%s-node", var.name)}"
  min_size             = "${var.node_min_size}"
  max_size             = "${var.node_max_size}"
  desired_capacity     = "${var.node_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${aws_subnet.internal.*.id}"]
  health_check_type    = "EC2"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.node.name}"

  tag {
    key                 = "Name"
    value               = "${format("%s-node", var.name)}"
    propagate_at_launch = true
  }

  tag {
    key                 = "RoleType"
    value               = "${var.role_type}"
    propagate_at_launch = true
  }

  tag {
    key                 = "CostCenter"
    value               = "${var.cost_center}"
    propagate_at_launch = true
  }

  tag {
    key                 = "KubernetesCluster"
    value               = "${var.name}"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "node" {
  name_prefix          = "${format("%s-node-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.node_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.node.name}"
  security_groups      = ["${aws_security_group.kubernetes.id}"]
  key_name             = "${module.key_pair.key_name}"
  depends_on           = ["aws_subnet.internal", "aws_s3_bucket.cluster", "aws_autoscaling_group.controller", "aws_launch_configuration.controller", "aws_s3_bucket_object.node", "aws_iam_instance_profile.node", "aws_security_group.kubernetes"]

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.node_root_volume_size}"
  }

  # /var/lib/docker
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.node_docker_volume_size}"
  }

  # /opt/data
  ebs_block_device = {
    device_name = "/dev/sdg"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.node_data_volume_size}"
  }

  # /opt/logging
  ebs_block_device = {
    device_name = "/dev/sdh"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.node_logging_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

# Node cloud-config
resource "aws_s3_bucket_object" "node" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/cloud-config.yaml"
  content = "${data.template_file.node.rendered}"
}

# Certificates
resource "aws_s3_bucket_object" "node_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/tls/node.pem.enc.base"
  content = "${var.node_cert}"
}

resource "aws_s3_bucket_object" "node_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/tls/node-key.pem.enc.base"
  content = "${var.node_key}"
}

resource "aws_s3_bucket_object" "api_server_client_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/tls/api-server-client.pem.enc.base"
  content = "${var.api_server_client_cert}"
}

resource "aws_s3_bucket_object" "api_server_client_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/tls/api-server-client-key.pem.enc.base"
  content = "${var.api_server_client_key}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "node" {
  name       = "${format("%s-node", var.name)}"
  roles      = ["${aws_iam_role.node.name}"]
  depends_on = ["aws_iam_role.node", "aws_iam_role_policy.node_policy"]
}

resource "aws_iam_role_policy" "node_policy" {
  name       = "${format("%s-node-policy", var.name)}"
  role       = "${aws_iam_role.node.id}"
  policy     = "${data.template_file.node_policy.rendered}"
  depends_on = ["aws_iam_role.node", "data.template_file.node_policy"]
}

resource "aws_iam_role" "node" {
  name               = "${format("%s-node", var.name)}"
  path               = "/"
  assume_role_policy = "${file(format("%s/policies/assume-role-policy.json", path.module))}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

# Templates
data "template_file" "node_policy" {
  template = "${file(format("%s/policies/node-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    kms_key_arn = "${var.kms_key_arn}"
  }
}

data "template_file" "node" {
  template = "${file(format("%s/cloud-configs/node.yaml", path.module))}"

  vars {
    kubernetes_api_dns_name         = "${aws_elb.kubernetes_api.dns_name}"
    kubernetes_dns_service_ip       = "${var.kubernetes_dns_service_ip}"
    kubernetes_hyperkube_image_repo = "${var.kubernetes_hyperkube_image_repo}"
    kubernetes_version              = "${var.kubernetes_version}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

