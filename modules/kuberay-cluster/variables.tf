# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "db_region" {
  type        = string
  description = "Cloud SQL instance region"
  default     = "us-central1"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace where resources are deployed"
  default     = "ray-system"
}

variable "enable_tpu" {
  type        = bool
  description = "Set to true to request TPUs in Ray cluster"
  default     = false
}

variable "enable_gpu" {
  type        = bool
  description = "Set to true to request GPUs in Ray cluster"
  default     = false
}

variable "autopilot_cluster" {
  type = bool
}

variable "google_service_account" {
  type        = string
  description = "Google service account name"
  default     = "kuberay-gcp-sa"
}

variable "gcs_bucket" {
  type        = string
  description = "GCS Bucket name"
}

variable "grafana_host" {
  type = string
}

# Commenting out underutilized, nested variables because they're harder to
# strip from the YAML encoding. Add these back if we can easily strip out
# the null values.
variable "security_context" {
  description = "Kubernetes security context to set on all ray cluster pods"
  type = object({
    allowPrivilegeEscalation = optional(bool)
    capabilities = optional(object({
      # Not typically used
      # add  = optional(list(string))
      drop = optional(list(string))
    }))
    privileged             = optional(bool)
    procMount              = optional(string)
    readOnlyRootFilesystem = optional(bool)
    runAsGroup             = optional(number)
    runAsNonRoot           = optional(bool)
    runAsUser              = optional(number)
    seLinuxOptions = optional(object({
      level = optional(string)
      role  = optional(string)
      type  = optional(string)
      user  = optional(string)
    }))
    seccompProfile = optional(object({
      # Not typically used
      # localhostProfile = optional(string)
      type = optional(string)
    }))
    windowsOptions = optional(object({
      gmsaCredentialSpec    = optional(string)
      gmsaCredentiaSpecName = optional(string)
      hostProcess           = bool
      runAsUserName         = string
    }))
  })

  default = {
    allowPrivilegeEscalation = false
    capabilities = {
      drop = ["ALL"]
    }
    # GKE will automatically mount GPUs and TPUs into unprivileged pods
    privileged         = false
    readOnlyFileSystem = true
    runAsNonRoot       = true
    seccompProfile = {
      type = "RuntimeDefault"
    }
  }
}

variable "db_secret_name" {
  type        = string
  description = "CloudSQL user credentials"
  default     = "empty-secret"
}
