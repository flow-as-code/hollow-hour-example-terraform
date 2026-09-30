# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What an operator reads after an apply, with `tofu output`. Never commit
# the values: the instance id and ARN carry the account.

output "instance_id" {
  description = "The Connect instance id."
  value       = module.hollow_hour.instance_id
}

output "instance_arn" {
  description = "The Connect instance ARN, the --context-id of its service quotas."
  value       = module.hollow_hour.instance_arn
}

output "instance_alias" {
  description = "The instance alias: sign in at https://<alias>.my.connect.aws/."
  value       = module.hollow_hour.instance_alias
}

output "season" {
  description = "The greeting the hotline invokes."
  value       = module.hollow_hour.season
}

output "district_hours" {
  description = "The hours profile each district's crew keeps."
  value       = module.hollow_hour.district_hours
}

output "lambda_function_names" {
  description = "The stub Lambdas, for logs and a manual invoke."
  value       = module.hollow_hour.lambda_function_names
}

output "flow_names" {
  description = "Every flow and module deployed."
  value       = module.hollow_hour.flow_names
}
