# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# One crew queue per district, and the three shared queues.
#
# Every queue is capped at local.queue_max_contacts, so QueueAtCapacity can
# fire; an uncapped queue never takes that branch.
# https://docs.aws.amazon.com/connect/latest/adminguide/set-maximum-queue-limit.html
#
# Queues keep always_open: the flows gate on hours explicitly through their
# hours:<slug> references, so a queue's own hours never decide routing, and a
# change of hours profile or season touches no queue.

locals {
  shared_queues = {
    "lantern-crew"      = "The Lantern Crew: Hostile and Chorus grades."
    "dispatch-overflow" = "Fallback when every other route errors or is full."
    "the-dead"          = "The Queue of the Dead, staffed by spectral liaisons."
  }
}

resource "aws_connect_queue" "crew" {
  for_each = local.districts

  instance_id           = aws_connect_instance.this.id
  name                  = "${local.name_prefix}-${each.key}-crew"
  description           = "${each.value.name} crew."
  hours_of_operation_id = aws_connect_hours_of_operation.profile["always_open"].hours_of_operation_id
  max_contacts          = local.queue_max_contacts

  tags = local.tags
}

resource "aws_connect_queue" "shared" {
  for_each = local.shared_queues

  instance_id           = aws_connect_instance.this.id
  name                  = "${local.name_prefix}-${each.key}"
  description           = each.value
  hours_of_operation_id = aws_connect_hours_of_operation.profile["always_open"].hours_of_operation_id
  max_contacts          = local.queue_max_contacts

  tags = local.tags
}
