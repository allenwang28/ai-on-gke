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

#######################################################
####    APPLICATIONS
#######################################################

provider "google" {
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
  enable_gpu        = true
  gpu_pools         = var.gpu_pools
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
  alias                  = "ray"
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
  alias = "ray"
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

module "namespace" {
  source           = "../../modules/kubernetes-namespace"
  providers        = { helm = helm.ray }
  create_namespace = true
  namespace        = var.kubernetes_namespace
}

module "kuberay-operator" {
  source                 = "../../modules/kuberay-operator"
  providers              = { helm = helm.ray, kubernetes = kubernetes.ray }
  name                   = "kuberay-operator"
  create_namespace       = true
  namespace              = var.kubernetes_namespace
  project_id             = var.project_id
  autopilot_cluster      = local.enable_autopilot
  google_service_account = local.workload_identity_service_account
  create_service_account = var.create_service_account
}

module "kuberay-logging" {
  source    = "../../modules/kuberay-logging"
  providers = { kubernetes = kubernetes.ray }
  namespace = var.kubernetes_namespace

  depends_on = [module.namespace]
}

module "kuberay-monitoring" {
  count                           = var.create_ray_cluster ? 1 : 0
  source                          = "../../modules/kuberay-monitoring"
  providers                       = { helm = helm.ray, kubernetes = kubernetes.ray }
  project_id                      = var.project_id
  namespace                       = var.kubernetes_namespace
  create_namespace                = true
  enable_grafana_on_ray_dashboard = var.enable_grafana_on_ray_dashboard
  k8s_service_account             = local.workload_identity_service_account
  depends_on                      = [module.kuberay-operator]
}

module "gcs" {
  source      = "../../modules/gcs"
  count       = var.create_gcs_bucket ? 1 : 0
  project_id  = var.project_id
  bucket_name = var.gcs_bucket
}

module "kuberay-cluster" {
  count                  = var.create_ray_cluster == true ? 1 : 0
  source                 = "../../modules/kuberay-cluster"
  providers              = { helm = helm.ray, kubernetes = kubernetes.ray }
  namespace              = var.kubernetes_namespace
  project_id             = var.project_id
  enable_tpu             = local.enable_tpu
  enable_gpu             = var.enable_gpu
  gcs_bucket             = var.gcs_bucket
  autopilot_cluster      = local.enable_autopilot
  google_service_account = local.workload_identity_service_account
  grafana_host           = var.enable_grafana_on_ray_dashboard ? module.kuberay-monitoring[0].grafana_uri : ""
  depends_on             = [module.gcs, module.kuberay-operator]
}

