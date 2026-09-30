# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The two hours profiles. Each district's flow checks the profile its crew
# keeps (local.district_hours), bound through the flow's refs as
# hours:<slug>, so switching a district, or the whole environment, between
# profiles changes a binding and never a flow's actions.
# https://docs.aws.amazon.com/connect/latest/adminguide/set-hours-operation.html
#
# always_open is 12:00 AM to 12:00 AM on every day, the admin guide's
# "Schedule for 24x7". night_shift is the living crews' 4 pm to 6 am, as two
# ranges per day, 12:00 AM to 6:00 AM and 4:00 PM to 12:00 AM, because
# Connect refuses a range that wraps midnight ("Start time: 16:0 cannot be
# greater than end time: 6:0"). Both were checked against a live instance
# (the TypeScript-first repository's VERIFY.md, rows H1 and H2).

locals {
  days = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]

  hours_profiles = {
    always_open = {
      description = "Open around the clock."
      ranges      = [{ start = 0, end = 0 }]
    }
    night_shift = {
      description = "Living crews: 4 pm to 6 am."
      ranges      = [{ start = 0, end = 6 }, { start = 16, end = 0 }]
    }
  }
}

resource "aws_connect_hours_of_operation" "profile" {
  for_each = local.hours_profiles

  instance_id = aws_connect_instance.this.id
  name        = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  description = each.value.description
  time_zone   = var.time_zone

  dynamic "config" {
    for_each = [
      for pair in setproduct(local.days, each.value.ranges) : {
        day   = pair[0]
        start = pair[1].start
        end   = pair[1].end
      }
    ]
    content {
      day = config.value.day
      start_time {
        hours   = config.value.start
        minutes = 0
      }
      end_time {
        hours   = config.value.end
        minutes = 0
      }
    }
  }

  tags = local.tags
}
