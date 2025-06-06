variable "credentials_file" { default = "jenkins-terraform-key.json" }
variable "project"         { default = "bachelors-project-461620" }
variable "region"          { default = "europe-central2" }
variable "zone"            { default = "europe-central2-a" }

variable "machine_type"    { default = "e2-medium" }
variable "boot_disk_size"  { default = 40 }
variable "ubuntu_image"    { default = "ubuntu-os-cloud/ubuntu-2204-lts" }
