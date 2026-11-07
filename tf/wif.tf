resource "google_service_account" "gh_actions" {
  account_id   = "gh-actions-image-releaser"
  display_name = "GitHub Actions Image Releaser"
}
# Role for Artifact Registry
resource "google_project_iam_member" "gar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer" # push / pull artifacts, signing 
  member  = "serviceAccount:${google_service_account.gh_actions.email}"
}
# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-pool" # resource id
  display_name              = "GitHub Actions Pool for WIF"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider" # resource id
  display_name                       = "GitHub Actions Provider"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository == '${var.github_repo}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com" # url of public keys to decrypt oidc token
  }
}
# Access for GitHub impersonate this sa
resource "google_service_account_iam_member" "wif_user" {
  service_account_id = google_service_account.gh_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}
 