# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The release of hh-offer-callback (hh-offer-callback.flow.tf): a version
# and a live alias, the shape the greetings carry in hh-greeting.tf. The
# district flows bind module:hh-offer-callback@live to the alias ARN, as
# the TypeScript-first repository's emitter does for its in-set module (its
# tasks/T2-full-moon.md, Deviations: the typed Refs.module takes an alias).
# It lives apart from the module's file because flow-cli reads a .flow.tf
# that holds exactly one resource.

# A version is a snapshot of the module's current content, replaced whenever
# that content changes. create_before_destroy makes the new version exist
# before the old one goes, and the alias moves to it in place in between:
# Connect refuses to delete a version an alias still points at.
resource "flowascode_contact_flow_module_version" "hh_offer_callback" {
  instance_id            = aws_connect_instance.this.id
  contact_flow_module_id = flowascode_contact_flow_module.hh_offer_callback.contact_flow_module_id
  content_hash           = flowascode_contact_flow_module.hh_offer_callback.content_hash
  description            = "${flowascode_contact_flow_module.hh_offer_callback.name} as reviewed (${var.environment})"

  lifecycle {
    create_before_destroy = true
  }
}

# The alias is what the district flows bind: its arn is the module ARN
# qualified by the alias id, the only form Connect runs as the alias.
resource "flowascode_contact_flow_module_alias" "hh_offer_callback_live" {
  instance_id                 = aws_connect_instance.this.id
  contact_flow_module_id      = flowascode_contact_flow_module.hh_offer_callback.contact_flow_module_id
  name                        = "live"
  contact_flow_module_version = flowascode_contact_flow_module_version.hh_offer_callback.version
  description                 = "The callback module as the district flows invoke it"
}
