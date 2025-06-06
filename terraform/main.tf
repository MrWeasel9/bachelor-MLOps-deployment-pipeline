# terraform/main.tf

# Reserve static internal and external IPs
resource "google_compute_address" "mlops_master_external" {
  name   = "mlops-master-external-ip"
  region = var.region
}

resource "google_compute_address" "mlops_master_internal" {
  name         = "mlops-master-internal-ip"
  address_type = "INTERNAL"
  subnetwork   = "default"
  region       = var.region
}

resource "google_compute_address" "mlops_worker_1_internal" {
  name         = "mlops-worker-1-internal-ip"
  address_type = "INTERNAL"
  subnetwork   = "default"
  region       = var.region
}

resource "google_compute_address" "mlops_worker_2_internal" {
  name         = "mlops-worker-2-internal-ip"
  address_type = "INTERNAL"
  subnetwork   = "default"
  region       = var.region
}

# Master node with static internal & external IP
resource "google_compute_instance" "mlops_master" {
  name         = "mlops-master"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.boot_disk_size
    }
  }

  network_interface {
    subnetwork   = "default"
    network_ip   = google_compute_address.mlops_master_internal.address
    access_config {
      nat_ip = google_compute_address.mlops_master_external.address
    }
  }

  tags = ["mlops", "master"]

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# Worker 1 (static internal IP, ephemeral external)
resource "google_compute_instance" "mlops_worker_1" {
  name         = "mlops-worker-1"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.boot_disk_size
    }
  }

  network_interface {
    subnetwork = "default"
    network_ip = google_compute_address.mlops_worker_1_internal.address
    access_config {} # ephemeral external IP for internet access
  }

  tags = ["mlops", "worker"]

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# Worker 2 (static internal IP, ephemeral external)
resource "google_compute_instance" "mlops_worker_2" {
  name         = "mlops-worker-2"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.boot_disk_size
    }
  }

  network_interface {
    subnetwork = "default"
    network_ip = google_compute_address.mlops_worker_2_internal.address
    access_config {} # ephemeral external IP for internet access
  }

  tags = ["mlops", "worker"]

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# === FIREWALL RULES ===

# Open Kubernetes API server port to the world (change source_ranges for security later!)
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "allow-k8s-api"
  network = "default"  # Change if you use a custom VPC

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

# Allow SSH (22) from anywhere (if not already defined; consider restricting later)
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = ["mlops", "master", "worker"]
  source_ranges = ["0.0.0.0/0"]
}

# === Ports for MLflow, MinIO, JupyterHub, etc. ===

# MLflow (5000)
resource "google_compute_firewall" "allow_mlflow" {
  name    = "allow-mlflow"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["5000"]
  }

  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

# MinIO API (9000) and Console (9001)
resource "google_compute_firewall" "allow_minio" {
  name    = "allow-minio"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["9000", "9001"]
  }

  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

# JupyterHub (8000)
resource "google_compute_firewall" "allow_jupyterhub" {
  name    = "allow-jupyterhub"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

