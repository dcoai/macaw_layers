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
- `Macaw.Layers.Color.Form` is public, the colors' JSON adapter (`tags/0`, `encode_value/1`, `decode_value/2`), with the tag `$rgb` for a literal: the hex string when 8-bit exact, else `[r, g, b, a]`. A theme document's tag table lists it. (Text as a color goes in #12, below.)
- `Color.name?/1`: the grammar of a theme's names (lower-case letters, digits and `_`, starting with a letter), the one its stylesheet names were already held to.

**Breaking:** a string is never a color; a theme holds color terms; theme JSON version 2 (spec/04 §1.3–§1.4, §2.1–§2.6, §3.1–§3.4, §4–§6, #12, macaw#188).

- `Color.value?/1` no longer accepts a string: a literal is `%Color{}` where `Color.literal?/1` holds, so `value?("#fff")` is false, and a transform's operand is a color value, never text. The helpers (`intensity/2`, `alpha/2`, `blend/1`, `contrast/1`, `shade/2`, …) raise for text, naming `Color.parse!/1` and `~RGB`. `saturate/2` of a literal keeps its HSL meaning; the transform of a literal is the tuple `{:saturate, c, t}`. `Color.Form` writes and reads operands and pinned steps in their own forms (`$rgb`), never bare strings.
- `%Theme{}` holds terms: `series` and the furniture are literals, and so are the ramps' anchors, `colors` entries and pinned steps, transforms' operands and style paint colors where they are literal. The built-ins are written with `~RGB` and resolve, compile and check exactly as before. `Theme.new/1` and `merge/2` raise for text in a color field (`Theme.new(axis: "#555")` raises naming `Color.parse!/1` and `~RGB`); text in a `colors` entry, a pinned step, an anchor or a style's `fill`/`stroke` color is a contract fault naming them; an extension's color default that is text raises naming the extension.
- `Theme.resolve(theme, slot, :literal)`, `Color.resolve(v, theme, :literal)`, `Theme.ramp/3`, `Theme.ink/2` and `Theme.data_color/2`'s `{:ok, c}` answer `%Color{}`; `:css` writes each literal by `Color.to_css/1`, so every `var()` reference and the stylesheet are byte for byte as before. A transform's literal stays quantized to 8 bits. `Theme.ink/2` takes a `%Color{}` or `nil` and raises for text. `Theme.check_color/2` raises for a term that is no color value, text included; `Theme.data_color/2` answers `{:error, :unreadable}` for text.
- `Theme.Document` is at version 2: a literal is tagged `$rgb`. The step from version 1 tags each string at a color position that `Color.parse/1` reads (the series, the furniture, ramp anchors, `colors` entries, `$steps` values, transform, `$contrast` and `$blend` operands, style `fill`/`stroke` colors), so a v0.2.4 document, and a bundle's entry of one, reads to the same theme; other text is refused at its path, a series entry or furniture as `{:type, :color}` (was `{:type, :string}`).
- Removed: `Color.Typed.unreadable/1` and `readable?/1` (internal), whose only use was text as a color.

**Breaking:** a theme's names are strings, one key per spelling; words as given; the vocabulary is the JSON reader's (spec/04 §1.3, §1.6, §2.1–§2.6, §3.4, §5, spec/01 §5–§6, #13, macaw#188, macaw#181).

- Every name inside `%Theme{}` is a string, the library's, its extensions' and a host's alike: the keys of `ramps`, `colors`, `styles` and `defaults`, the built-in palettes and colors, the slots and the name in every typed color (`{:color, "good"}`, `{:ramp, "status", 0.5}`). The lists answer strings: `slots/1`, `color_slots/1`, `color_names/1` (now plainly sorted), `style_names/1`, `ramp_names/0`, `role_names/0`, `series_slot/2`, and `check/1`/`violations/1` subjects (`{:ramp, "status"}`), `floors/1` faults (`{"text", …}`, `{"surface", {:equal, "grid"}}`) and fault messages name them so. Every function that takes a name still takes either spelling.
- Atom input is normalized once, at construction (`Theme.new/1`, `merge/2`, `Theme.Document`'s read), by one function: `colors: %{"info" => c}` is the library's `"info"`, **the host's value winning** — before, the library's `:info` silently shadowed a host's `"info"` (macaw#181) — and likewise a ramp `"status"` or a style `"muted"`. A typed color's name normalizes wherever it stands (ramp anchors, `colors` entries, pinned steps, style nodes, `defaults`), so a ramp anchor `{:color, :brand}` is `{:color, "brand"}` and round-trips through JSON. One name given both as its atom and its string in one map raises `ArgumentError`; in a document value it is `{:duplicate, :name}` at `[:theme, map, name]`.
- `Color.color/1` and `Color.ramp/2` build the name's string (`color(:red)` is `{:color, "red"}`), and `Color.Form` reads `$color` and `$ramp` names as strings, never atoms: a typed color built in Elixir is the value its JSON form reads back.
- Words are kept as given: `Theme.new/1` no longer turns a style's or a default's keys and atom values outside the library's vocabulary into strings (`curve: %{type: :monotone_x}`, `font: %{line_height: 1.2}` stay atoms). `Theme.Words` holds only words now, no names.
- The vocabulary is the JSON reader's: `Form.read/3`, `from_map/3`, `to_map/3` and `to_json/3` take `vocabulary: %{keys: [...], atoms: [...]}`, merged over the type's tables for that call; no atom is made from a document beyond them. `Theme.Extension` gains an optional `words/0`; `Theme.Document.to_json/1` writes with the theme's extensions' words and `from_json/2` reads with the `extensions:` given, so **`from_json` needs `extensions:` for an adopter's words** (without them an adopter's atom value is `{:enum, allowed}` at its path). An extension's `styles/0` and `colors/0` may name by atom or string; the theme holds them as strings.
- `Theme.Document`'s read path is the theme's normalization (its library-spelling-to-atom reading and the style-series name table are gone); `Table.spelled/2`'s either-way search is gone, and `Color.Names.atoms/0` (internal) is removed.

**Breaking:** a theme's own name and its `dark` and `light` are strings (spec/04 §2.1, §2.5, §5, #16).

- `%Theme{}`'s `name`, `dark` and `light` are strings, the built-ins' included: `Theme.default().name` is `"default"` (was `:default`), `default().dark` `"dark"`, `dark().light` `"default"`, `color_safe/0` and `print/0` named `"color_safe"` and `"print"`. Atom input is normalized once, at construction (`new/1`, `merge/2`, a document read), so `new(name: :house)` and `new(name: "house")` are one theme and `new(dark: :dark)` is `new(dark: "dark")`. `Theme.builtin/1` takes either spelling (`builtin("dark") == builtin(:dark)`); `Theme.builtins/0` (internal) answers strings. Fault messages name the theme as its string (`theme "default": …`).
- `Theme.Document` writes the three as JSON strings (`"dark": "dark"`, where it wrote `{"$atom": "dark"}`) and reads them as strings; a version 1 (v0.2.4) document's `{"$atom": "dark"}` migrates to `"dark"` in the step to version 2, and is refused at version 2; a `name` that is not a string is `{:type, :string}`. The stylesheet's theme classes are unchanged (`.mw-theme-color-safe`).

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
