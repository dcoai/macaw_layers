# Changelog

## Unreleased

**Breaking:** every digest changes.

- The kernel's digest is over the value itself, any data term, not its map form (spec/01 §7, #3, macaw#188): a type-tagged canonical encoding of the term, so identity no longer needs a representation. `1`/`1.0`, `:a`/`"a"`, `{:a}`/`[:a]` and a `DateTime`'s zone all count. A function, PID, reference, port or improper list raises.

**Breaking:** validity is judged on the value, and `Form` is the JSON adapter (spec/01 §5–§6, spec/03 §3.2–§3.3, spec/04 §5, #9, macaw#188).

- `Macaw.Layers.Document.validate/1` now receives the type's value (atom keys where the type has keys, string names, atoms, times, its own structs), never the map form. `Document.check(value, type)` judges a value with no encoding and no limits: how a value built in Elixir is judged. `Document.read/3` is removed.
- The gates move to the JSON adapter: `Form.gates(input, type, opts)` (bytes, scan, version, migration, recount, with `limits:` as before) gives the map form at the current version, and `Form.read(input, type, opts)` reads the value from it and checks it. The recount is now a gate of its own: its faults stop the read before the type's. `Form.from_json/3` is removed (use `Form.read/3`); `Form.to_json/2` stamps `"$version"` for a type with a version line.
- `Bundle.validate/1` judges a `%Bundle{}`; `Bundle.check(bundle, types)` adds each entry's kind. `Bundle.from_map/3` and `from_json/3` report the map form's own faults, then the entries' reads, then the term's check. `Store.relocate/3` checks the bundle term instead of writing it to its map form and reading it back, so a bundle read under a raised limit relocates.
- `Theme.Document.from_map/2` judges the value with no form written or read and takes no `limits:` (they are `from_json/2`'s); `Theme.Document.validate/1` judges the envelope value, so a key beside `theme` is named by its atom.

The JSON adapter tells a name map from a node by the type's positions (spec/01 §6, spec/02 §9, spec/04 §5, #10, dco-tek/macaw/macaw#184).

- An optional `Form` callback, `name_map?(path)`: whether the map at `path` holds names, never the type's keys. At a name map a string key is written and read as the name, whatever its spelling (a style named `"fill"`, a scale `"x"`), escaped as before when it starts with `$`; an atom key there is `{:type, :name}`, since names are strings. At a node, and for a type without the callback, keys are as before.
- `Fragment.name_map?(type, path)`, from the type's specs: a `:union` or `:deep` key holds a name map whose entries are nodes of its `element` kind, for a fragment type to implement the callback in one line.
- **Breaking:** `Theme.Document`'s `ramps`, `colors`, `styles` and `defaults` are name maps, and its value spells every name in them as a string: `node/1`, `fragment/1` and `to_map/1` write `"info"` where they wrote `:info`. `from_map/2` and `from_json/2` read a library spelling back as its atom in one place, so the theme read is unchanged, its JSON form is unchanged, and a theme entry of a store goes through a bundle's forms and import. A node with atom names still reads; `Form.to_map/2` of one is `{:type, :name}` at each.
- A use site's `local` is a fragment of the type: `Form.encode_term/3` takes the term's place below its tag (`at`), the reader asks `name_map?/1` at `{:tag, tag}` and the path within the payload, and `Fragment.name_map?/2` places a `$use` local at the root's positions, so a local holding a style named `"fill"` round-trips.

**Breaking:** `%Macaw.Layers.Color{}` fields are floats (spec/04 §1.1, §1.6, #11, macaw#188).

- A literal color is a term: every constructor (`rgb`, `hsl`, `lab`, `hcl`, `oklab`, `oklch`, `parse`, the manipulations and interpolations) builds `%Color{}` with every field a float, clamped, never a negative zero, so equal colors are one term and one digest whatever built them. `hsl`, `lab` and `hcl` still round their channels, now held as floats; `interpolate_rgb/3` clamps its result. A struct written with integer fields still compares `==` but is not `Color.literal?/1` and has another digest. `to_rgb/1` and `to_hex/1` are unchanged.
- The adapters: `Color.parse!/1` (raises `ArgumentError` naming the text) and the compile-time sigil `~RGB"#3b6fa8"` (unreadable text is a `CompileError`) in; `Color.to_css/1` out, hex where the color is 8-bit exact (`Color.exact?/1`), else `rgb(r g b / a)`, which `parse/1` now reads (CSS Color 4's space-separated `rgb()`).
- `Macaw.Layers.Color.Form` is public, the colors' JSON adapter (`tags/0`, `encode_value/1`, `decode_value/2`), with the tag `$rgb` for a literal: the hex string when 8-bit exact, else `[r, g, b, a]`. A theme document's tag table lists it. How a string is read as a color is unchanged for now.
- `Color.name?/1`: the grammar of a theme's names (lower-case letters, digits and `_`, starting with a letter), the one its stylesheet names were already held to.

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
