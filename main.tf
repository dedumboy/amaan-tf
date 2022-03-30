# Configure the Alicloud Provider
provider "alicloud" {
  access_key = ""
  secret_key = ""
  region     = "ap-southeast-1"
}

resource "alicloud_vpc" "irsyad_vpc" {
  vpc_name = "irsyad-vpc"
  cidr_block = "192.168.0.0/16"
}

resource "alicloud_vswitch" "irsyad_vswitch" {
  vswitch_name = "irsyad-vswitch"
  zone_id = "ap-southeast-1a"
  cidr_block = "192.168.1.0/24"
  vpc_id = "${alicloud_vpc.irsyad_vpc.id}"
}

// Security group and rule
resource "alicloud_security_group" "app_security_group" {
  vpc_id = "${alicloud_vpc.irsyad_vpc.id}"
}

resource "alicloud_security_group_rule" "accept_8080_rule" {
  type = "ingress"
  ip_protocol = "tcp"
  nic_type = "intranet"
  policy = "accept"
  port_range = "8080/8080"
  priority = 1
  security_group_id = "${alicloud_security_group.app_security_group.id}"
  cidr_ip = "0.0.0.0/0"
}

resource "alicloud_slb_load_balancer" "slb" {
  load_balancer_name       = "app-slb"
  vswitch_id = alicloud_vswitch.irsyad_vswitch.id
  address_type       = "intranet"
  load_balancer_spec = "slb.s1.small"
}

data "alicloud_instance_types" "default" {
  availability_zone = "ap-southeast-1a"
}

data "alicloud_images" "default" {
  name_regex  = "^ubuntu_18.*64"
  most_recent = true
  owners      = "system"
}

resource "alicloud_instance" "ecs_instance" {
  image_id          = data.alicloud_images.default.images[0].id
  instance_type     = data.alicloud_instance_types.default.instance_types[0].id
  availability_zone = "ap-southeast-1a"
  security_groups   = [alicloud_security_group.app_security_group.id]
  vswitch_id        = alicloud_vswitch.irsyad_vswitch.id
  instance_name     = "irsyad-ecs"
  password          = "testrootpassword"
  user_data         = "${file("user-data")}"
}

resource "alicloud_slb_listener" "app_slb_listener_http" {
  load_balancer_id = "${alicloud_slb_load_balancer.slb.id}"

  backend_port = 8080
  frontend_port = 80
  bandwidth = 3
  protocol = "http"

  health_check = "on"
  health_check_type = "http"
  health_check_connect_port = 8080
  health_check_uri = "/health"
  health_check_http_code = "http_2xx"
}

resource "alicloud_eip_address" "eip" {
}

resource "alicloud_eip_association" "eip_asso" {
  allocation_id = alicloud_eip_address.eip.id
  instance_id   = alicloud_slb_load_balancer.slb.id
}

resource "alicloud_ess_scaling_group" "default" {
  min_size           = 1
  max_size           = 2
  scaling_group_name = "irsyad-autoscale-group"
  removal_policies   = ["OldestInstance", "NewestInstance"]
  vswitch_ids        = [alicloud_vswitch.irsyad_vswitch.id]
}

resource "alicloud_ess_scaling_configuration" "default" {
  scaling_group_id  = alicloud_ess_scaling_group.default.id
  instance_name     = "irsyad-ecs"
  security_group_id = alicloud_security_group.app_security_group.id
  force_delete      = true
  active            = true
}
