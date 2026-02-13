output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "artifact_registry_repository" {
  value = google_artifact_registry_repository.main.repository_id
}

output "gke_cluster_name" {
  value = google_container_cluster.main.name
}

output "deployment_id" {
  value = random_id.deployment.hex
}

output "vpc_name" {
  value = google_compute_netwrok.main.name
}
