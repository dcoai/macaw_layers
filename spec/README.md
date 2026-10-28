# macaw_layers specification

`macaw_layers` is Macaw's document layer: the document kernel every declarative value is read through, fragments and stacking, stores, and themes. Each Macaw component has its own spec in its own repository (dco-tek/macaw_compose#61); this is `macaw_layers`'s. The family's overview, vocabulary and open questions, and the specs of components without a repository of their own yet, are in [macaw_compose's spec](https://github.com/dcoai/macaw/blob/main/spec/README.md).

| File | Covers | Status |
|---|---|---|
| [00 — Overview](00-overview.md) | what `macaw_layers` holds, what it depends on, the order it is built in | |
| [01 — The document kernel](01-kernel.md) | names, vocabularies, faults and the formatter, version lines, the gates, the forms and tags, the digest, untrusted strings | §1–§7 implemented (v0.1.0); §8 is macaw_compose#100 |
| [02 — Fragments and stacking](02-fragments.md) | fragments, composites, use sites, stacking, masks, `explain` | order-of-work step 7 (#94) |
| [03 — Stores and references](03-stores.md) | the store behavior, references, bundles, ids on object storage | order-of-work step 7 (#94) |
| [04 — Themes](04-themes.md) | rules and delivery | order-of-work step 7 (#94) |

Sections keep the anchors they had in the family spec (`documents-*`, `stores-*`, `themes-*`), so links into them stay stable.
