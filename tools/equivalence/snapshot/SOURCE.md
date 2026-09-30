# Snapshot source

The files in this directory are copied byte for byte from the
TypeScript-first repository,
[flow-as-code/hollow-hour-example-typescript](https://github.com/flow-as-code/hollow-hour-example-typescript),
at commit `04e4995c7a9647d7631c76be75b6075567575276` (2026-09-30). Its
`flows/` and `seasonal/` FlowDocs are unchanged since `c3a50dd`.

- `flows/*.flowdoc.json` and `seasonal/*.flowdoc.json`, twelve files: the
  content `check.mjs` compares the module's flows against.
- `refs/dev.tfmap.json`, `refs/qa.tfmap.json`, `refs/prod.tfmap.json` and
  `refs/prod-october.tfmap.json`, as `<profile>.tfmap.json`: which Terraform
  address each reference key binds to in each profile there. `check.mjs`
  reads each address as the resource name it carries in that repository
  (`hh-<environment>-*`, from its `envs/*/supporting.tf`, `lambdas.tf` and
  `seasonal-*/greetings.tf`), with this repository's prefix
  (`hh-tf-<environment>-*`), and compares it with what the module binds.

They are never edited here.

To move the snapshot forward, copy the same files from a newer commit of that
repository, update the commit above, and run `node check.mjs`. A difference
it then reports is a change of behavior in one repository that the other
has not made yet. If that repository renames a resource or adds a kind of
binding, `expectedBindings` in `check.mjs` moves with it.
