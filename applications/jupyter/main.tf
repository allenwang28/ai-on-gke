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

provider "google" {
  project = var.project_id
}
provider "google-beta" {
  project = var.project_id
}

data "google_client_config" "default" {}

data "google_project" "project" {
  project_id = var.project_id
}

module "infra" {
  source = "../../infrastructure"
  count  = var.create_cluster ? 1 : 0

  project_id        = var.project_id
  cluster_name      = var.cluster_name
  cluster_location  = var.cluster_location
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = false
  network_name      = "default"
  subnetwork_name   = "default"
  cpu_pools         = var.cpu_pools
  enable_gpu        = false
}

data "google_container_cluster" "default" {
  count    = var.create_cluster ? 0 : 1
  name     = var.cluster_name
  location = var.cluster_location
}

locals {
  endpoint              = var.create_cluster ? "https://${module.infra[0].endpoint}" : "https://${data.google_container_cluster.default[0].endpoint}"
  ca_certificate        = var.create_cluster ? base64decode(module.infra[0].ca_certificate) : base64decode(data.google_container_cluster.default[0].master_auth[0].cluster_ca_certificate)
  private_cluster       = var.create_cluster ? var.private_cluster : data.google_container_cluster.default[0].private_cluster_config.0.enable_private_endpoint
  cluster_membership_id = var.cluster_membership_id == "" ? var.cluster_name : var.cluster_membership_id
  enable_autopilot      = var.create_cluster ? var.autopilot_cluster : data.google_container_cluster.default[0].enable_autopilot
  enable_tpu            = var.create_cluster ? true : data.google_container_cluster.default[0].enable_tpu
  host                  = local.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : local.endpoint
}

locals {
  workload_identity_service_account = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.workload_identity_service_account}" : var.workload_identity_service_account
}

provider "kubernetes" {
  alias                  = "jupyter"
  host                   = local.host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
  dynamic "exec" {
    for_each = local.private_cluster ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

provider "helm" {
  alias = "jupyter"
  kubernetes {
    host                   = local.host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
    dynamic "exec" {
      for_each = local.private_cluster ? [1] : []
      content {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "gke-gcloud-auth-plugin"
      }
    }
  }
}

module "gcs" {
  source      = "../../modules/gcs"
  count       = var.create_gcs_bucket ? 1 : 0
  project_id  = var.project_id
  bucket_name = var.gcs_bucket
}

# create namespace
module "namespace" {
  source           = "../../modules/kubernetes-namespace"
  providers        = { helm = helm.jupyter }
  namespace        = var.kubernetes_namespace
  create_namespace = true
}

# IAP Section: Enabled the IAP service
resource "google_project_service" "project_service" {
  count   = var.add_auth ? 1 : 0
  project = var.project_id
  service = "iap.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Creates jupyterhub
module "jupyterhub" {
  source                            = "../../modules/jupyter"
  providers                         = { helm = helm.jupyter, kubernetes = kubernetes.jupyter }
  project_id                        = var.project_id
  namespace                         = var.kubernetes_namespace
  workload_identity_service_account = local.workload_identity_service_account
  gcs_bucket                        = var.gcs_bucket
  autopilot_cluster                 = local.enable_autopilot

  # IAP Auth parameters
  add_auth                 = var.add_auth
  brand                    = var.brand
  support_email            = var.support_email
  client_id                = var.client_id
  client_secret            = var.client_secret
  k8s_ingress_name         = var.k8s_ingress_name
  k8s_managed_cert_name    = var.k8s_managed_cert_name
  k8s_iap_secret_name      = var.k8s_iap_secret_name
  k8s_backend_config_name  = var.k8s_backend_config_name
  k8s_backend_service_name = var.k8s_backend_service_name
  k8s_backend_service_port = var.k8s_backend_service_port
  url_domain_addr          = var.url_domain_addr
  url_domain_name          = var.url_domain_name
  members_allowlist        = var.members_allowlist
  depends_on               = [module.gcs, module.namespace]
}
