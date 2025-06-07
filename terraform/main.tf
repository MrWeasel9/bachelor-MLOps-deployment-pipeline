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

# Kubernetes API server port
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "allow-k8s-api"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_rke2_server" {
  name    = "allow-rke2-server"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["9345"]
  }
  # Best practice: Restrict to internal communication only
  source_ranges = ["10.0.0.0/8"] # or your actual GCP subnet, e.g., ["10.186.0.0/16"]
  target_tags   = ["master"]
}


# SSH (22) from anywhere (restrict later!)
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

# Traefik NodePort (32255, for HTTP) - can add HTTPS if you want later
resource "google_compute_firewall" "allow_traefik_nodeport" {
  name    = "allow-traefik-nodeport"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["32255"]
  }
  target_tags   = ["mlops", "master"]
  source_ranges = ["0.0.0.0/0"]
}