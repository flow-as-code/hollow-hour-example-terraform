# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The environment's own Amazon Connect instance, in the Region of the aws
# provider the root passes in. The alias is the instance's sign-in domain
# (<alias>.my.connect.aws), unique across every account, so it carries a
# random suffix unless var.instance_alias names one.
# https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-instances.html
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/connect_instance
#
# Nothing Tier 1 creates needs a user, a routing profile or a security
# profile, so none is made here. The provider returns once the instance is
# ACTIVE. The default quota is two instances per account and Region, and a
# create while another is pending can be refused (VERIFY.md).

resource "random_id" "alias_suffix" {
  byte_length = 3
}

resource "aws_connect_instance" "this" {
  instance_alias           = local.instance_alias
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  # Nothing in Tier 1 places an outbound call. It stays true to match the
  # TypeScript-first repository's instances (its envs/bootstrap/instances.tf),
  # so both approaches deploy the same instance settings and what was
  # checked live there holds here.
  outbound_calls_enabled    = true
  contact_flow_logs_enabled = true

  tags = local.tags

  # The flow log group exists, with its retention, before Connect first
  # writes to it (below). With manage_flow_log_group false there is none.
  depends_on = [aws_cloudwatch_log_group.connect_flow_logs]
}

# The instance's flow logs go to /aws/connect/<alias>, which Connect creates
# for itself when the instance is created, and which keeps logs indefinitely
# by default. https://docs.aws.amazon.com/connect/latest/adminguide/contact-flow-logs.html
#
# The choice: create the group here, before the instance, under the name
# Connect will use, so Connect finds it already there, retention is set from
# the first log line, and a destroy removes it after the instance. That works
# greenfield in one apply. The alternatives do not: an aws_cloudwatch_log_group
# created after the instance fails with ResourceAlreadyExistsException, and an
# import block needs the group to exist and its name to be known at plan time,
# neither of which holds before the first apply (the alias carries a random
# suffix). Adopting an instance created elsewhere is the one case for import;
# README.md, "Adopting an existing instance", has the block. Whether Connect
# reuses a group that already exists rather than refusing is recorded in
# VERIFY.md (T1) until a live create shows it.
#
# If it refuses, var.manage_flow_log_group = false is the fallback: no group
# here, Connect creates its own, and an operator sets its retention once with
# `aws logs put-retention-policy` after the first apply (README.md, "If
# Connect refuses the log group"). The AWS CLI is the only tool that needs.
resource "aws_cloudwatch_log_group" "connect_flow_logs" {
  count = var.manage_flow_log_group ? 1 : 0

  name              = "/aws/connect/${local.instance_alias}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}
