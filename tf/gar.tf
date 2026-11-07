# Enable Artifact Registry API in GCP project
resource "google_project_service" "artifactregistry" {
  project                    = var.project_id
  service                    = "artifactregistry.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Also ensure IAM Credentials API is enabled for WIF token exchange
resource "google_project_service" "iamcredentials" {
  project                    = var.project_id
  service                    = "iamcredentials.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# The Artifact Registry Docker Repository
resource "google_artifact_registry_repository" "zero_trust" {
  depends_on = [google_project_service.artifactregistry]

  project       = var.project_id
  location      = var.region
  repository_id = var.gar_repository_id
  description   = "Zero-Trust Supply Chain OCI registry for signed images, SBOMs, and attestations"
  format        = "DOCKER"

  # Immutable tags: Prevents overwriting existing image tags (Strict Zero-Trust practice)
  docker_config {
    immutable_tags = true
  }

  labels = {
    environment = "production"
    managed-by  = "terraform"
    security    = "zero-trust"
  }
}

# Optional: Public read access for admission verification & Kind cluster pulling
# In Zero-Trust, public pulling is safe because every image MUST be cryptographically verified by Kyverno.
resource "google_artifact_registry_repository_iam_member" "public_reader" {
  count = var.gar_public_readable ? 1 : 0

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.zero_trust.name
  role       = "roles/artifactregistry.reader"
  member     = "allUsers"
}
