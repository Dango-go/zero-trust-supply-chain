variable "project_id" {
  type        = string
  description = "GCP Project ID (e.g. security-supply-chain)"
}

variable "region" {
  type        = string
  default     = "europe-west1" # St. Ghislain
  description = "Primary GCP region for resources and Artifact Registry"
}

variable "github_repo" {
  type        = string
  default     = "your-username/zero-trust-supply-chain"
  description = "GitHub repo in owner/repo format (e.g. bodya/zero-trust-supply-chain)"
}

variable "gar_repository_id" {
  type        = string
  default     = "zero-trust"
  description = "Artifact Registry Docker repository ID"
}

variable "gar_public_readable" {
  type        = bool
  default     = true
  description = "Allow public pull of images (recommended for Kind / external admission testing; zero-trust relies on cryptographic verification)"
}

variable "gke_machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "Machine type for GKE nodes (4 vCPU, 16 GB RAM required for HA security stack)"
}

variable "gke_node_count" {
  type        = number
  default     = 3
  description = "Initial number of worker nodes in the GKE node pool"
}
