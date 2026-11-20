# Verifies the validation of the cluster inputs

# Mock the providers so that tests run without a Kubernetes cluster or Humanitec Organization
mock_provider "helm" {}
mock_provider "humanitec" {}
mock_provider "kubernetes" {}
mock_provider "random" {}
mock_provider "tls" {}

# Valid inputs. Each run breaks one input
variables {
  helm_release_version        = "1.2.3"
  resource_definition_id      = "my-cluster"
  cloud_account_id            = "my-account"
  driver_type                 = "humanitec/k8s-cluster-eks"
  cluster_access_subject_kind = "Group"
  cluster_access_subject_name = "my-subject"
  cluster_values              = { name = "my-cluster" }
}

run "rejects_empty_resource_definition_id" {
  command = plan

  variables {
    resource_definition_id = " "
  }

  expect_failures = [var.resource_definition_id]
}

run "rejects_empty_cloud_account_id" {
  command = plan

  variables {
    cloud_account_id = " "
  }

  expect_failures = [var.cloud_account_id]
}

run "accepts_missing_cloud_account_id" {
  command = plan

  variables {
    cloud_account_id = null
  }
}

run "rejects_empty_resource_definition_id_prefix" {
  command = plan

  variables {
    resource_definition_id        = null
    resource_definition_id_prefix = " "
  }

  expect_failures = [var.resource_definition_id_prefix]
}

run "rejects_empty_driver_type" {
  command = plan

  variables {
    driver_type = " "
  }

  expect_failures = [var.driver_type]
}

run "rejects_unknown_subject_kind" {
  command = plan

  variables {
    cluster_access_subject_kind = "ServiceAccount"
  }

  expect_failures = [var.cluster_access_subject_kind]
}

run "rejects_empty_subject_name" {
  command = plan

  variables {
    cluster_access_subject_name = ""
  }

  expect_failures = [var.cluster_access_subject_name]
}

run "rejects_cluster_values_without_name" {
  command = plan

  variables {
    cluster_values = { region = "eu-central-1" }
  }

  expect_failures = [var.cluster_values]
}

run "rejects_cluster_values_with_empty_name" {
  command = plan

  variables {
    cluster_values = { name = " " }
  }

  expect_failures = [var.cluster_values]
}

run "rejects_cluster_values_with_null_name" {
  command = plan

  variables {
    cluster_values = { name = null }
  }

  expect_failures = [var.cluster_values]
}
