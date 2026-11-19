# Verifies the cluster Resource Definition and the Kubernetes objects granting the Orchestrator access, per cluster type

# Mock the providers so that tests run without a Kubernetes cluster or Humanitec Organization
mock_provider "helm" {}
mock_provider "humanitec" {}
mock_provider "kubernetes" {}
mock_provider "random" {}
mock_provider "tls" {}

variables {
  helm_release_version        = "1.2.3"
  resource_definition_id      = "my-cluster"
  cloud_account_id            = "my-aws-account"
  driver_type                 = "humanitec/k8s-cluster-eks"
  cluster_access_subject_kind = "Group"
  cluster_access_subject_name = "humanitec-platform-orchestrator"
  cluster_values              = { name = "my-eks", region = "eu-central-1" }
}

run "creates_resource_definition" {
  command = plan

  assert {
    condition     = humanitec_resource_definition.cluster.type == "k8s-cluster"
    error_message = "The Resource Definition must be of type k8s-cluster"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.driver_type == "humanitec/k8s-cluster-eks"
    error_message = "The Driver must be taken from driver_type"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.driver_account == "my-aws-account"
    error_message = "driver_account must be taken from cloud_account_id"
  }
}

run "creates_resource_definition_without_cloud_account" {
  command = plan

  variables {
    cloud_account_id = null
    driver_type      = "humanitec/k8s-cluster"
  }

  assert {
    condition     = humanitec_resource_definition.cluster.driver_type == "humanitec/k8s-cluster"
    error_message = "The Driver must be taken from driver_type"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.driver_account == null
    error_message = "No driver_account must be set if cloud_account_id is null"
  }
}

run "binds_cluster_role_to_group" {
  command = plan

  assert {
    condition     = kubernetes_cluster_role_binding_v1.deploy_access.subject[0].kind == "Group" && kubernetes_cluster_role_binding_v1.deploy_access.subject[0].name == "humanitec-platform-orchestrator"
    error_message = "The subject must be taken from cluster_access_subject_kind and cluster_access_subject_name"
  }
  assert {
    condition     = kubernetes_cluster_role_binding_v1.deploy_access.subject[0].api_group == "rbac.authorization.k8s.io"
    error_message = "The subject must use the API group rbac.authorization.k8s.io"
  }
  assert {
    condition     = output.cluster_access_subject == { kind = "Group", name = "humanitec-platform-orchestrator" }
    error_message = "cluster_access_subject output must reflect the subject of the ClusterRoleBinding"
  }
}

run "binds_cluster_role_to_user" {
  command = plan

  variables {
    cluster_access_subject_kind = "User"
    cluster_access_subject_name = "my-sa@my-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = kubernetes_cluster_role_binding_v1.deploy_access.subject[0].kind == "User" && kubernetes_cluster_role_binding_v1.deploy_access.subject[0].name == "my-sa@my-project.iam.gserviceaccount.com"
    error_message = "The subject must be taken from cluster_access_subject_kind and cluster_access_subject_name"
  }
}

run "passes_cluster_values" {
  command = plan

  variables {
    cluster_values = {
      name         = "my-cluster"
      loadbalancer = "10.0.0.1"
      internal_ip  = false
      proxy_url    = null
      cluster_data = {
        server                     = "https://my-cluster.example.com:6443"
        certificate-authority-data = "LS0tY2E="
      }
    }
  }

  assert {
    condition = jsondecode(humanitec_resource_definition.cluster.driver_inputs.values_string) == {
      name         = "my-cluster"
      loadbalancer = "10.0.0.1"
      internal_ip  = false
      cluster_data = {
        server                     = "https://my-cluster.example.com:6443"
        certificate-authority-data = "LS0tY2E="
      }
    }
    error_message = "Driver values must be taken from cluster_values, keeping nested and false values and omitting null values"
  }
}

run "passes_agent_url_by_default" {
  command = plan

  assert {
    condition     = jsondecode(humanitec_resource_definition.cluster.driver_inputs.secrets_string) == { agent_url = "$${resources['agent#agent'].outputs.url}" }
    error_message = "Driver secrets must contain only the Agent URL by default"
  }
}

run "merges_cluster_secrets_with_agent_url" {
  command = plan

  variables {
    cluster_secrets = {
      credentials = {
        client-certificate-data = "LS0tY2VydA=="
        client-key-data         = "LS0ta2V5"
      }
    }
  }

  assert {
    condition = jsondecode(humanitec_resource_definition.cluster.driver_inputs.secrets_string) == {
      credentials = {
        client-certificate-data = "LS0tY2VydA=="
        client-key-data         = "LS0ta2V5"
      }
      agent_url = "$${resources['agent#agent'].outputs.url}"
    }
    error_message = "Driver secrets must contain cluster_secrets and the Agent URL"
  }
}

run "passes_only_cluster_secrets_without_agent" {
  command = plan

  variables {
    enable_agent    = false
    cluster_secrets = { credentials = { token = "abc" } }
  }

  assert {
    condition     = jsondecode(humanitec_resource_definition.cluster.driver_inputs.secrets_string) == { credentials = { token = "abc" } }
    error_message = "Driver secrets must contain only cluster_secrets if the Agent is disabled"
  }
}

run "omits_secrets_without_agent_and_cluster_secrets" {
  command = plan

  variables {
    enable_agent = false
  }

  assert {
    condition     = humanitec_resource_definition.cluster.driver_inputs.secrets_string == null
    error_message = "No driver secrets must be passed if the Agent is disabled and cluster_secrets is empty"
  }
}

run "creates_deploy_access_cluster_role" {
  command = plan

  assert {
    condition     = kubernetes_cluster_role_v1.deploy_access.metadata[0].name == "humanitec-deploy-access"
    error_message = "The ClusterRole must be named humanitec-deploy-access by default"
  }
  assert {
    condition     = length(kubernetes_cluster_role_v1.deploy_access.rule) == 8
    error_message = "The ClusterRole must contain the 8 rules for Direct mode"
  }
  assert {
    condition     = one([for r in kubernetes_cluster_role_v1.deploy_access.rule : r.verbs if contains(r.api_groups, "humanitec.io")]) == tolist(["create", "get", "list", "update", "patch", "delete", "deletecollection", "watch"])
    error_message = "The ClusterRole must grant full access to the Humanitec custom resources"
  }
  assert {
    condition     = kubernetes_cluster_role_binding_v1.deploy_access.metadata[0].name == "humanitec-deploy-access"
    error_message = "The ClusterRoleBinding must be named like the ClusterRole"
  }
  assert {
    condition     = kubernetes_cluster_role_binding_v1.deploy_access.role_ref[0].kind == "ClusterRole" && kubernetes_cluster_role_binding_v1.deploy_access.role_ref[0].name == "humanitec-deploy-access"
    error_message = "The ClusterRoleBinding must reference the ClusterRole"
  }
  assert {
    condition     = output.cluster_role_name == "humanitec-deploy-access" && output.cluster_role_binding_name == "humanitec-deploy-access"
    error_message = "cluster_role_name and cluster_role_binding_name outputs must reflect the created objects"
  }
}

run "uses_custom_cluster_role_name" {
  command = plan

  variables {
    cluster_role_name = "my-role"
  }

  assert {
    condition     = kubernetes_cluster_role_v1.deploy_access.metadata[0].name == "my-role" && kubernetes_cluster_role_binding_v1.deploy_access.metadata[0].name == "my-role"
    error_message = "ClusterRole and ClusterRoleBinding must be named after cluster_role_name"
  }
}

run "names_resource_definition_and_creates_criteria" {
  command = plan

  variables {
    resource_definition_criteria = [
      { env_type = "development" },
      { app_id = "my-app", env_id = "test" },
    ]
  }

  assert {
    condition     = humanitec_resource_definition.cluster.id == "my-cluster" && humanitec_resource_definition.cluster.name == "my-cluster"
    error_message = "The Resource Definition name must default to resource_definition_id"
  }
  assert {
    condition     = length(humanitec_resource_definition_criteria.cluster) == 2
    error_message = "One Matching Criteria must be created per entry of resource_definition_criteria"
  }
  assert {
    condition     = humanitec_resource_definition_criteria.cluster[0].resource_definition_id == "my-cluster" && humanitec_resource_definition_criteria.cluster[0].env_type == "development" && humanitec_resource_definition_criteria.cluster[0].app_id == null
    error_message = "The first Matching Criteria must match the env_type only"
  }
  assert {
    condition     = humanitec_resource_definition_criteria.cluster[1].app_id == "my-app" && humanitec_resource_definition_criteria.cluster[1].env_id == "test" && humanitec_resource_definition_criteria.cluster[1].env_type == null
    error_message = "The second Matching Criteria must match the app_id and env_id"
  }
  assert {
    condition     = output.resource_definition_id == "my-cluster" && output.resource_definition_driver_type == "humanitec/k8s-cluster-eks"
    error_message = "resource_definition_id and resource_definition_driver_type outputs must reflect the Resource Definition"
  }
}

run "uses_custom_resource_definition_name" {
  command = plan

  variables {
    resource_definition_name = "My cluster"
  }

  assert {
    condition     = humanitec_resource_definition.cluster.name == "My cluster"
    error_message = "The Resource Definition name must be taken from resource_definition_name"
  }
  assert {
    condition     = length(humanitec_resource_definition_criteria.cluster) == 0
    error_message = "No Matching Criteria must be created by default"
  }
}
