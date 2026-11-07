resource "google_project_service" "compute" {
  project                    = var.project_id
  service                    = "compute.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_compute_network" "zt_vpc" {
  depends_on = [google_project_service.compute]

  name                    = "zt-vpc"
  auto_create_subnetworks = false # only manual subnet creation
  routing_mode            = "REGIONAL"
  description             = "Custom VPC for Zero-Trust Supply Chain Platform"
}

resource "google_compute_subnetwork" "zt_subnet" {
  name                     = "zt-subnet-${var.region}"
  ip_cidr_range            = "10.10.0.0/20" # Primary range for GKE Nodes (4096 IPs)
  region                   = var.region
  network                  = google_compute_network.zt_vpc.id
  private_ip_google_access = true  
  # Secondary IP range dedicated for Kubernetes Pods
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.20.0.0/16" # 65536 Pod IPs
  }

  # Secondary IP range dedicated for Kubernetes Services (ClusterIPs)
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.30.0.0/20" # 4096 Service IPs
  }
}


resource "google_compute_router" "zt_router" {
  name    = "zt-router-${var.region}"
  region  = var.region
  network = google_compute_network.zt_vpc.name
}


resource "google_compute_router_nat" "zt_nat" {
  name                               = "zt-nat-${var.region}"
  router                             = google_compute_router.zt_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}


resource "google_compute_firewall" "allow_internal" {
  name        = "zt-allow-internal"
  network     = google_compute_network.zt_vpc.name
  description = "Allow internal traffic between nodes, pods, and services"
  priority    = 1000

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    "10.10.0.0/20", # Nodes
    "10.20.0.0/16", # Pods
    "10.30.0.0/20"  # Services
  ]
}

# Allow Google Cloud Health Checks and Master nodes (Control Plane) to communicate with webhooks
resource "google_compute_firewall" "allow_health_checks" {
  name        = "zt-allow-health-checks"
  network     = google_compute_network.zt_vpc.name
  description = "Allow Google Cloud Load Balancer and Master nodes health checks"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["443", "10250", "8080", "9443"] # Kyverno & Kubelet admission ports
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
}
