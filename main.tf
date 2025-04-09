terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.51.0"
    }
  }
}

provider "openstack" {
  auth_url    = "https://api.pub1.infomaniak.cloud/identity/v3"
  region      = "dc3-a"
  tenant_name = "project_test"
}
# Trouver une image
data "openstack_images_image_v2" "ubuntu" {
  name_regex  = "(?i)ubuntu.*22.04"
  most_recent = true
}

# Trouver un type d'instance
data "openstack_compute_flavor_v2" "small" {
  name = "a1-ram2-disk20-perf1"
}

# Créer une paire de clés SSH
resource "openstack_compute_keypair_v2" "terraform_key" {
  name = "terraform-key"
}

# Créer une instance
resource "openstack_compute_instance_v2" "web_server" {
  name            = "web-server"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_id       = data.openstack_compute_flavor_v2.small.id
  key_pair        = openstack_compute_keypair_v2.terraform_key.name
  security_groups = ["default"]

  network {
    name = "ext-net1"
  }
}

# Afficher l'adresse IP de l'instance
output "instance_ip" {
  value = openstack_compute_instance_v2.web_server.access_ip_v4
}
resource "openstack_blockstorage_volume_v3" "data_volume" {
  name        = "data-volume"
  size        = 50
  volume_type = "ssd"
}

# Attacher le volume à l'instance
resource "openstack_compute_volume_attach_v2" "attach_volume" {
  instance_id = openstack_compute_instance_v2.web_server.id
  volume_id   = openstack_blockstorage_volume_v3.data_volume.id
}
resource "openstack_networking_secgroup_v2" "web_secgroup" {
  name        = "web-secgroup"
  description = "Security group for web servers"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "http_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web_secgroup.id
}
resource "openstack_networking_network_v2" "private_network" {
  name           = "private-network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name       = "private-subnet"
  network_id = openstack_networking_network_v2.private_network.id
  cidr       = "192.168.1.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "router" {
  name           = "my-router"
  admin_state_up = true
  external_network_id = "ext-net1-v4subnet2"
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.private_subnet.id
}
resource "openstack_lb_loadbalancer_v2" "lb" {
  name          = "web-loadbalancer"
  vip_subnet_id = openstack_networking_subnet_v2.private_subnet.id
}

resource "openstack_lb_listener_v2" "http_listener" {
  name            = "http-listener"
  protocol        = "HTTP"
  protocol_port   = 80
  loadbalancer_id = openstack_lb_loadbalancer_v2.lb.id
}

resource "openstack_lb_pool_v2" "http_pool" {
  name        = "http-pool"
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.http_listener.id
}

resource "openstack_lb_member_v2" "web_member" {
  pool_id       = openstack_lb_pool_v2.http_pool.id
  address       = openstack_compute_instance_v2.web_server.access_ip_v4
  protocol_port = 80
}
