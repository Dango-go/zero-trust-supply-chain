# Enable Kubernetes Engine API
resource "google_project_service" "container" {
  project                    = var.project_id
  service                    = "container.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Dedicated Least-Privilege Service Account for GKE Nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Pool Service Account (Minimal Permissions)"
}

# Standard least-privilege roles for GKE nodes
resource "google_project_iam_member" "node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Allow GKE nodes to pull images from Google Artifact Registry
resource "google_project_iam_member" "node_gar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Hardened Private GKE Cluster Control Plane
resource "google_container_cluster" "zt_cluster" {
  depends_on = [google_project_service.container]

  name     = "zt-cluster"
  location = var.region

  # We use a custom, independently managed node pool below
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network bindings (uses our isolated VPC & Subnet)
  network    = google_compute_network.zt_vpc.name
  subnetwork = google_compute_subnetwork.zt_subnet.name

  # VPC-Native Cluster configuration (Secondary IP ranges from vpc.tf)
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Zero-Trust Networking: Cilium-powered GKE Datapath v2
  datapath_provider = "ADVANCED_DATAPATH" # Enables high-performance eBPF routing and network policy enforcement (K8s NetworkPolicy, CiliumNetworkPolicy)

  # Workload Identity: Seamless, keyless authentication from pods to Google Cloud APIs
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private Cluster Configuration (Nodes have NO public IPs)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Keep endpoint accessible via authorized networks / cloud shell
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Shielded Nodes: Cryptographic verification of node identity and boot integrity
  enable_shielded_nodes = true

  # Release channel: Regular for stable security patches
  release_channel {
    channel = "REGULAR"
  }

  # Disable basic auth & client certs (Zero-Trust authentication)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Add-ons configuration
  addons_config {
    http_load_balancing {
      disabled = false
    }
    # Horizontal Pod Autoscaling
    horizontal_pod_autoscaling {
      disabled = false
    }
    # GCS Fuse CSI driver (useful for audit evidence/logs)
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # Maintenance window (Weekends)
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T00:00:00Z"
      end_time   = "2026-01-01T04:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }
}

# GKE Node Pool with eBPF and Security Hardening
resource "google_container_node_pool" "zt_nodes" {
  name       = "zt-node-pool"
  location   = var.region
  cluster    = google_container_cluster.zt_cluster.name
  node_count = var.gke_node_count

  # Autoscaling settings
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }

  # Node management: auto repair and auto upgrade
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    # e2-standard-4 (4 vCPU, 16 GB RAM) - optimal for Cilium, Kyverno HA, Vault & Falco eBPF
    machine_type = var.gke_machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Minimal least-privilege SA
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Container-Optimized OS with containerd (Supports modern eBPF BTF for Falco)
    image_type = "COS_CONTAINERD"

    # Shielded VM features
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Node metadata configuration for Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = "production"
      node-tier   = "worker"
      security    = "zero-trust"
    }

    tags = ["gke-node", "zt-cluster"]
  }
}
