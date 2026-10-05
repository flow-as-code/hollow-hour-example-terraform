# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Reachability over one FlowDoc's actions, for tests/fixtures/walks: the
# action ids a walk from var.start reaches when it follows every transition
# (next, each condition, each error), never out of an id in var.cut, and
# takes var.overrides as the successors of the ids it names (a Compare whose
# outcome is known). HCL has no loops, so the closure is built by doubling:
# r1 holds what each id reaches in one step, r2 in two, up to r128, more
# than any flow here has actions; converged says the last doubling added
# nothing.

variable "actions" {
  description = "A FlowDoc's content.Actions, as jsondecode reads them."
  type        = any
}

variable "start" {
  description = "The action id the walk starts from."
  type        = string
}

variable "cut" {
  description = "Action ids the walk may reach but never leave."
  type        = list(string)
  default     = []
}

variable "overrides" {
  description = "Successors to take for an action id in place of its transitions."
  type        = map(list(string))
  default     = {}
}

locals {
  succ = {
    for a in var.actions : a.Identifier => (
      contains(var.cut, a.Identifier) ? [] : lookup(var.overrides, a.Identifier, distinct(compact(concat(
        [try(a.Transitions.NextAction, "")],
        [for c in try(a.Transitions.Conditions, []) : c.NextAction],
        [for e in try(a.Transitions.Errors, []) : e.NextAction],
      ))))
    )
  }

  r1   = { for id, s in local.succ : id => distinct(concat([id], s)) }
  r2   = { for id, s in local.r1 : id => distinct(flatten([for j in s : lookup(local.r1, j, [j])])) }
  r4   = { for id, s in local.r2 : id => distinct(flatten([for j in s : lookup(local.r2, j, [j])])) }
  r8   = { for id, s in local.r4 : id => distinct(flatten([for j in s : lookup(local.r4, j, [j])])) }
  r16  = { for id, s in local.r8 : id => distinct(flatten([for j in s : lookup(local.r8, j, [j])])) }
  r32  = { for id, s in local.r16 : id => distinct(flatten([for j in s : lookup(local.r16, j, [j])])) }
  r64  = { for id, s in local.r32 : id => distinct(flatten([for j in s : lookup(local.r32, j, [j])])) }
  r128 = { for id, s in local.r64 : id => distinct(flatten([for j in s : lookup(local.r64, j, [j])])) }
}

output "reachable" {
  description = "Every action id reachable from var.start, var.start included."
  value       = toset(lookup(local.r128, var.start, [var.start]))
}

output "converged" {
  description = "True when 64 steps already reached everything 128 do."
  value       = toset(lookup(local.r128, var.start, [])) == toset(lookup(local.r64, var.start, []))
}
