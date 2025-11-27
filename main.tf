terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "project-29422a96-bd2f-4e5d-b3b"
  region  = "europe-west1"                  
  zone    = "europe-west1-b"                  
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 7.0" 
  
  project_id   = "project-29422a96-bd2f-4e5d-b3b"
  network_name = "app-module-vpc-network"
  routing_mode = "GLOBAL" 

  subnets = [
    {
      subnet_name   = "app-vpc-subnet"
      subnet_ip     = "10.10.0.0/24"
      subnet_region = "europe-west1"
    },
  ]
}

resource "google_compute_firewall" "ssh_http_firewall" {
  name    = "allow-ssh-http-access"
  network = module.vpc.network_name

  allow {
    protocol = "tcp"
    ports    = ["22", "80"] 
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["http-server", "ssh-server"]
}

resource "google_compute_instance" "web_server" {
  count        = 2 
  name         = "web-server-${count.index}"
  machine_type = "e2-micro"
  zone         = "europe-west1-b" 

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = module.vpc.subnets_self_links[0]
    
    access_config {
    }
  }
  
  tags = ["http-server", "ssh-server"]
}

resource "google_compute_http_health_check" "lb_health_check" {
  name               = "lb-http-health-check"
  request_path       = "/"
  check_interval_sec = 1
  timeout_sec        = 1
}

resource "google_compute_instance_group" "instance_group" {
  name    = "web-instance-group"
  zone    = "europe-west1-b"
  network = module.vpc.network_self_link

  instances = [
    for instance in google_compute_instance.web_server : instance.self_link
  ]
}

resource "google_compute_backend_service" "default" {
  name        = "web-backend-service"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 10
  health_checks = [google_compute_http_health_check.lb_health_check.self_link]

  backend {
    group = google_compute_instance_group.instance_group.self_link
  }
}

resource "google_compute_url_map" "default" {
  name            = "web-url-map"
  default_service = google_compute_backend_service.default.self_link
}

resource "google_compute_target_http_proxy" "default" {
  name    = "http-proxy"
  url_map = google_compute_url_map.default.self_link
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "http-forwarding-rule"
  target     = google_compute_target_http_proxy.default.self_link
  port_range = "80"
}

output "load_balancer_ip" {
  description = "IP addr of th HTTP Load Balancer"
  value       = google_compute_global_forwarding_rule.default.ip_address
}
