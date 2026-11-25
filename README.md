# Humanitec Management Cluster on Kubernetes

This repository contains an OpenTofu/Terraform module for configuring an existing Kubernetes cluster as a Humanitec management cluster.

If your target cluster is one of Azure AKS, AWS EKS, or Google Cloud GKE, use these modules instead of the current one:

- [AKS](https://github.com/humanitec-tf-modules/management-cluster-aks)
- [EKS](https://github.com/humanitec-tf-modules/management-cluster-eks)
- [GKE](https://github.com/humanitec-tf-modules/management-cluster-gke)

## Runner cluster

To also set up the cluster to execute runners, use the separate module for your cluster type:

- [AKS](https://github.com/humanitec-tf-modules/k8s-runner-cluster-aks)
- [EKS](https://github.com/humanitec-tf-modules/k8s-runner-cluster-eks)
- [GKE](https://github.com/humanitec-tf-modules/k8s-runner-cluster-gke)
- [Generic](https://github.com/humanitec-tf-modules/k8s-runner-cluster)

## Operator installation

The setup includes installing the [Humanitec Operator](https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-operator/overview/) and creating a cluster [Resource Definition](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/resource-definitions). The module also creates the required permissions on the cluster itself via a `ClusterRole` and `ClusterRoleBinding`.

The Operator install uses a [Helm chart](https://helm.sh). The module exposes all the properties of the [`helm_release` resource](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) as variables named `helm_release_*`.

The chart has its own values which you can set through the module's `helm_release_values` or `helm_release_set*` variables. To list them, run `helm show values oci://ghcr.io/humanitec/charts/humanitec-operator`. See the [usage example](#set-helm-chart-values) below.

Connecting a secret store to the Operator is not part of this module. [Sibling modules](https://github.com/orgs/humanitec-tf-modules/repositories?q=secret-store) are available that implement the [guides for your secret store type](https://developer.humanitec.com/platform-orchestrator/guides/platform-engineers/security/connect-secret-stores/overview/). 

## Humanitec Agent

By default, the module configures access for the Platform Orchestrator to the cluster through the [Humanitec Agent](https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-agent/overview/) by adding the secret `agent_url` to the Resource Definition, referencing the output `url` of the Resource `agent#agent`. This requires a Resource Definition of type `agent` matching the same Deployments as the cluster.

Installing the Agent and creating its Resource Definition are not part of this module. Use the module [agent-k8s](https://github.com/humanitec-tf-modules/agent-k8s) to do so.

To access the cluster API server directly instead, set `enable_agent = false`.

## Authentication for Drivers

The Operator needs to [authenticate against Humanitec-hosted Drivers](https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-operator/installation/#configure-authentication-for-drivers) only if you use any of them. The Echo, Template, and any built-in Drivers run inside the Operator and do not need it.

Authentication for Drivers is off by default. To turn it on, set `enable_driver_authentication = true`. The module then does two things:

- It registers the public key in your Humanitec Organization
- It stores the private key and the Humanitec Organization ID in a Kubernetes Secret in the Operator namespace

You can pass in a key pair via `operator_private_key` and `operator_public_key`, or let the module generate one.

The module does not store a passed-in private key in the Terraform state.

## Usage

### Generic cluster

```hcl
module "my_management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
  }

  # Operator chart version
  helm_release_version = "1.2.3"

  resource_definition_id = "my-generic-k8s-cluster"
  driver_type            = "humanitec/k8s-cluster"

  # Common Name (CN) of the client certificate in cluster_secrets
  cluster_access_subject_name = "humanitec-platform-orchestrator"
  cluster_access_subject_kind = "User"

  # Driver inputs of the humanitec/k8s-cluster Driver
  cluster_values = {
    "loadbalancer" = "my-lb.example.com"
    "cluster_data" = {
      "name" = "my-cluster"
      # Kubeconfig property: cluster.server
      "server" = "https://my-cluster.example.com:6443"
      # Kubeconfig property: cluster.certificate-authority-data
      "certificate-authority-data" = "LS0t...ca-data....=="
      # Kubeconfig property: cluster.insecure-skip-tls-verify
      "insecure-skip-tls-verify" = false
      # Kubeconfig property: cluster.proxy-url
      "proxy_url" = "https://my-proxy.example.com"
      # Kubeconfig property: cluster.tls-server-name
      "tls-server-name" = "my-cluster.example.com"
    }
  }
  cluster_secrets = {
    "credentials" = {
      # Kubeconfig property: user.client-certificate-data
      "client-certificate-data" = "LS0t...cert-data...=="
      # Kubeconfig property: user.client-key-data
      "client-key-data" = "LS0t...key-data...=="
      # Kubeconfig property: user.token
      "token" = "..."
      # Kubeconfig property: user.auth-provider
      "auth-provider" = { ... }
    }
  }

  # Optional: matching criteria
  resource_definition_criteria = [
    { env_type = "development" },
  ]
}
```

The following examples configure the Operator installation. They omit the cluster inputs shown in the Generic cluster example.

### Enable authentication for Drivers with your own key pair

```hcl
module "my_management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
  }

  # Cluster inputs omitted

  enable_driver_authentication = true
  humanitec_org_id             = "my-org"
  # Ephemeral: pass it in from an ephemeral variable or an ephemeral resource of your secret store
  # so that the key is not stored in the state of the calling configuration either
  operator_private_key = var.operator_private_key
  operator_public_key  = "-----BEGIN PUBLIC KEY----- ..."
  helm_release_version         = "1.2.3"
}
```

### Enable authentication for Drivers with a convenience key pair

The module can generate a key pair for convenience, but we do not recommend this for production use because the `tls_private_key` resource stores the generated private key in the Terraform state. Use an external key management solution and pass in the keys instead as shown in the preceding example. The module does not store a passed-in private key in the state.

```hcl
module "my_management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
  }

  # Cluster inputs omitted

  enable_driver_authentication = true
  humanitec_org_id             = "my-org"
}
```

### Self-hosting the Helm chart

```hcl
module "my_management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
  }

  # Cluster inputs omitted

  helm_release_repository         = "oci://my-registry.example.com/my/helm/charts"
  helm_release_chart              = "humanitec-operator"
  helm_release_version            = "1.2.3"
  helm_release_repository_ca_file = "..."
  # Use other "helm_release_repository_*" variables as required to access your own registry
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_humanitec"></a> [humanitec](#requirement\_humanitec) | ~> 1.9 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.humanitec_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [humanitec_key.operator](https://registry.terraform.io/providers/humanitec/humanitec/latest/docs/resources/key) | resource |
| [humanitec_resource_definition.cluster](https://registry.terraform.io/providers/humanitec/humanitec/latest/docs/resources/resource_definition) | resource |
| [humanitec_resource_definition_criteria.cluster](https://registry.terraform.io/providers/humanitec/humanitec/latest/docs/resources/resource_definition_criteria) | resource |
| [kubernetes_cluster_role_binding_v1.deploy_access](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding_v1) | resource |
| [kubernetes_cluster_role_v1.deploy_access](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_v1) | resource |
| [kubernetes_secret_v1.operator_private_key](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [random_string.resource_definition_id_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.operator](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_account_id"></a> [cloud\_account\_id](#input\_cloud\_account\_id) | ID of the Cloud Account the Orchestrator uses to access the cluster, e.g. an AWS Cloud Account for `humanitec/k8s-cluster-eks`. Leave unset for Drivers using static credentials in `cluster_secrets`, such as `humanitec/k8s-cluster`. | `string` | `null` | no |
| <a name="input_cluster_access_subject_kind"></a> [cluster\_access\_subject\_kind](#input\_cluster\_access\_subject\_kind) | Kind of the subject the Orchestrator authenticates as when accessing the cluster. One of `Group` or `User`. The module binds the ClusterRole `cluster_role_name` to this subject. | `string` | n/a | yes |
| <a name="input_cluster_access_subject_name"></a> [cluster\_access\_subject\_name](#input\_cluster\_access\_subject\_name) | Name of the subject the Orchestrator authenticates as when accessing the cluster, e.g. the name of a group or the user name. The module binds the ClusterRole `cluster_role_name` to this subject. | `string` | n/a | yes |
| <a name="input_cluster_role_name"></a> [cluster\_role\_name](#input\_cluster\_role\_name) | Name of the Kubernetes ClusterRole and ClusterRoleBinding granting the Orchestrator access to the cluster. | `string` | `"humanitec-deploy-access"` | no |
| <a name="input_cluster_secrets"></a> [cluster\_secrets](#input\_cluster\_secrets) | Driver input secrets of the Resource Definition, e.g. `credentials` for the Driver `humanitec/k8s-cluster`. Their keys depend on `driver_type`, see the Driver documentation at https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/drivers/k8-drivers/. If `enable_agent` is `true`, the module adds the key `agent_url`. | `any` | `{}` | no |
| <a name="input_cluster_values"></a> [cluster\_values](#input\_cluster\_values) | Driver input values of the Resource Definition. Their keys depend on `driver_type`, see the Driver documentation at https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/drivers/k8-drivers/. Must contain the key `name` with the name of the cluster. Entries with a `null` value are omitted so that the Driver default applies. | `any` | n/a | yes |
| <a name="input_driver_type"></a> [driver\_type](#input\_driver\_type) | Driver of the Resource Definition, e.g. `humanitec/k8s-cluster-eks`. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/drivers/k8-drivers/ | `string` | n/a | yes |
| <a name="input_enable_agent"></a> [enable\_agent](#input\_enable\_agent) | Access the cluster through the Humanitec Agent. Adds the secret `agent_url`, referencing the output `url` of the Resource `agent#agent`, to the Resource Definition. Requires a Resource Definition of type `agent` matching the same Deployments as the cluster. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-agent/overview/ | `bool` | `true` | no |
| <a name="input_enable_driver_authentication"></a> [enable\_driver\_authentication](#input\_enable\_driver\_authentication) | Enable authentication of the Operator against Humanitec-hosted Drivers. Requires `humanitec_org_id`. Registers the public key in the Humanitec Organization and stores the private key in the Kubernetes Secret `humanitec-operator-private-key` in the namespace `helm_release_namespace`. Pass in a key pair via `operator_private_key` and `operator_public_key`, or leave both unset to generate a convenience key pair. Only required if you use Humanitec-hosted Drivers. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-operator/installation/#configure-authentication-for-drivers | `bool` | `false` | no |
| <a name="input_helm_release_atomic"></a> [helm\_release\_atomic](#input\_helm\_release\_atomic) | If set, installation process purges chart on fail. The wait flag will be set automatically if atomic is used. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_chart"></a> [helm\_release\_chart](#input\_helm\_release\_chart) | Chart name to be installed. A path may be used. | `string` | `"humanitec-operator"` | no |
| <a name="input_helm_release_cleanup_on_fail"></a> [helm\_release\_cleanup\_on\_fail](#input\_helm\_release\_cleanup\_on\_fail) | Allow deletion of new resources created in this upgrade when upgrade fails. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_create_namespace"></a> [helm\_release\_create\_namespace](#input\_helm\_release\_create\_namespace) | Choose whether to create the Kubernetes namespace | `bool` | `true` | no |
| <a name="input_helm_release_dependency_update"></a> [helm\_release\_dependency\_update](#input\_helm\_release\_dependency\_update) | Run helm dependency update before installing the chart. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_description"></a> [helm\_release\_description](#input\_helm\_release\_description) | Add a custom description | `string` | `null` | no |
| <a name="input_helm_release_devel"></a> [helm\_release\_devel](#input\_helm\_release\_devel) | Use chart development versions, too. Equivalent to version '>0.0.0-0'. If `helm_release_version` is set, this is ignored | `bool` | `null` | no |
| <a name="input_helm_release_disable_crd_hooks"></a> [helm\_release\_disable\_crd\_hooks](#input\_helm\_release\_disable\_crd\_hooks) | Prevent CRD hooks from running, but run other hooks. See helm install --no-crd-hook | `bool` | `null` | no |
| <a name="input_helm_release_disable_openapi_validation"></a> [helm\_release\_disable\_openapi\_validation](#input\_helm\_release\_disable\_openapi\_validation) | If set, the installation process will not validate rendered templates against the Kubernetes OpenAPI Schema. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_disable_webhooks"></a> [helm\_release\_disable\_webhooks](#input\_helm\_release\_disable\_webhooks) | Prevent hooks from running. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_force_update"></a> [helm\_release\_force\_update](#input\_helm\_release\_force\_update) | Force resource update through delete/recreate if needed. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_keyring"></a> [helm\_release\_keyring](#input\_helm\_release\_keyring) | Location of public keys used for verification. Used only if `helm_release_verify` is true. Defaults to `/.gnupg/pubring.gpg` in the location set by `home`. | `string` | `null` | no |
| <a name="input_helm_release_lint"></a> [helm\_release\_lint](#input\_helm\_release\_lint) | Run helm lint when planning. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_max_history"></a> [helm\_release\_max\_history](#input\_helm\_release\_max\_history) | Limit the maximum number of revisions saved per release. Use 0 for no limit. Defaults to 0 (no limit). | `number` | `null` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release for the Operator | `string` | `"humanitec-operator"` | no |
| <a name="input_helm_release_namespace"></a> [helm\_release\_namespace](#input\_helm\_release\_namespace) | Kubernetes namespace where to install the Operator | `string` | `"humanitec-operator-system"` | no |
| <a name="input_helm_release_pass_credentials"></a> [helm\_release\_pass\_credentials](#input\_helm\_release\_pass\_credentials) | Pass credentials to all domains. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_postrender"></a> [helm\_release\_postrender](#input\_helm\_release\_postrender) | Postrender command configuration. | <pre>object({<br/>    binary_path = string<br/>    args        = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_helm_release_recreate_pods"></a> [helm\_release\_recreate\_pods](#input\_helm\_release\_recreate\_pods) | Perform pods restart during upgrade/rollback. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_render_subchart_notes"></a> [helm\_release\_render\_subchart\_notes](#input\_helm\_release\_render\_subchart\_notes) | If set, render subchart notes along with the parent. Defaults to `true`. | `bool` | `null` | no |
| <a name="input_helm_release_replace"></a> [helm\_release\_replace](#input\_helm\_release\_replace) | Re-use the given name, even if that name is already used. This is unsafe in production. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_repository"></a> [helm\_release\_repository](#input\_helm\_release\_repository) | Repository where to locate the requested chart. If is a URL the chart is installed without installing the repository. Set it to `null` for a local chart. | `string` | `"oci://ghcr.io/humanitec/charts"` | no |
| <a name="input_helm_release_repository_ca_file"></a> [helm\_release\_repository\_ca\_file](#input\_helm\_release\_repository\_ca\_file) | The repositories CA File | `string` | `null` | no |
| <a name="input_helm_release_repository_cert_file"></a> [helm\_release\_repository\_cert\_file](#input\_helm\_release\_repository\_cert\_file) | The repositories cert file | `string` | `null` | no |
| <a name="input_helm_release_repository_key_file"></a> [helm\_release\_repository\_key\_file](#input\_helm\_release\_repository\_key\_file) | The repositories cert key file | `string` | `null` | no |
| <a name="input_helm_release_repository_password"></a> [helm\_release\_repository\_password](#input\_helm\_release\_repository\_password) | Password for HTTP basic authentication | `string` | `null` | no |
| <a name="input_helm_release_repository_username"></a> [helm\_release\_repository\_username](#input\_helm\_release\_repository\_username) | Username for HTTP basic authentication | `string` | `null` | no |
| <a name="input_helm_release_reset_values"></a> [helm\_release\_reset\_values](#input\_helm\_release\_reset\_values) | When upgrading, reset the values to the ones built into the chart. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_reuse_values"></a> [helm\_release\_reuse\_values](#input\_helm\_release\_reuse\_values) | When upgrading, reuse the last release's values and merge in any overrides. If 'helm\_release\_reset\_values' is specified, this is ignored. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_set"></a> [helm\_release\_set](#input\_helm\_release\_set) | Custom values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = optional(string)<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_list"></a> [helm\_release\_set\_list](#input\_helm\_release\_set\_list) | Custom list values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_sensitive"></a> [helm\_release\_set\_sensitive](#input\_helm\_release\_set\_sensitive) | Custom sensitive values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_wo"></a> [helm\_release\_set\_wo](#input\_helm\_release\_set\_wo) | Custom values to be merged with the values. This is the same as "helm\_release\_set" but write-only. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_wo_revision"></a> [helm\_release\_set\_wo\_revision](#input\_helm\_release\_set\_wo\_revision) | The current revision of the write-only "helm\_release\_set\_wo" attribute. Incrementing this integer value will cause Terraform to update the write-only value. | `number` | `null` | no |
| <a name="input_helm_release_skip_crds"></a> [helm\_release\_skip\_crds](#input\_helm\_release\_skip\_crds) | If set, no CRDs will be installed. By default, CRDs are installed if not already present. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_take_ownership"></a> [helm\_release\_take\_ownership](#input\_helm\_release\_take\_ownership) | If set, allows Helm to adopt existing resources not marked as managed by the release. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_timeout"></a> [helm\_release\_timeout](#input\_helm\_release\_timeout) | Time in seconds to wait for any individual Kubernetes operation. Defaults to 300 seconds. | `number` | `null` | no |
| <a name="input_helm_release_upgrade_install"></a> [helm\_release\_upgrade\_install](#input\_helm\_release\_upgrade\_install) | If true, the provider will install the release at the specified version even if a release not controlled by the provider is present: this is equivalent to running 'helm upgrade --install' with the Helm CLI. WARNING: this may not be suitable for production use -- see the 'Upgrade Mode' note in the provider documentation. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_values"></a> [helm\_release\_values](#input\_helm\_release\_values) | List of values in raw yaml format to pass to Helm. | `list(string)` | `null` | no |
| <a name="input_helm_release_verify"></a> [helm\_release\_verify](#input\_helm\_release\_verify) | Verify the package before installing it. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_version"></a> [helm\_release\_version](#input\_helm\_release\_version) | Chart version to use for the Operator installation in the format `X.Y.Z`. If this is not specified, the latest version is installed. | `string` | `null` | no |
| <a name="input_helm_release_wait"></a> [helm\_release\_wait](#input\_helm\_release\_wait) | Will wait until all resources are in a ready state before marking the release as successful. Defaults to `true`. | `bool` | `null` | no |
| <a name="input_helm_release_wait_for_jobs"></a> [helm\_release\_wait\_for\_jobs](#input\_helm\_release\_wait\_for\_jobs) | If wait is enabled, will wait until all Jobs have been completed before marking the release as successful. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_humanitec_org_id"></a> [humanitec\_org\_id](#input\_humanitec\_org\_id) | Humanitec Organization ID. Required if `enable_driver_authentication` is `true`, ignored otherwise. | `string` | `null` | no |
| <a name="input_operator_private_key"></a> [operator\_private\_key](#input\_operator\_private\_key) | Private key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PRIVATE KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. The variable is ephemeral and the module writes the key to the Kubernetes Secret via a write-only attribute, so the key is not stored in the Terraform state or plan. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use. | `string` | `null` | no |
| <a name="input_operator_public_key"></a> [operator\_public\_key](#input\_operator\_public\_key) | Public key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PUBLIC KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use. | `string` | `null` | no |
| <a name="input_resource_definition_criteria"></a> [resource\_definition\_criteria](#input\_resource\_definition\_criteria) | Matching Criteria for the Resource Definition, directing Deployments to the cluster. Each entry creates one Matching Criteria and must be unique. Unset attributes match any value. See https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/resource-definitions/#matching-criteria | <pre>list(object({<br/>    app_id   = optional(string)<br/>    env_id   = optional(string)<br/>    env_type = optional(string)<br/>    res_id   = optional(string)<br/>    class    = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_resource_definition_id"></a> [resource\_definition\_id](#input\_resource\_definition\_id) | ID of the Resource Definition of type `k8s-cluster` representing the cluster. Must be unique within the Humanitec Organization. Defaults to `<resource_definition_id_prefix>-<suffix>` with a random suffix of four lowercase alphanumeric characters. | `string` | `null` | no |
| <a name="input_resource_definition_id_prefix"></a> [resource\_definition\_id\_prefix](#input\_resource\_definition\_id\_prefix) | Prefix of the generated `resource_definition_id`, e.g. `management-cluster-eks`. Ignored if `resource_definition_id` is set. | `string` | `"management-cluster"` | no |
| <a name="input_resource_definition_name"></a> [resource\_definition\_name](#input\_resource\_definition\_name) | Display name of the Resource Definition. Defaults to `resource_definition_id`. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_access_subject"></a> [cluster\_access\_subject](#output\_cluster\_access\_subject) | Subject of the Kubernetes ClusterRoleBinding, i.e. the identity the Orchestrator uses to access the cluster, as an object with the attributes `kind` and `name` |
| <a name="output_cluster_role_binding_name"></a> [cluster\_role\_binding\_name](#output\_cluster\_role\_binding\_name) | Name of the Kubernetes ClusterRoleBinding granting the Orchestrator access to the cluster |
| <a name="output_cluster_role_name"></a> [cluster\_role\_name](#output\_cluster\_role\_name) | Name of the Kubernetes ClusterRole granting the Orchestrator access to the cluster |
| <a name="output_helm_release_chart"></a> [helm\_release\_chart](#output\_helm\_release\_chart) | Chart name used for the Operator Helm chart |
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the Helm release for the Operator |
| <a name="output_helm_release_namespace"></a> [helm\_release\_namespace](#output\_helm\_release\_namespace) | Kubernetes namespace where the Operator is installed |
| <a name="output_helm_release_repository"></a> [helm\_release\_repository](#output\_helm\_release\_repository) | Repository used for the Operator Helm chart |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Chart version used for the Operator installation |
| <a name="output_operator_private_key"></a> [operator\_private\_key](#output\_operator\_private\_key) | Generated convenience private key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false` or if the key pair is passed in via `operator_private_key` and `operator_public_key`. |
| <a name="output_operator_private_key_secret_name"></a> [operator\_private\_key\_secret\_name](#output\_operator\_private\_key\_secret\_name) | Name of the Kubernetes Secret holding the private key of the Operator. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key"></a> [operator\_public\_key](#output\_operator\_public\_key) | Public key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key_fingerprint"></a> [operator\_public\_key\_fingerprint](#output\_operator\_public\_key\_fingerprint) | Fingerprint (SHA256 hash of the DER representation) of the public key registered in the Humanitec Organization. Use it to debug authentication against Humanitec-hosted Drivers. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key_id"></a> [operator\_public\_key\_id](#output\_operator\_public\_key\_id) | ID of the public key registered in the Humanitec Organization. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_resource_definition_driver_type"></a> [resource\_definition\_driver\_type](#output\_resource\_definition\_driver\_type) | Driver type of the Resource Definition |
| <a name="output_resource_definition_id"></a> [resource\_definition\_id](#output\_resource\_definition\_id) | ID of the Resource Definition of type `k8s-cluster` representing the cluster |
<!-- END_TF_DOCS -->
