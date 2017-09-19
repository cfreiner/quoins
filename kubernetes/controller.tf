/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "controller_instance_type" {
  description = "The type of instance to use for the controller cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "controller_min_size" {
  description = "The minimum size for the controller cluster."
  default     = "1"
}

variable "controller_max_size" {
  description = "The maximum size for the controller cluster."
  default     = "3"
}

variable "controller_desired_capacity" {
  description = "The desired capacity of the controller cluster."
  default     = "1"
}

variable "controller_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "controller_docker_volume_size" {
  description = "Set the desired capacity for the docker volume in GB."
  default     = "12"
}

variable "is_k8s_elb_internal" {
  description = "Specify if the k8s API is internal or external facing."
  default     = false
}

variable "controller_encrypt_docker_volume" {
  description = "Encrypt docker volume used by controller."
  default     = true
}

variable "kubedns_image_repo" {
  description = "Docker image repository for kube dns image."
  default     = "gcr.io/google_containers/kubedns-amd64"
}

variable "kubedns_version" {
  description = "Version of kubedns"
  default     = "1.8"
}

variable "kubednsmasq_image_repo" {
  description = "Docker image repository for kube dnsmasq image."
  default     = "gcr.io/google_containers/kube-dnsmasq-amd64"
}

variable "kubednsmasq_version" {
  description = "Version of kubednsmasq"
  default     = "1.4"
}

variable "exechealthz_image_repo" {
  description = "Docker image repository for exec healthz image."
  default     = "gcr.io/google_containers/exechealthz-amd64"
}

variable "exechealthz_version" {
  description = "Version of exec healthz"
  default     = "1.2"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "controller" {
  name                 = "${format("%s-controller", var.name)}"
  min_size             = "${var.controller_min_size}"
  max_size             = "${var.controller_max_size}"
  desired_capacity     = "${var.controller_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.internal_subnet_ids)}"]
  health_check_type    = "EC2"
  force_delete         = true
  load_balancers       = ["${aws_elb.kubernetes_api.id}"]
  launch_configuration = "${aws_launch_configuration.controller.name}"

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${format("%s-controller", var.name)}"
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

resource "aws_launch_configuration" "controller" {
  name_prefix          = "${format("%s-controller-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.controller_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.controller.name}"
  security_groups      = ["${aws_security_group.kubernetes.id}"]
  key_name             = "${module.key_pair.key_name}"
  depends_on           = ["aws_s3_bucket.cluster", "module.etcd", "aws_s3_bucket_object.controller", "aws_iam_instance_profile.controller", "aws_security_group.kubernetes"]

  lifecycle {
    create_before_destroy = true
  }

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.controller_root_volume_size}"
  }

  # /var/lib/docker
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = "${var.controller_encrypt_docker_volume}"
    volume_type = "gp2"
    volume_size = "${var.controller_docker_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

resource "aws_elb" "kubernetes_api" {
  name                = "${format("%s-k8s", var.name)}"
  connection_draining = true
  security_groups     = ["${aws_security_group.balancers.id}"]
  subnets             = ["${split(",", var.elb_subnet_ids)}"]
  internal            = "${var.is_k8s_elb_internal}"

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    interval            = 30
    target              = "http:8080/healthz"
    timeout             = 3
    unhealthy_threshold = 2
  }

  tags {
    Name = "${format("%s-kubernetes-api", var.name)}"
  }
}

resource "aws_security_group" "balancers" {
  name   = "${format("%s-balancers-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${format("%s-balancers", var.name)}"

    # Need to label this KubernetesCluster as well, so Kubernetes
    # knows which security group to use for ELB's.
    KubernetesCluster = "${var.name}"
  }
}

# Controller cloud-config
resource "aws_s3_bucket_object" "controller" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/controller/cloud-config.yaml"
  content = "${data.template_file.controller.rendered}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "controller" {
  name       = "${format("%s-controller-%s-%s", var.name, var.region, var.version)}"
  roles      = ["${aws_iam_role.controller.name}"]
  depends_on = ["aws_iam_role.controller", "aws_iam_role_policy.controller_policy"]
}

resource "aws_iam_role_policy" "controller_policy" {
  name       = "${format("%s-controller-policy", var.name)}"
  role       = "${aws_iam_role.controller.id}"
  policy     = "${data.template_file.controller_policy.rendered}"
  depends_on = ["aws_iam_role.controller", "data.template_file.controller_policy"]
}

resource "aws_iam_role" "controller" {
  name               = "${format("%s-controller-%s-%s", var.name, var.region, var.version)}"
  path               = "/"
  assume_role_policy = "${data.template_file.assume_role_policy.rendered}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

# Templates
data "template_file" "controller_policy" {
  template = "${file(format("%s/policies/controller-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    arn_region  = "${var.arn_region}"
  }
}

data "template_file" "controller_system_proxy" {
  template = "${file(format("%s/environment/system_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "controller_docker_proxy" {
  template = "${file(format("%s/environment/docker_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "controller_user_proxy" {
  template = "${file(format("%s/environment/user_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "controller" {
  template = "${file(format("%s/cloud-configs/controller.yaml", path.module))}"

  vars {
    name                            = "${var.name}"
    kubernetes_hyperkube_image_repo = "${var.kubernetes_hyperkube_image_repo}"
    kubernetes_version              = "${var.kubernetes_version}"
    kubedns_image_repo              = "${var.kubedns_image_repo}"
    kubedns_version                 = "${var.kubedns_version}"
    kubednsmasq_image_repo          = "${var.kubednsmasq_image_repo}"
    kubednsmasq_version             = "${var.kubednsmasq_version}"
    exechealthz_image_repo          = "${var.exechealthz_image_repo}"
    exechealthz_version             = "${var.exechealthz_version}" 
    pod_infra_image_repo            = "${var.pod_infra_image_repo}"
    pod_infra_version               = "${var.pod_infra_version}"
    kubernetes_service_cidr         = "${var.kubernetes_service_cidr}"
    kubernetes_dns_service_ip       = "${var.kubernetes_dns_service_ip}"
    kubernetes_pod_cidr             = "${var.kubernetes_pod_cidr}"
    system_proxy                    = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.controller_system_proxy.rendered : ""}"
    docker_proxy                    = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.controller_docker_proxy.rendered : ""}"
    user_proxy                      = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.controller_user_proxy.rendered : ""}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The ELB DNS in which you can access the Kubernetes API.
output "kubernetes_api_dns" {
  value = "${aws_elb.kubernetes_api.dns_name}"
}
