# modules/hollow-hour

The entire Hollow Hour environment: an Amazon Connect instance and
everything in it, in the Region of the `aws` provider the caller passes.
The roots under `environments/` call it with four values; everything else
has a default.

| Input                | Default                                     | What it chooses                                                                                           |
| -------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `environment`        | (required)                                  | part of every name, the instance alias and the tags                                                       |
| `hours`              | `night_shift`                               | the profile district crews keep: `always_open` or `night_shift`                                           |
| `season`             | `standard`                                  | the greeting the hotline invokes: `standard` or `halloween`                                               |
| `districts`          | Old Town, Harborside, Graveyard Hill        | keypad order, `overflow_to` a sibling, optional per-district `hours`; 2 to 9 entries                      |
| `queue_max_contacts` | 25 in prod, 2 elsewhere                     | the cap that makes QueueAtCapacity reachable                                                              |
| `name_prefix`        | `hh-tf`                                     | the start of every Lambda, role, log group, queue and hours name                                          |
| `instance_alias`     | `hollow-hour-tf-<environment>-<random hex>` | the instance's sign-in domain                                                                             |
| `time_zone`          | `America/New_York`                          | both hours profiles                                                                                       |
| `log_retention_days` | 14                                          | the instance's flow log group and every Lambda log group; a value CloudWatch Logs accepts                 |
| `manage_flow_log_group` | `true`                                   | create `/aws/connect/<alias>` before the instance; `false` leaves it to Connect (VERIFY.md, T1)           |
| `tags`               | `{}`                                        | added to every taggable AWS resource, and to every flow and module                                        |

Every input AWS would refuse at apply is refused at plan: the alias rules
of CreateInstance, the retention values of PutRetentionPolicy, a queue cap
below 1, a time zone that is not a tz name, and a `name_prefix` that is not
a short slug or starts `tfacc`.

Outputs: `instance_id`, `instance_arn`, `instance_alias`, `flow_log_group_name`, `season`,
`district_hours`, `lambda_function_names`, `flow_names`, `recording_bucket`,
`greeting_live_arns`, and, for the tests and the equivalence check,
`flow_refs` and `flowdocs`.

It configures no provider. The caller configures `aws` and `flowascode`
for one Region; `archive` and `random` need no configuration.
