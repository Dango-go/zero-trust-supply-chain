output "wif_provider" {
  value       = google_iam_workload_identity_pool_provider.github_provider.name
  description = "Put this into GitHub Variable: WIF_PROVIDER"
}

output "wif_service_account" {
  value       = google_service_account.gh_actions.email
  description = "Put this into GitHub Variable: WIF_SERVICE_ACCOUNT"
}

output "gar_repository_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.zero_trust.repository_id}"
  description = "Full URL of the Google Artifact Registry repository"
}

output "gcp_project_id" {
  value       = var.project_id
  description = "Put this into GitHub Variable: GCP_PROJECT_ID"
}

output "gar_location" {
  value       = var.region
  description = "Put this into GitHub Variable: GAR_LOCATION"
}

output "gar_repository_name" {
  value       = google_artifact_registry_repository.zero_trust.repository_id
  description = "Put this into GitHub Variable: GAR_REPOSITORY"
}

output "vpc_network_name" {
  value       = google_compute_network.zt_vpc.name
  description = "Name of the created VPC Network"
}

output "vpc_subnet_name" {
  value       = google_compute_subnetwork.zt_subnet.name
  description = "Name of the primary GKE Subnetwork"
}

output "gke_cluster_name" {
  value       = google_container_cluster.zt_cluster.name
  description = "Name of the GKE Cluster"
}

output "gke_get_credentials_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.zt_cluster.name} --region ${var.region} --project ${var.project_id}"
  description = "Command to connect kubectl to the cluster"
}
