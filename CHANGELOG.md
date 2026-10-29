# Changelog

## Unreleased

**Breaking:** every digest changes.

- The kernel's digest is over the value itself, any data term, not its map form (spec/01 §7, #3, macaw#188): a type-tagged canonical encoding of the term, so identity no longer needs a representation. `1`/`1.0`, `:a`/`"a"`, `{:a}`/`[:a]` and a `DateTime`'s zone all count. A function, PID, reference, port or improper list raises.

**Breaking:** validity is judged on the value, and `Form` is the JSON adapter (spec/01 §5–§6, spec/03 §3.2–§3.3, spec/04 §5, #9, macaw#188).

- `Macaw.Layers.Document.validate/1` now receives the type's value (atom keys where the type has keys, string names, atoms, times, its own structs), never the map form. `Document.check(value, type)` judges a value with no encoding and no limits: how a value built in Elixir is judged. `Document.read/3` is removed.
- The gates move to the JSON adapter: `Form.gates(input, type, opts)` (bytes, scan, version, migration, recount, with `limits:` as before) gives the map form at the current version, and `Form.read(input, type, opts)` reads the value from it and checks it. The recount is now a gate of its own: its faults stop the read before the type's. `Form.from_json/3` is removed (use `Form.read/3`); `Form.to_json/2` stamps `"$version"` for a type with a version line.
- `Bundle.validate/1` judges a `%Bundle{}`; `Bundle.check(bundle, types)` adds each entry's kind. `Bundle.from_map/3` and `from_json/3` report the map form's own faults, then the entries' reads, then the term's check. `Store.relocate/3` checks the bundle term instead of writing it to its map form and reading it back, so a bundle read under a raised limit relocates.
- `Theme.Document.from_map/2` judges the value with no form written or read and takes no `limits:` (they are `from_json/2`'s); `Theme.Document.validate/1` judges the envelope value, so a key beside `theme` is named by its atom.

## v0.2.4 (2026-10-29)

Additive: the hooks visualize needs to adopt the cascade and composites (macaw#179, macaw#183, visualize#963), and a load-order fix.

- A host may raise a named limit, explicitly: `Limits.new(items: {:raise, 500_000})`, also through `read/3`'s `limits:`; a plain value above the default still raises (spec/01 §5, #7, macaw#183).
- The composite's hooks (spec/02 §8, #6, macaw#179): a type may `scope/3` each site's contribution by the composite node's own keys (visualize's `defaults`), and `place_whole/2` a keyed site's contribution of no kind under the site's key. spec/02 §8 says which keys a composite node holds.
- The cascade's hooks (spec/02 §3.3, #5, macaw#179): a fragment type may `normalize/4` a key both fragments hold (a shorthand against a part merges as the part) and trim with `under/3` what of a lower node a higher one keeps (a node whose type changes); both hold in `compose/3`, `stack/2` and `explain/2`. A trim is a replacement, so a stack where one happens is its left fold. `explain/2` reports a normalized part's leaf with the layer that set it.
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
