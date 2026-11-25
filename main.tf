locals {
  # A passed-in key pair counts as set only if it is not empty or blank. Checked on the public key because the
  # private key is ephemeral and must not decide the resource count. The validation of operator_private_key
  # ensures that both or neither key are set.
  operator_keys_passed_in = try(trimspace(var.operator_public_key), "") != ""

  # Ephemeral if passed in, so it can only be used in write-only attributes
  operator_private_key = var.enable_driver_authentication ? coalesce(one(tls_private_key.operator[*].private_key_pem_pkcs8), var.operator_private_key) : null
  operator_public_key  = var.enable_driver_authentication ? coalesce(one(tls_private_key.operator[*].public_key_pem), var.operator_public_key) : null

  # Revision of the write-only Secret data. The provider rewrites the data whenever the revision changes, so derive it
  # from the non-secret values that change together with the data: the public key, which changes with the private key,
  # and the Organization ID. Must be at least 1.
  operator_private_key_secret_revision = var.enable_driver_authentication ? parseint(substr(sha256("${local.operator_public_key}\n${var.humanitec_org_id}"), 0, 12), 16) + 1 : null

  # The Operator expects the Secret under this exact name in its own namespace
  operator_private_key_secret_name = "humanitec-operator-private-key"
}

# Convenience key used only if driver authentication is enabled and no operator_private_key is passed in.
# Not recommended for production use.
resource "tls_private_key" "operator" {
  count = var.enable_driver_authentication && !local.operator_keys_passed_in ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# Helm chart installation on target cluster
resource "helm_release" "humanitec_operator" {
  name             = var.helm_release_name
  namespace        = var.helm_release_namespace
  create_namespace = var.helm_release_create_namespace

  repository = var.helm_release_repository
  chart      = var.helm_release_chart
  version    = var.helm_release_version

  repository_ca_file   = var.helm_release_repository_ca_file
  repository_cert_file = var.helm_release_repository_cert_file
  repository_key_file  = var.helm_release_repository_key_file
  repository_username  = var.helm_release_repository_username
  repository_password  = var.helm_release_repository_password
  pass_credentials     = var.helm_release_pass_credentials
  devel                = var.helm_release_devel
  verify               = var.helm_release_verify
  keyring              = var.helm_release_keyring

  description                = var.helm_release_description
  atomic                     = var.helm_release_atomic
  cleanup_on_fail            = var.helm_release_cleanup_on_fail
  dependency_update          = var.helm_release_dependency_update
  disable_crd_hooks          = var.helm_release_disable_crd_hooks
  disable_openapi_validation = var.helm_release_disable_openapi_validation
  disable_webhooks           = var.helm_release_disable_webhooks
  force_update               = var.helm_release_force_update
  lint                       = var.helm_release_lint
  max_history                = var.helm_release_max_history
  postrender                 = var.helm_release_postrender
  recreate_pods              = var.helm_release_recreate_pods
  render_subchart_notes      = var.helm_release_render_subchart_notes
  replace                    = var.helm_release_replace
  reset_values               = var.helm_release_reset_values
  reuse_values               = var.helm_release_reuse_values
  skip_crds                  = var.helm_release_skip_crds
  take_ownership             = var.helm_release_take_ownership
  timeout                    = var.helm_release_timeout
  upgrade_install            = var.helm_release_upgrade_install
  wait                       = var.helm_release_wait
  wait_for_jobs              = var.helm_release_wait_for_jobs

  values          = var.helm_release_values
  set             = var.helm_release_set
  set_list        = var.helm_release_set_list
  set_sensitive   = var.helm_release_set_sensitive
  set_wo          = var.helm_release_set_wo
  set_wo_revision = var.helm_release_set_wo_revision
}

# Public key registration in the Orchestrator for authenticating the Operator against Humanitec-hosted Drivers
resource "humanitec_key" "operator" {
  count = var.enable_driver_authentication ? 1 : 0

  key = local.operator_public_key
}

# Private key made available to the Operator for signing requests to Humanitec-hosted Drivers
resource "kubernetes_secret_v1" "operator_private_key" {
  count = var.enable_driver_authentication ? 1 : 0

  metadata {
    name = local.operator_private_key_secret_name
    # Referencing the release ensures that the namespace exists before the Secret is created
    namespace = helm_release.humanitec_operator.namespace
  }

  # Write-only so that the private key is not stored in the Terraform state
  data_wo = {
    privateKey              = local.operator_private_key
    humanitecOrganisationID = var.humanitec_org_id
  }
  data_wo_revision = local.operator_private_key_secret_revision

  # Make the Operator use the private key only once the public key is registered.
  # On destroy, the Secret is removed before the registration.
  depends_on = [humanitec_key.operator]
}

# Random suffix for the generated Resource Definition ID. Created only if no ID is passed in
resource "random_string" "resource_definition_id_suffix" {
  count = var.resource_definition_id == null ? 1 : 0

  length  = 4
  upper   = false
  special = false
}

locals {
  resource_definition_id = var.resource_definition_id != null ? var.resource_definition_id : "${var.resource_definition_id_prefix}-${random_string.resource_definition_id_suffix[0].result}"

  # Drop unset values so that the Driver applies its defaults
  cluster_driver_values = {
    for k, v in var.cluster_values : k => v if v != null
  }

  # Driver secrets: the passed-in secrets, and the URL of the Humanitec Agent if enabled
  cluster_driver_secrets = merge(
    var.cluster_secrets,
    var.enable_agent ? { agent_url = "$${resources['agent#agent'].outputs.url}" } : {},
  )
}

# Permissions for the Orchestrator to deploy to the cluster in Direct mode. Identical for all cluster types.
# See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/containerization/kubernetes/
resource "kubernetes_cluster_role_v1" "deploy_access" {
  metadata {
    name = var.cluster_role_name
  }

  # Namespaces management
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["create", "get", "list", "update", "patch", "delete"]
  }
  # Humanitec's CRs management
  rule {
    api_groups = ["humanitec.io"]
    resources  = ["resources", "secretmappings", "workloadpatches", "workloads"]
    verbs      = ["create", "get", "list", "update", "patch", "delete", "deletecollection", "watch"]
  }
  # Deployment / Workload Status in UI
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "replicasets", "daemonsets"]
    verbs      = ["get", "list"]
  }
  # "watch" keeps the pod status in the UI's runtime view live
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
  # Container logs in the UI
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
  # Pause Environments
  rule {
    api_groups = ["apps"]
    resources  = ["deployments/scale"]
    verbs      = ["update"]
  }
  # Active Resources outputs
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get"]
  }
}

# Bind the permissions to the identity the Orchestrator uses to access the cluster.
resource "kubernetes_cluster_role_binding_v1" "deploy_access" {
  metadata {
    name = kubernetes_cluster_role_v1.deploy_access.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.deploy_access.metadata[0].name
  }
  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = var.cluster_access_subject_kind
    name      = var.cluster_access_subject_name
  }
}

# Resource Definition representing the cluster in the Orchestrator
resource "humanitec_resource_definition" "cluster" {
  id             = local.resource_definition_id
  name           = coalesce(var.resource_definition_name, local.resource_definition_id)
  type           = "k8s-cluster"
  driver_type    = var.driver_type
  driver_account = var.cloud_account_id

  driver_inputs = {
    values_string  = jsonencode(local.cluster_driver_values)
    secrets_string = length(local.cluster_driver_secrets) > 0 ? jsonencode(local.cluster_driver_secrets) : null
  }

  # Make Deployments target the cluster only once the Operator is running and the Orchestrator has access.
  # On destroy, the Resource Definition is removed first.
  depends_on = [
    helm_release.humanitec_operator,
    kubernetes_cluster_role_binding_v1.deploy_access,
  ]
}

# Matching Criteria directing Deployments to the cluster
resource "humanitec_resource_definition_criteria" "cluster" {
  count = length(var.resource_definition_criteria)

  resource_definition_id = humanitec_resource_definition.cluster.id
  app_id                 = var.resource_definition_criteria[count.index].app_id
  env_id                 = var.resource_definition_criteria[count.index].env_id
  env_type               = var.resource_definition_criteria[count.index].env_type
  res_id                 = var.resource_definition_criteria[count.index].res_id
  class                  = var.resource_definition_criteria[count.index].class
}
