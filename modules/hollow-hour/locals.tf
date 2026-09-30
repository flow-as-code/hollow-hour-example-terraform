# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

locals {
  # hh-tf-dev: every Lambda, role, log group, queue and hours name starts here.
  name_prefix = "${var.name_prefix}-${var.environment}"

  tags = merge(var.tags, {
    "environment" = var.environment
  })

  # The flowascode provider has no default_tags, so the flows and modules
  # carry the roots' aws default tags explicitly, beside local.tags.
  flow_tags = merge({ "hollow-hour-example-terraform" = "true" }, local.tags)

  # The districts by slug, for for_each; var.districts keeps keypad order.
  districts = { for d in var.districts : d.slug => d }

  # The hours profile each district's crew keeps: its own, or the
  # environment's.
  district_hours = { for d in var.districts : d.slug => coalesce(d.hours, var.hours) }

  queue_max_contacts = coalesce(var.queue_max_contacts, var.environment == "prod" ? 25 : 2)

  instance_alias = coalesce(var.instance_alias, "hollow-hour-tf-${var.environment}-${random_id.alias_suffix.hex}")
}
