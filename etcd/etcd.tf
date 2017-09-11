/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "subnet_ids" {
  description = "A comma-separated list of subnet ids to use for the instances."
}

variable "etcd_instance_type" {
  description = "The type of instance to use for the etcd cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "etcd_min_size" {
  description = "The minimum size for the etcd cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "etcd_max_size" {
  description = "The maximum size for the etcd cluster. NOTE: Use odd numbers."
  default     = "9"
}

variable "etcd_desired_capacity" {
  description = "The desired capacity of the etcd cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "etcd_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "etcd_data_volume_size" {
  description = "Set the desired capacity for the data volume used by etcd in GB."
  default     = "12"
}

variable "key_name" {
  description = "A name for the given key pair to use for instances."
}

variable "bastion_security_group_id" {
  description = "Security Group ID for bastion instance with external SSH allows ssh connections on port 22"
}

variable "etcd_encrypt_data_volume" {
  description = "Encrypt data volume used by etcd."
  default     = "true"
}

variable "system_environment" {
  description = "Environment variables to be used system wide."
  default     = ""
}

variable "docker_environment" {
  description = "Environment variables to be used by Docker."
  default     = ""
}

variable "user_environment" {
  description = "Environment variables to be used by the user."
  default     = ""
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "etcd" {
  name                 = "${format("%s", var.name)}"
  min_size             = "${var.etcd_min_size}"
  max_size             = "${var.etcd_max_size}"
  desired_capacity     = "${var.etcd_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.subnet_ids)}"]
  health_check_type    = "EC2"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.etcd.name}"

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${format("%s", var.name)}"
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
}

resource "aws_launch_configuration" "etcd" {
  name_prefix          = "${format("%s-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.etcd_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.etcd.name}"
  security_groups      = ["${aws_security_group.etcd.id}"]
  key_name             = "${var.key_name}"
  depends_on           = ["aws_s3_bucket.cluster", "aws_s3_bucket_object.etcd", "aws_iam_instance_profile.etcd", "aws_security_group.etcd"]

  lifecycle {
    create_before_destroy = true
  }

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.etcd_root_volume_size}"
  }

  # /var/lib/etcd
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = "${var.etcd_encrypt_data_volume}"
    volume_type = "gp2"
    volume_size = "${var.etcd_data_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

# Security Group
resource "aws_security_group" "etcd" {
  name       = "${format("%s-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id     = "${var.vpc_id}"

  # Allow SSH from the bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${var.bastion_security_group_id}"]
  }

  # Allow etcd peers to communicate, include etcd proxies
  ingress {
    from_port   = 2380
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # Allow etcd clients to communicate
  ingress {
    from_port   = 2379
    to_port     = 2379
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${format("%s", var.name)}"
  }
}

# Etcd cloud-config
resource "aws_s3_bucket_object" "etcd" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/etcd/cloud-config.yaml"
  content = "${data.template_file.etcd.rendered}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "etcd" {
  name       = "${format("%s-%s-%s", var.name, var.region, var.version)}"
  roles      = ["${aws_iam_role.etcd.name}"]
  depends_on = ["aws_iam_role.etcd", "aws_iam_role_policy.etcd_policy"]
}

resource "aws_iam_role_policy" "etcd_policy" {
  name       = "${format("%s-policy", var.name)}"
  role       = "${aws_iam_role.etcd.id}"
  policy     = "${data.template_file.etcd_policy.rendered}"
  depends_on = ["aws_iam_role.etcd", "data.template_file.etcd_policy"]
}

resource "aws_iam_role" "etcd" {
  name               = "${format("%s-%s-%s", var.name, var.region, var.version)}"
  path               = "/"
  assume_role_policy = "${data.template_file.assume_role_policy.rendered}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

# Templates
data "template_file" "etcd_policy" {
  template = "${file(format("%s/policies/etcd-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    arn_region  = "${var.arn_region}"
  }
}

data "template_file" "etcd" {
  template = "${file(format("%s/cloud-configs/etcd.yaml", path.module))}"

  vars {
    system_environment = "${var.system_environment}"
    docker_environment = "${var.docker_environment}"
    user_environment   = "${var.user_environment}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

