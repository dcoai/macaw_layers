# 04 — Themes {#themes}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

**One theme system styles every surface, the site included** (decided, owner, 2026-10-25). It is visualize's theme document: palettes, named whole styles and **roles** (good, warning, bad, info, neutral, selected, muted …). macaw_server's brand tokens become a theme, and metresis maps its UI framework's roles from it.

## 1. Rules {#themes-rules}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

- **Drawing colors are theme roles and tokens,** and values derived from them (`lighten(:warning)`), so contrast is checked on the theme. (metresis.md C3.)
- **Data colors are typed content.** A `:color` column or a schema's value color (a team's color) may be shown only with a non-color cue (a glyph, a label or a dash) and under a contrast guard against the background; it is never the sole carrier of meaning ([macaw_data 01](https://gitlab.conet.yarina.org/dco-tek/macaw_data/-/blob/main/spec/01-sources.md#sources-data); macaw_compose#22, decision 7).
- **Literal colors are refused** under the **`:roles` profile**, which every Macaw page validates against. An adopter may offer a permissive profile standalone (visualize's `colors: :open`); on a Macaw page its documents validate as `:roles`.
- **One theme per page.** A component's own theme setting (a visualize design's `theme`) is an override the page masks; standalone, it applies.
- **Adopters register their theme roles** (visualize's mark roles) into the shared theme document, so one theme styles them.
- **Contrast is checked once, on the theme,** for every theme offered ([macaw_compose 10](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/10-web.md#web-a11y)).
- **Themes stack** like any fragment ([02](02-fragments.md#documents-fragments)).

## 2. Delivery {#themes-delivery}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

- A theme compiles to **custom properties scoped by a class**, `.mw-theme-<name>` (`.mw-theme-dark`), in the site's static stylesheet, served from `'self'`. Adopters emit the same class, so a visualize chart standalone and on a page reads the same properties.
- **"Auto"** follows `prefers-color-scheme` through a media query in that stylesheet; there is never a `<style>` element per component.
- Per-mark and per-datum styles resolve on the server into SVG presentation attributes or classes.
