# Changelog

## Unreleased

- The cascade's hooks (spec/02 §3.3, #5, macaw#179): a fragment type may `normalize/4` a key both fragments hold (a shorthand against a part merges as the part) and name with `under/2` the keys of a lower node a higher one keeps (a node whose type changes); both hold in `compose/3`, `stack/2` and `explain/2`, and `under/2` reads only the higher node, so the cascade stays associative. `explain/2` reports a normalized part's leaf with the layer that set it.
- An optional callback is found whether or not its module is loaded: `Macaw.Layers.Callback.exported?/3`, used by `Form`, the cascade and every other site, replaces `Fragment.callback?/3`; CI refuses a bare `function_exported?/3` (spec/01 §9, #4, macaw#136).

## v0.2.3 (2026-10-28)

- The macaw logo in the docs and the README (macaw#175).
- Tests check "makes no atom" on the input's own names, never the node's atom count, and a test forbids the count (#1).

## v0.2.2 (2026-10-28)

- The README opens with the early-release notice (macaw#174).

## v0.2.1 (2026-10-28)

- Spec and README links to the public home, `github.com/dcoai/macaw_layers`, and the install snippet from Hex (macaw#171, #173).
- Package metadata for Hex: the public home, the changelog link, the files shipped, and docs with `ex_doc` (macaw_compose#155).

## v0.2.0 (2026-10-27)

- macaw_layers v0.2.0: fragments and stacking, stores and bundles, colors and themes (macaw_compose#94)

## v0.1.0 (2026-10-27)

- macaw_layers v0.1.0: the document kernel (macaw_compose#56): names, vocabularies, faults, version lines, the gates, the forms and tags, the digest
