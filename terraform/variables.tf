// Variables to use accross the project
// which can be accessed by var.project_id
variable "project_id" {
  description = "The project ID to host the cluster in"
  default     = "tensile-axiom-482205-g8"
}

variable "region" {
  description = "The region the cluster in"
  default     = "asia-southeast1"
}

variable "bucket" {
  description = "GCS bucket for MLE course"
  default     = "bucket-aide1-k8-khoa-nguyen-424"
}