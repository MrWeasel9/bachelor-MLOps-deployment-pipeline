# terraform/outputs.tf

output "master_external_ip" {
  value = google_compute_instance.mlops_master.network_interface[0].access_config[0].nat_ip
}

output "master_internal_ip" {
  value = google_compute_instance.mlops_master.network_interface[0].network_ip
}

output "worker_1_internal_ip" {
  value = google_compute_instance.mlops_worker_1.network_interface[0].network_ip
}

output "worker_2_internal_ip" {
  value = google_compute_instance.mlops_worker_2.network_interface[0].network_ip
}
