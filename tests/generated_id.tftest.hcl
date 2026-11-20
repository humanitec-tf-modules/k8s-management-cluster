# Verifies the generated Resource Definition ID.
# Runs use "command = apply" against mocked providers so that the random suffix is known to assertions.

mock_provider "helm" {}
mock_provider "humanitec" {}
mock_provider "kubernetes" {}
mock_provider "tls" {}
mock_provider "random" {}

override_resource {
  target = random_string.resource_definition_id_suffix
  values = {
    result = "x9y8"
  }
}

variables {
  helm_release_version        = "1.2.3"
  cloud_account_id            = "my-aws-account"
  cluster_values              = { name = "my-cluster", region = "eu-central-1" }
  driver_type                 = "humanitec/k8s-cluster-eks"
  cluster_access_subject_kind = "Group"
  cluster_access_subject_name = "humanitec-platform-orchestrator"
  helm_release_set_wo         = []
}

run "generates_resource_definition_id" {
  command = apply

  assert {
    condition     = length(random_string.resource_definition_id_suffix) == 1
    error_message = "A random suffix must be generated if resource_definition_id is not set"
  }
  assert {
    condition     = random_string.resource_definition_id_suffix[0].length == 4 && random_string.resource_definition_id_suffix[0].upper == false && random_string.resource_definition_id_suffix[0].special == false
    error_message = "The random suffix must consist of 4 lowercase alphanumeric characters"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.id == "management-cluster-x9y8"
    error_message = "The Resource Definition ID must default to management-cluster-<suffix>"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.name == "management-cluster-x9y8"
    error_message = "The Resource Definition name must default to the generated ID"
  }
  assert {
    condition     = output.resource_definition_id == "management-cluster-x9y8"
    error_message = "resource_definition_id output must contain the generated ID"
  }
}

run "generates_resource_definition_id_with_prefix" {
  command = apply

  variables {
    resource_definition_id_prefix = "management-cluster-eks"
  }

  assert {
    condition     = humanitec_resource_definition.cluster.id == "management-cluster-eks-x9y8"
    error_message = "The generated Resource Definition ID must start with resource_definition_id_prefix"
  }
}

run "uses_passed_in_resource_definition_id" {
  command = plan

  variables {
    resource_definition_id = "my-cluster"
  }

  assert {
    condition     = length(random_string.resource_definition_id_suffix) == 0
    error_message = "No random suffix must be generated if resource_definition_id is set"
  }
  assert {
    condition     = humanitec_resource_definition.cluster.id == "my-cluster"
    error_message = "The Resource Definition ID must be taken from resource_definition_id"
  }
}
