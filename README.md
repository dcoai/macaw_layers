<img src="brand/logo/macaw_scarlet.svg" alt="The Macaw logo, a scarlet macaw in flight" width="128">

# macaw_layers

> **This software is a very early release, and not ready for general use.**

Public home: [github.com/dcoai/macaw_layers](https://github.com/dcoai/macaw_layers) · Docs: [hexdocs.pm](https://hexdocs.pm/macaw_layers)

Macaw's document layer ([spec/00](https://github.com/dcoai/macaw_layers/blob/main/spec/00-overview.md)): the document kernel every declarative value is read through, fragments and stacking, stores and portable bundles, and colors and themes (dco-tek/macaw_compose#56, #94).

| Module | What it is |
|---|---|
| `Macaw.Layers.Names` | names a document declares: strings, never atoms made from data ([spec/01 §1](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-names)) |
| `Macaw.Layers.Vocabulary` | closed vocabularies looked up by spelling ([spec/01 §2](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-vocabulary)) |
| `Macaw.Layers.Fault` | the fault `{path, reason}`, its order, and the one formatter ([spec/01 §3](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-faults)) |
| `Macaw.Layers.Version` | one version line per document type, and stepwise migration ([spec/01 §4](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-versions)) |
| `Macaw.Layers.Document`, `Macaw.Layers.Limits`, `Macaw.Layers.Scan` | the gates a document is read through, in order: bytes, a scan that stops at a limit, decode, version, migrate, validate and recount ([spec/01 §5](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-gates)) |
| `Macaw.Layers.Form`, `Macaw.Layers.Tags` | the value, map and JSON forms, exact inverses, and each type's table of `$` tags ([spec/01 §6](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-forms)) |
| `Macaw.Layers.Document.digest/1` | a canonical digest of a document's map form, independent of key order ([spec/01 §7](https://github.com/dcoai/macaw_layers/blob/main/spec/01-kernel.md#kernel-digest)) |
| `Macaw.Layers.Fragment` | the fragment-type behavior, compose, stack, explain, kinds and ids ([spec/02 §1–§3, §6](https://github.com/dcoai/macaw_layers/blob/main/spec/02-fragments.md#fragments-types)) |
| `Macaw.Layers.Var`, `Macaw.Layers.Use`, `Macaw.Layers.Composite` | variables and binding, use sites and masks, composites flattened at deployment ([spec/02 §4–§9](https://github.com/dcoai/macaw_layers/blob/main/spec/02-fragments.md#fragments-masks)) |
| `Macaw.Layers.Store`, `Macaw.Layers.Store.Memory` | the store behavior, typed ids and import as a relocation; the default in-memory store ([spec/03 §1–§2, §3.3](https://github.com/dcoai/macaw_layers/blob/main/spec/03-stores.md#stores-behavior)) |
| `Macaw.Layers.Bundle` | a portable closure of documents, its forms and provenance ([spec/03 §3](https://github.com/dcoai/macaw_layers/blob/main/spec/03-stores.md#stores-portable)) |
| `Macaw.Layers.Color`, `Macaw.Layers.Color.Vision` | colors, OKLab with gamut mapping, typed colors and their resolution; color-vision simulation ([spec/04 §1](https://github.com/dcoai/macaw_layers/blob/main/spec/04-themes.md#themes-color)) |
| `Macaw.Layers.Theme`, `Macaw.Layers.Theme.Extension` | the theme: the color table, ramps and roles, the style palette, contracts and floors, resolution, the ink, extensions and the profile ([spec/04 §2–§4](https://github.com/dcoai/macaw_layers/blob/main/spec/04-themes.md#themes-theme)) |
| `Macaw.Layers.Theme.Document`, `Macaw.Layers.Theme.Sheet` | a theme as a document, and compiled to a stylesheet of `--mw-` custom properties ([spec/04 §5–§6](https://github.com/dcoai/macaw_layers/blob/main/spec/04-themes.md#themes-document)) |

No runtime dependencies. From Hex:

```elixir
{:macaw_layers, "~> 0.2.4"}
```

Part of [Macaw](https://github.com/dcoai/macaw).
