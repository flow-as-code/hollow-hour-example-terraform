# tools/equivalence

**A CI check, not a deploy step.** Nothing in this directory is needed to
plan or apply an environment, and it is the only place in the repository
that uses Node.

It shows that `modules/hollow-hour` deploys the same flows as the
TypeScript-first repository,
[flow-as-code/hollow-hour-example-typescript](https://github.com/flow-as-code/hollow-hour-example-typescript),
bound to the same resources, in every deploy profile: dev, qa and prod from
their committed `terraform.tfvars`, and prod-october (prod with `hours =
"always_open"` and `season = "halloween"`).

1. `harness/` is a root that calls the module with placeholder credentials
   and every `skip_` flag, and takes the profile as `-var` flags.
   `check.mjs` plans it once per profile (offline: resources that do not
   exist yet need no API call) and reads the `flowdoc` the flowascode
   provider computes for every flow and module.
2. Each is compared with the FlowDoc of the same name in `snapshot/`,
   vendored byte for byte from the TypeScript-first repository at the
   commit `snapshot/SOURCE.md` records: the same eighteen names, and per
   document the same kind, Connect type, start action, module settings,
   references (as `${cdref:...}` tokens) and every action's Identifier,
   Type, Parameters and Transitions, in order. Descriptions and canvas
   layout are not compared.
3. Tokens alone cannot show that a flow binds `queue:lantern-crew` to the
   Lantern Crew's queue rather than another. So `check.mjs` plans a
   temporary copy of the module in which every `refs` value is rewritten to
   a name the plan knows (a queue's or hours profile's `name`, a Lambda's
   `function_name`, a flow's `name`, a greeting alias as
   `<module name>@live`), and compares each flow's bindings with the
   TypeScript-first repository's `refs/<profile>.tfmap.json` for the same
   profile, its `hh-<environment>-*` names read as `hh-tf-<environment>-*`.
   A swapped queue, a swapped Lambda or a greeting fixed to one season
   fails it; so does a binding the rewrite cannot name. A key that map
   binds and no flow uses (`hours:closed`, which only a scenario
   substitutes) must still name a queue, hours profile or Lambda the
   module plans.
4. The single-resource `*.flow.tf` files are also read by
   `@flow-as-code/hcl`, the reader flow-cli and the studio use, and must
   give the same documents.
5. `@flow-as-code/core` checks every document is a valid FlowDoc and lints
   the planned set.

```sh
npm ci
node check.mjs                    # exit 0: equivalent
node check.mjs --write <dir>      # also write prod's planned FlowDocs, for flow-cli or the studio
```

It needs Node 22.12 or later and `tofu` on PATH (or `TOFU=<path>`). It
clears every `AWS_*` variable before calling `tofu`, so no profile or role
in your shell is used.
