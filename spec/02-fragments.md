# 02 — Fragments and stacking {#documents-fragments}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

visualize's fragment machinery moves into Macaw and is used by every stackable document: templates and layers, styles, themes and designs. It comprises:
- **fragments** and **composites;**
- **use sites,** resolved `ref → local → mask → bind → stack`;
- **`stack/1`,** a cascade, and **`compose/2`,** a union, each under **per-key merge rules** (`:concat`, `:union`, `:deep`, `:override`);
- **masks,** which explicitly drop keys from below;
- **`explain/1`,** provenance for any value: which layer or fragment set it.

(visualize.md C4, C7; macaw_compose#8.)
