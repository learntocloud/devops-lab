terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "google_compute_netwrok" "main" {
  name                    = "vpc-devopslab-${random_id.deployment.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = "snet-gke"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_netwrok.main.id
}

resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = "devopslab-${random_id.deployment.hex}"
  description   = "DevOps Lab container registry"
  format        = "DOCKER"
}

resource "google_container_cluster" "main" {
  name               = "gke-devopslab-${random_id.deployment.hex}"
  location           = var.zone
  initial_node_count = 1

  network    = google_compute_netwrok.main.name
  subnetwork = google_compute_subnetwork.gke.name

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.1.0.0/16"
    services_ipv4_cidr_block = "10.1.0.0/20"
  }

  deletion_protection = false
}

resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes-${random_id.deployment.hex}"
  display_name = "GKE node pool service account"
}

resource "google_container_node_pool" "primary" {
  name       = "primary-nodes"
  location   = var.zone
  cluster    = google_container_cluster.main.name
  node_count = 1

  node_config {
    machine_type    = "e2-standard-2"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

resource "google_project_iam_member" "gke_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregsitry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
