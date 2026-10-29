# 00 — Overview {#layers-overview}

## 1. What macaw_layers holds {#layers-holds}

`macaw_layers` is Macaw's document layer ([macaw_compose 00 §4](https://github.com/dcoai/macaw/blob/main/spec/00-overview.md#overview-packaging)):
- **the document kernel** ([01](01-kernel.md)): names, closed vocabularies, faults and their formatter, version lines and migration, the gates, the map and JSON forms with the `$` tag table, and the digest;
- **fragments and stacking** ([02](02-fragments.md)): fragments, composites, use sites, `stack/1` and `compose/2`, masks and `explain/1`;
- **stores and references** ([03](03-stores.md)): the store behavior, typed references, and bundles;
- **themes** ([04](04-themes.md)): the theme document, roles, and stylesheet compilation.

It knows nothing of pages, components, state or data. Those belong to `macaw_compose` and `macaw_data`, which depend on it.

## 2. Terms are the form {#layers-terms}

**A value is a BEAM term, and its encodings are adapters** (dco-tek/macaw/macaw#188, from v0.3.0):
- **Identity is the term's.** The digest is over the value itself, by a type-tagged canonical encoding ([01 §7](01-kernel.md#kernel-digest)), so two values are one exactly when they are one term, whatever wrote them.
- **Validity is the term's.** A type judges its value, never a representation of it: `Document.check/2` judges a value built in Elixir, and a document read from elsewhere is judged the same way once read ([01 §5](01-kernel.md#kernel-gates)).
- **Each value has one form.** A name is a string; a literal color is `%Color{}` ([04 §1](04-themes.md#themes-color)); a theme's names are strings ([04 §2.1](04-themes.md#themes-slots)). No value is held in two spellings, so equality, digests and lookups need no either-way search.
- **JSON is an adapter at the edge.** `Macaw.Layers.Form` writes and reads the map and JSON forms, with the gates, the version line, the tag table and the reader's vocabulary ([01 §6](01-kernel.md#kernel-forms)); what an encoding cannot write, or what reading one may make (an atom), is the adapter's limit, never the value's.

## 3. Dependencies {#layers-dependencies}


None at runtime beyond Elixir (1.18 or newer, for its built-in `JSON`) and OTP. There is no Phoenix and no other Macaw library, so an adopter using no other Macaw library (visualize, standalone) can depend on it alone. In dev and test only: `stream_data` for properties and `surfex`, which keeps spec, tests and code aligned.

## 4. Order of work {#layers-order}

Built in the family's order of work ([macaw_compose 00 §5](https://github.com/dcoai/macaw/blob/main/spec/00-overview.md#overview-order)), which puts first what adopters consume:
1. **the document kernel** (step 2, macaw_compose#56): names, vocabularies and faults (#95), version lines (#96), the gates (#97), the forms (#98) and the digest (#99), tagged v0.1.0; then untrusted strings and the URL policy (#100);
2. **themes and the fragment machinery** (step 7, macaw_compose#94).

Each is released by git tag. An adopter published on Hex (visualize) switches when `macaw_layers` is published on Hex, keeping its own definitions meanwhile ([macaw_compose 00 §5](https://github.com/dcoai/macaw/blob/main/spec/00-overview.md#overview-order)).
