# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# prod: the night shift, standard greeting. The only file that differs
# between environments/dev, qa and prod.
#
# October is these two lines changed as below (the prod-october profile the
# tests and the equivalence check plan), and rollback is reverting them
# (README.md, "The season"):
#   hours  = "always_open"
#   season = "halloween"

environment = "prod"
aws_region  = "us-east-1"
hours       = "night_shift"
season      = "standard"
