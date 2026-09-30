# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Everything an environment chooses. The roots under environments/ set four of
# these (environment, hours, season, and the Region through their provider);
# the rest keep their defaults, so the roots stay identical but for
# terraform.tfvars.

variable "environment" {
  description = "The environment's name: part of every resource name, the instance alias and the tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,11}$", var.environment))
    error_message = "environment is a lowercase slug of at most 12 characters, such as dev, qa or prod."
  }
}

variable "hours" {
  description = "The hours profile every district crew keeps unless its districts entry names another: always_open (around the clock) or night_shift (4 pm to 6 am)."
  type        = string
  default     = "night_shift"

  validation {
    condition     = contains(["always_open", "night_shift"], var.hours)
    error_message = "hours is always_open or night_shift."
  }
}

variable "season" {
  description = "Which greeting module the hotline invokes, through that module's live alias: standard or halloween. Both greetings are always deployed; this chooses the one bound."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "halloween"], var.season)
    error_message = "season is standard or halloween."
  }
}

variable "districts" {
  description = <<-EOT
    The districts the hotline dispatches to, in keypad order: the first is
    key 1 in the district menu. Each gets a crew queue, a district flow and a
    queue-experience flow. overflow_to names the sibling crew a full queue
    spills to and must be another slug in this list. hours, when set, is the
    profile that district's crew keeps instead of var.hours.
  EOT
  type = list(object({
    slug        = string
    name        = string
    overflow_to = string
    hours       = optional(string)
  }))
  default = [
    { slug = "old-town", name = "Old Town", overflow_to = "harborside" },
    { slug = "harborside", name = "Harborside", overflow_to = "graveyard-hill" },
    { slug = "graveyard-hill", name = "Graveyard Hill", overflow_to = "old-town" },
  ]

  validation {
    condition     = length(var.districts) >= 2 && length(var.districts) <= 9
    error_message = "The menu takes one keypad digit per district, and overflow needs a sibling: 2 to 9 districts."
  }

  validation {
    condition     = length(distinct([for d in var.districts : d.slug])) == length(var.districts)
    error_message = "Each district slug appears once."
  }

  validation {
    condition     = alltrue([for d in var.districts : can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", d.slug))])
    error_message = "A district slug is lowercase letters, digits and dashes."
  }

  validation {
    condition = alltrue([
      for d in var.districts :
      d.overflow_to != d.slug && contains([for o in var.districts : o.slug], d.overflow_to)
    ])
    error_message = "Each overflow_to names another district in the list."
  }

  validation {
    condition     = alltrue([for d in var.districts : d.hours == null ? true : contains(["always_open", "night_shift"], d.hours)])
    error_message = "A district's hours, when set, is always_open or night_shift."
  }
}

variable "queue_max_contacts" {
  description = "The most contacts any one queue holds before a transfer takes its QueueAtCapacity branch. Null means 25 in prod and 2 elsewhere, so an operator can fill a dev or qa queue with two test contacts and hear the overflow path."
  type        = number
  default     = null

  validation {
    condition     = var.queue_max_contacts == null ? true : (var.queue_max_contacts >= 1 && floor(var.queue_max_contacts) == var.queue_max_contacts)
    error_message = "queue_max_contacts is null or a whole number of at least 1. A queue capped at 0 takes no contact, and an uncapped queue never takes QueueAtCapacity."
  }
}

variable "name_prefix" {
  description = "Prefix of every Lambda, IAM role, log group, queue and hours name, before the environment. It keeps this repository's resources apart from the TypeScript-first repository's (hh-<environment>-*) in a shared account. Never tfacc-: the provider's acceptance sweeper deletes those."
  type        = string
  default     = "hh-tf"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.name_prefix)) && !startswith(var.name_prefix, "tfacc")
    error_message = "name_prefix is a lowercase slug of at most 16 characters (so IAM role names stay under 64), and never starts tfacc: the provider's acceptance sweeper deletes those."
  }
}

variable "instance_alias" {
  description = "The Connect instance alias, which is also its sign-in domain and so unique across every account. Null means hollow-hour-tf-<environment>-<random suffix>."
  type        = string
  default     = null

  # CreateInstance's InstanceAlias: 1 to 45 characters, letters and digits in
  # runs joined by dashes, and never starting d- (the directory id prefix).
  # https://docs.aws.amazon.com/connect/latest/APIReference/API_CreateInstance.html
  validation {
    condition = var.instance_alias == null ? true : try(
      length(var.instance_alias) <= 45 &&
      can(regex("^[0-9A-Za-z]+(-*[0-9A-Za-z])*$", var.instance_alias)) &&
      !startswith(var.instance_alias, "d-"),
      false
    )
    error_message = "instance_alias is null or 1 to 45 letters, digits and inner dashes, starting and ending with a letter or digit, and not starting d-."
  }
}

variable "time_zone" {
  description = "The time zone of both hours profiles, as a tz database name (America/New_York, Europe/London, UTC)."
  type        = string
  default     = "America/New_York"

  # Connect takes a tz database name; this catches a typo such as a space or
  # an offset like -05:00 at plan, not whether the zone exists.
  # https://docs.aws.amazon.com/connect/latest/APIReference/API_CreateHoursOfOperation.html
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$", var.time_zone))
    error_message = "time_zone is a tz database name such as America/New_York or UTC."
  }
}

variable "log_retention_days" {
  description = "Retention, in days, of the instance's flow log group and of every Lambda log group."
  type        = number
  default     = 14

  # The values PutRetentionPolicy accepts. 0 (never expire) is left out on
  # purpose: bounded retention is why the module owns these groups.
  # https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_PutRetentionPolicy.html
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days is one of the values CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}

variable "manage_flow_log_group" {
  description = "Create the instance's flow log group, /aws/connect/<alias>, before the instance, with log_retention_days. False leaves the group to Connect, which keeps its logs forever until an operator sets retention with the AWS CLI (README.md, \"If Connect refuses the log group\")."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags added to every taggable AWS resource here, beside the roots' provider default_tags."
  type        = map(string)
  default     = {}
}
