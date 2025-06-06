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
