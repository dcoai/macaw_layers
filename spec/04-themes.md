# 04 — Themes {#themes}

<!-- surfex: deferred #134: the theme document -->

**One theme system styles every surface, the site included** (decided, owner, 2026-10-25). It is visualize's theme: palettes, named whole styles and **roles** (good, warning, bad, info, neutral), with the states (hover, focused, selected, active, disabled, muted, emphasis, breakpoint) and the furniture. macaw_server's brand tokens become a theme, and metresis maps its UI framework's roles from it. This file is visualize's color and theme (spec/08 §1, §7; spec/14 §2.5, §9.3; D-55, D-122, D-123, D-135, D-139, D-142, D-171–D-175, D-184, D-225, D-233), with what draws a chart left in visualize (macaw_compose#94; R11 of `design/visualize-alignment.md`):

- **the CSS names are Macaw's:** `--mw-<name>` properties under `.mw-theme-<name>`, which adopters emit too, so a visualize chart standalone and on a page reads the same properties;
- **adopters register** the palette names and color names they add (§3.4), from an explicit list, closed by default;
- **literal colors are a profile's** (§4): a Macaw page validates as `:roles`;
- **visualize keeps** its style defaults, its mark style parts, the palette's assignment to marks, its backends and its builder's theme editor.

Each section's tests are written as **`planned-test:` blocks** until its work item is built (macaw_compose#133–#135).

| Module | What it is |
|---|---|
| `Macaw.Layers.Color` | colors: the struct, parsing, conversions, manipulation, interpolation, OKLab and OKLCH, contrast, typed colors and their resolution (§1) |
| `Macaw.Layers.Color.Vision` | color-vision simulation (§1.8) |
| `Macaw.Layers.Theme` | the theme: slots, the color table, ramps and roles, the style palette, contracts, resolution, the ink, the built-ins, extensions, the profile (§2–§4) |
| `Macaw.Layers.Theme.Document` | a theme as a document of its own (§5) |
| `Macaw.Layers.Theme.Sheet` | a theme compiled to a stylesheet (§6) |

## 1. Color {#themes-color}

<!-- surfex: deferred #133: color -->

### 1.1 The struct and parsing {#themes-color-parse}

<!-- surfex: deferred #133: color -->

`%Macaw.Layers.Color{r, g, b, opacity}` with `r`, `g`, `b` in `[0, 255]` and `opacity` in `[0, 1]` (default `1.0`). Constructors round channels to integers; interpolation may leave them as floats.

`parse/1` trims and lower-cases its argument and returns a color or `nil`. A non-binary argument returns `nil`. Accepted syntaxes:
- **hex:** `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`. Short digits are doubled; an alpha byte becomes `opacity = a / 255`. Any other length after `#`, and a non-hex digit, return `nil` (visualize raised for a non-hex digit; a parser of untrusted text answers rather than raises);
- **`rgb(r, g, b)` and `rgba(r, g, b, a)`:** integer channels, optional decimal alpha, any whitespace around separators. Percentages are not accepted;
- **`hsl(h, s, l)` and `hsla(h, s, l, a)`:** decimal components, `%` optional on `s` and `l`;
- **named colors:** the 148 CSS color keywords (the 147 classic names plus `rebeccapurple`, with `gray` in both its spellings).

A string that matches none returns `nil`. `named/1` is the lower-case hex string for a keyword (case-insensitively) or `nil`; `named_colors/0` is the keyword list.

```planned-test:color-parse-forms
parse reads every hex length, rgb and rgba, hsl and hsla and the 148 keywords case-insensitively and trimmed; any other text, a bad digit and a non-binary are nil; named gives a keyword's hex
```

### 1.2 Constructors, conversions and manipulation {#themes-color-convert}

<!-- surfex: deferred #133: color -->

- **Constructors.**
  - `rgb/3,4` clamps channels to `[0, 255]` and opacity to `[0, 1]` without rounding.
  - `hsl/3,4` takes `h` in degrees (truncated and wrapped into `[0, 360)`), and `s` and `l` in `[0, 100]` (clamped), and rounds the channels.
  - `lab/3,4` takes CIE L\*a\*b\* and converts through XYZ with the reference white `Xn = 0.96422, Yn = 1, Zn = 0.82521` (the d3-color constants) to sRGB, clamped and rounded.
  - `hcl/3,4` takes hue in degrees, chroma and luminance, and converts through Lab (`a = c cos h`, `b = c sin h`).
- **Conversions.**

  | Function | What it gives |
  |---|---|
  | `to_rgb/1` | `{r, g, b}`, rounded integers |
  | `to_rgba/1` | `{r, g, b, opacity}` |
  | `to_hsl/1` | `%{h, s, l, opacity}`: `h` in `[0, 360)`, and `s` and `l` in `[0, 100]` |
  | `to_lab/1` | `%{l, a, b, opacity}`, through the D50-adapted matrix and white point of `lab/4`, so `lab/4` of `to_lab/1` is the color again and a gray has `a = b = 0` (visualize D-135) |
  | `to_hcl/1` | `%{h, c, l, opacity}` |
  | `to_hex/1` | `#rrggbb` in lower case, with `aa` appended when `opacity < 1` |
  | `to_string/1` | `rgb(r, g, b)`, or `rgba(r, g, b, opacity)` when translucent |

- **Manipulation.**
  - `brighter/1,2` and `darker/1,2` move Lab `L` by `18 k`, with `k` 1 by default.
  - `saturate/1,2` multiplies HSL saturation by `amount` (1.2 by default) on a `%Color{}`, and `desaturate/1,2` does the same at 0.8.
  - `rotate/2` adds degrees to the hue.
  - `grayscale/1` is `round(0.299 r + 0.587 g + 0.114 b)`, and `invert/1` is `255 − channel`.
  - `with_opacity/2` sets a clamped opacity.
  - `luminance/1` is the WCAG relative luminance, and `contrast/2` is `(L_light + 0.05) / (L_dark + 0.05)` in `[1, 21]`.
  - `mix/2` is `interpolate_rgb(c1, c2, 0.5)`.
- **Interpolation.**
  - `interpolate_rgb/3` is linear and unrounded.
  - `interpolate_hsl/3` and `interpolate_hcl/3` take the shorter hue arc.
  - `interpolate_lab/3` interpolates in Lab.
  - Every result other than RGB passes through its constructor and is rounded. `t` is not clamped.
- **OKLab and OKLCH** (Björn Ottosson, 2020; CSS Color 4 §9).
  - `to_oklab/1` is `%{l, a, b, opacity}`, and `to_oklch/1` is `%{l, c, h, opacity}`, with `l` in `0..1` and `h` in `[0, 360)`.
  - `oklab/3,4` and `oklch/3,4` build a color, **gamut-mapped** by CSS Color 4 §13.2: chroma is reduced in OKLCH by binary search until the clipped color is within a ΔEOK of 0.02, and a result too light or too dark becomes white or black.
  - `delta_eok/2` is the OKLab distance.

```planned-test:color-conversions-exact
lab of to_lab is the color and a gray has a and b zero; OKLab of the sRGB primaries matches the published values; contrast and luminance follow WCAG; each manipulation and interpolation gives d3-color's values; an out-of-gamut OKLCH is chroma-reduced to within 0.02
```

### 1.3 Typed colors and their transforms {#themes-color-typed}

<!-- surfex: deferred #133: color -->

A document names a color as a **typed value**, never a bare atom; the values are plain data, built by functions that check their arguments and compile nothing, and resolved against a theme (§3.1), so a theme swap changes every color derived from the theme's colors.

| Value | Built by | Meaning |
|---|---|---|
| `{:color, name}` | `color(name)` | the color `name` of the theme's color table (§2.2) |
| `{:series, i}` | `series(i)` | the i-th series color, cycling |
| `{:ramp, name, t}` | `ramp(name, t)` | the color at `t` along one of the theme's ramps (§2.3) |
| a string | — | a literal CSS color, as written (allowed by the `:open` profile alone, §4) |
| `{:intensity, c, t}` | `intensity(c, t)` | how much of `c` is present; the rest is transparent |
| `{:blend, [c, …]}` | `blend(list)` | the colors mixed in OKLab, each weighted by its intensity |
| `{:alpha, c, a}` | `alpha(c, a)` | `c` at opacity `a` |
| `{:lighten, c, t}`, `{:darken, c, t}`, `{:saturate, c, t}` | `lighten/2`, `darken/2`, `saturate/2` | `c` moved toward white, black or full chroma in OKLCH |
| `{:contrast, c}` | `contrast(c)` | the readable ink over `c` (§3.2) |
| `{:contrast, :under}` | `contrast()` | the readable ink over whatever the text is drawn on |
| `{:shade, c, n}` | `shade(c, n)` | the step `n` of `c`'s scale, from 0 (near white) through 500 (`c` itself) to 1000 (near black); a step the theme pins is the pinned color |

**Each helper takes the color first, and every number is in `0..1`** (a shade's step in `0..1000`), so colors pipe: `[color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)] |> blend() |> alpha(0.65)`. A helper raises `ArgumentError` for a number outside its range, an operand that is not a color value, a name that is not an atom or a string (`nil`, `true` and `false` are not names), or an empty `blend`; it does not check that a name exists, which is the theme's to resolve. `saturate/2` on a `%Color{}` keeps §1.2's meaning; on a color value it builds the transform. `value?/1` is whether a term is a color value of the table, operands included.

**The transforms, exactly**, every computation in OKLab:
- **`intensity(c, t)`** alone is `c` with its alpha multiplied by `t`, as `color-mix(in oklab, c t%, transparent)` is.
- **`blend(list)`** is CSS Color 5's `color-mix` over any number of colors:
  1. An element `intensity(c, w)` contributes `c` with weight `w`, and any other element contributes itself with weight 1.
  2. The weights are normalized by their sum `W`, and the colors averaged in OKLab with premultiplied alpha.
  3. When `W < 1` the alpha is multiplied by `W`.
  4. A blend whose weights are all 0 is fully transparent.

  A blend of one color at weight 1 is that color.
- **`alpha(c, a)`** replaces `c`'s opacity, so `alpha` after a `blend` states the final opacity.
- **The OKLCH moves**, each keeping hue and alpha:
  - **`lighten(c, t)`** is `L + (1 − L) t`;
  - **`darken(c, t)`** is `L (1 − t)`;
  - **`saturate(c, t)`** is `C + (0.4 − C) t`.
- **`contrast(c)`** is the theme's ink over `c` (§3.2), a translucent `c` first laid over the theme's background.
- **`shade(c, n)`** lies on one curve, keeping hue. With `u = |n − 500| / 500`:
  - toward white, `L' = L + (0.97 − L) u`;
  - toward black, `L' = L − (L − 0.2) u`;
  - `C' = C (1 − u²)`.

  **A theme may pin steps** of a name (§2.2), and a shade of a pinned name reads them. A shade of any other color is computed.

```planned-test:color-typed-transforms
each builder makes its value and refuses an out-of-range number, a non-color operand, a non-name and an empty blend; each transform equals the value computed independently through CSS Color 4's XYZ route; a blend follows color-mix's weights, premultiplied, its remainder transparent
```

### 1.4 Resolution and CSS {#themes-color-resolve}

<!-- surfex: deferred #133: color -->

`Color.resolve(value, theme, mode)` resolves a color value in `:literal` or `:css` mode:
- **Names and positions:** a name, a series position, a ramp position and a bare slot atom resolve as `Theme.resolve/3` resolves them (§3.1). A literal string is returned as written.
- **Transforms in `:literal`:** a transform is computed to a literal, `#rrggbb` (or `#rrggbbaa` below full opacity). Its operands are resolved as literals first, and an operand `parse/1` cannot read raises `ArgumentError`.
- **Transforms in `:css`:** a transform is written as CSS, so a stylesheet's theme switch carries through every derived color without a re-render. Each operand is written in its own `:css` form, a name as `var(--mw-red, #c23238)`:

  | Transform | CSS |
  |---|---|
  | `intensity(c, t)` | `color-mix(in oklab, C t%, transparent)` |
  | `blend([…])` | `color-mix(in oklab, C1 p1%, C2 p2%)`, the weights scaled to sum to 1 when they sum above 1. Three or more nest: the first n − 1 mixed at weights normalized among them, then mixed with the last at their sum. A weight of 0 is left out, a blend of nothing is `transparent` |
  | `alpha(c, a)` | `oklch(from C l c h / a)` |
  | `lighten(c, t)` | `oklch(from C calc(l + (1 - l) * t) c h / alpha)` |
  | `darken(c, t)` | `oklch(from C calc(l * k) c h / alpha)`, `k = 1 − t` |
  | `saturate(c, t)` | `oklch(from C l calc(c + (0.4 - c) * t) h / alpha)` |
  | `contrast(c)`, `contrast()` | the ink's literal (visualize D-123) |
  | `shade(color(name), n)`, `n` pinned | `var(--mw-<name>-<n>, literal)`, a property the sheet declares |
  | `shade(c, n)` toward white / black | `oklch(from C calc(l + (0.97 - l) * u) calc(c * k) h / alpha)` / `oklch(from C calc(l - (l - 0.2) * u) calc(c * k) h / alpha)`, `u` and `k = 1 − u²` as numbers |
  | `shade(c, 500)` | `C` |

  A number is written with at most four decimals and no trailing zeros. The literal a browser evaluates from this CSS by CSS Color 4 and 5 is the literal `:literal` mode computes, within a channel's rounding; the tests hold the two to it with an evaluator of the CSS written from the CSS specifications alone.

```planned-test:color-css-agrees
every transform's CSS, evaluated by an evaluator written from CSS Color 4 and 5, gives the literal mode's color within a channel's rounding; names resolve to var references with their literal fallback
```

### 1.5 Color-vision simulation {#themes-color-vision}

<!-- surfex: deferred #133: color -->

`Macaw.Layers.Color.Vision` simulates how a color reads to a person with one of the three dichromacies, so a palette can be judged by eye for the readers it would fail; it is used for judging only. The model is **Machado, Oliveira and Fernandes (2009)** at severity 1.0, chosen for one cheap matrix per deficiency that grades to the anomalous trichromacies with no new code path (visualize D-139). A color is:
1. decoded from sRGB to linear RGB, by `c / 12.92` for `c ≤ 0.04045` and `((c + 0.055) / 1.055)^2.4` otherwise;
2. multiplied by the deficiency's matrix;
3. clamped to `0..1` and encoded back, its opacity kept.

| Deficiency | Matrix (rows R, G, B) |
|---|---|
| `:protanopia` | `[0.152286, 1.052583, −0.204868]`, `[0.114503, 0.786281, 0.099216]`, `[−0.003882, −0.048116, 1.051998]` |
| `:deuteranopia` | `[0.367322, 0.860646, −0.227968]`, `[0.280085, 0.672501, 0.047413]`, `[−0.011820, 0.042940, 0.968881]` |
| `:tritanopia` | `[1.255528, −0.076749, −0.178779]`, `[−0.078411, 0.930809, 0.147602]`, `[0.004733, 0.691367, 0.303900]` |

Each row sums to 1, so every gray is its own simulation.

| Function | Contract |
|---|---|
| `Vision.deficiencies/0` | `[:protanopia, :deuteranopia, :tritanopia]` |
| `Vision.matrix/1` | the matrix as three rows |
| `Vision.simulate/2` | the color as the deficiency sees it, opacity kept; `:none` is the color; any other value raises `ArgumentError` |
| `Vision.recolor/2` | every `#rrggbb` and `#rgb` literal in a text replaced by its simulation as `#rrggbb`; `url(#id)` is left alone |

```planned-test:color-vision-machado
each deficiency's matrix is Machado's at severity 1, every gray is its own simulation, opacity is kept, none is the identity, and recolor replaces hex literals but not url references
```

## 2. The theme {#themes-theme}

<!-- surfex: deferred #134: the theme document -->

### 2.1 Fields and slots {#themes-slots}

<!-- surfex: deferred #134: the theme document -->

`%Macaw.Layers.Theme{name, series, axis, grid, text, background, surface, ramps, colors, styles, defaults, font_family, font_size, label_size, title_size, dark, light, extensions}`:

- **`name`** — the theme's name. A built-in theme's is an atom (`:default`, `:dark`, `:color_safe`, `:print`); a host's is its string (`name: :house` is held as `"house"`), so a theme built in Elixir and the one its document reads are one value.
- **`series`** — a non-empty list of color strings.
- **`axis`, `grid`, `text`, `background`, `surface`** — the **furniture**, color strings.
- **`ramps`** — each ramp name of §2.3 to its anchors.
- **`colors`** — the theme's own part of its color table (§2.2).
- **`styles`** — each palette name of §2.4 to its entry.
- **`defaults`** — the theme's own root defaults, an adopter's node (visualize's `:defaults`, its spec/14 §3.8), carried and merged key by key and otherwise not read here.
- **`font_family`** — a CSS font-family string; **`font_size`, `label_size`, `title_size`** — numbers in pixels.
- **`dark` and `light`** — the built-in theme that stands for this one in the viewer's dark or light color scheme, or `nil` (§6).
- **`extensions`** — the registered extensions (§3.4), `[]` by default.

Every field is plain data, so a theme is stored and compared as a value.

A **slot** names one value of a theme:

| Slot | Field | Used for |
|---|---|---|
| `:series_1` … `:series_n`, or `{:series, i}` | `series` | the i-th categorical color; `{:series, i}` cycles, so on ten colors `{:series, 11}` is `:series_1` |
| `:axis`, `:grid`, `:text`, `:background`, `:surface` | the furniture | lines, grids and links behind the data, text, the page, the plane the data lies on |
| `:good`, `:warning`, `:bad` | `colors` | the status roles, by default the `status` ramp at 0, 0.5 and 1 |
| `:info`, `:neutral` | `colors` | the remaining roles |
| `:font_family`, `:font_size`, `:label_size`, `:title_size` | the font fields | every text, the smallest, the labels, the titles |

`slots/1` lists a theme's slots in that order. `series_slot/2` is the `:series_k` that `{:series, i}` cycles to. A slot that is none of these, or `:series_k` outside `1..n`, raises `ArgumentError` in every function that takes a slot. `color_slots/1` is the color slots alone: the series, the furniture, then the five roles.

```planned-test:themes-slots-order
slots lists the series then the furniture, roles and font slots in order; series positions cycle; an unknown slot or a series slot beyond the palette raises
```

### 2.2 The color table {#themes-color-table}

<!-- surfex: deferred #134: the theme document -->

Every color a document names with `color(name)` is looked up in the theme's **color table**, in this order:
1. the theme's own `colors`;
2. the default theme's `colors`;
3. the colors the theme's extensions add (§3.4);
4. the **CSS named colors** (§1.1).

The furniture and `:series_1` … `:series_n` are names of the table too, read from their fields. A theme may change any value, and add names, by its string (`colors: %{brand: …}` is held under `"brand"`). A name is found in the table by either spelling, and must be lower-case letters, digits and `_`, starting with a letter. A value is a color string, or a color value of §1.3 that resolves through the same theme (`{:ramp, :status, 1}`).

**A theme may pin steps** of a name: `colors: %{red: %{500 => "#d62728", 100 => "#fde8e8"}}`, a map of integer steps in `0..1000` with 500 among them to color strings. Step 500 is the name's own color, and a step not pinned is computed on §1.3's curve. A pinned entry without step 500, with a step outside `0..1000` or not an integer, or with a value that is no color string, is refused.

The built-in themes' own `colors`:

| Name | `default/0` | `dark/0` |
|---|---|---|
| `:red`, `:amber`, `:green` | `#c23238`, `#bd7407`, `#4ca34b` | `#ff8f8a`, `#db8e1c`, `#4f924c` |
| `:blue`, `:gray` | `#3b6fa8`, `#6f7480` | `#7fb3e6`, `#b7bcc6` |
| `:good`, `:warning`, `:bad` | `{:ramp, :status, 0}`, `{:ramp, :status, 0.5}`, `{:ramp, :status, 1}` | as the default |
| `:info`, `:neutral` | `#3b6fa8`, `#6f7480` | `#7fb3e6`, `#b7bcc6` |

`color_names/1` lists a theme's table, sorted. `color_name?/2` answers membership without building the list (visualize D-184). A theme's `roles` key, the role colors of before visualize#663, is read as `colors`.

```planned-test:themes-color-table
a name resolves from the theme's colors, then the default's, then an extension's, then the CSS names; furniture and series are names; a host's name is held by its string and found by either spelling; pinned steps need 500 and integer steps in range
```

### 2.3 Ramps and roles {#themes-ramps}

<!-- surfex: deferred #134: the theme document -->

A palette position promises *distinct*, never a meaning. Colors that carry meaning a reader brings with them — the stop-light, cold and hot, below and above a target — are carried as **ramps**, whose meaning the library fixes and whose tones the theme tunes (visualize D-135).

**A ramp** is two or more anchors (a color string, a name of the table, or a transform of those, measured as the literal it computes), evenly spaced along `0..1`, the color at `t` interpolated between its two neighbors in **CIE Lab**. A position on an anchor is that anchor as written. Four ramps, each with its **contract**:

| Ramp | Meaning | Contract |
|---|---|---|
| `status` | good → caution → bad | hue order: at 0 green or blue, at 0.5 amber, at 1 red, the hue of every chromatic anchor falling monotonically; lightness monotonic |
| `thermal` | cold → neutral → hot | at 0 blue, at 0.5 neutral, at 1 red |
| `diverging` | below → at → above | the ends chromatic and at least 60° of hue apart; the middle neutral |
| `sequential` | less → more, one quantity | one hue family; lightness monotonic |

**The terms**, in CIE LCh against D50:
- **Hue regions:** **red** is below 45° or from 345°; **amber** 45°–100°; **green** 100°–200°; **blue** 200°–315°. A falling status hue is read with red's arc taken below zero.
- **Chromatic and neutral:** **chromatic** is a chroma of at least 20 C\*, and **neutral** at most 10 C\*.
- **Monotonic lightness:** every step between consecutive anchors moves the same way by at least 3 L\*.
- **One hue family:** every anchor of at least 10 C\* lies within a 45° arc.

The built-ins run `status` and `sequential` away from their background, so the role that must be noticed stands out; that is advice, not a contract.

**Roles** are the meaning vocabulary: `:good` (status 0), `:warning` (0.5), `:bad` (1), `:info` (a chromatic blue) and `:neutral` (neutral), the names design systems give their semantic tokens. Their colors are names by use in the table, so a role and its ramp position agree, and a theme may set a status role's entry apart from the ramp by its own choice. A role names a meaning, never a color, which is what lets data name it: a feed's state `"down"` can say `:bad`.

**Cues** (visualize D-142): every role carries a glyph and a dash, `cue/1`, so a status reads without its hue.

| Role | Glyph | Dash |
|---|---|---|
| `:good` | `:circle` | solid |
| `:warning` | `:triangle` | `"6 3"` |
| `:bad` | `:cross` | `"2 3"` |
| `:info` | `:square` | `"8 3 2 3"` |
| `:neutral` | `:diamond` | `"1 4"` |

**Fallback:** a theme lacking a ramp or a color name takes the default theme's, never a series color, since a series color carries no meaning.

```planned-test:themes-ramps-contracts
ramp interpolates in Lab between evenly spaced anchors and clamps t; each built-in theme holds every ramp and role contract; a ramp breaking hue order, lightness, neutrality, chroma or family is refused naming the anchor and the term; a missing ramp falls back to the default's; cue gives each role's glyph and dash
```

### 2.4 The style palette {#themes-palette}

<!-- surfex: deferred #134: the theme document -->

`styles` carries the palette over to **whole styles** — fill, stroke and its width, dash, opacity, marker, font — so a document can name a whole look by position, by meaning or by view state, and a theme swap restyles it.

| Group | Names | Promises |
|---|---|---|
| style series | `:style_1` … `:style_n`; `{:style, i}` cycles | distinct whole looks for categories, differing between neighbors in more than hue |
| style roles | `:good`, `:warning`, `:bad`, `:info`, `:neutral` | a meaning as a whole style: the role's color and its cue |
| state styles | `:hover`, `:focused`, `:selected`, `:active`, `:disabled`, `:muted`, `:emphasis`, `:breakpoint` | what a view state looks like, laid over an object's own look |
| furniture styles | `:axis`, `:grid`, `:label`, `:title`, `:caption`, `:value`, `:annotation` | the furniture's lines and each kind of text |
| modifiers | `:bold`, `:italic`, `:thin`, `:thick`, `:dashed`, `:dotted`, `:outline` | one change each, to stack on a look |

A theme chooses only how many style series it has, with no gap, and how each entry looks. **It cannot add a name**: the names are the library's and its registered extensions' (§3.4), so a document that names one reads the same on every theme.

**An entry is a style node in parts, written in slots:** its keys are the parts `fill`, `stroke`, `font`, `text`, `effect`, `marker`, `curve`, and `opacity`, `blend` and `class`. Its colors are typed values or slots, never literals where a slot says the same (`fill: %{type: :solid, color: {:color, :bad}}`, `stroke: %{type: :solid, color: {:series, 3}, width: 1.5}`, `font: %{size: :label_size}`). A bare atom in a color position is the typed color it names. In a role's entry, `stroke: %{dash: :cue}` and `marker: %{shape: :cue}` take the role's cue. An entry may be **a list** of palette names and nodes, stacked left to right. It may not use `extends`: the palette is the end of every chain. Entries may be partial: a state or a modifier gives a few keys.

**The built-in palette**, the same entries on every built-in theme, each taking that theme's colors:

| Name | Entry |
|---|---|
| `:style_1` … `:style_10` | a solid `fill` and `stroke` of `{:series, k}`, `width: 1.5`; markers `:circle :square :triangle :diamond :cross :star :wye :circle :square :triangle`; dashes solid, `"8 3"`, `"3 3"`, `"8 3 3 3"`, `"1 3"`, repeated |
| `:good` … `:neutral` | a solid `fill` of `{:color, role}`; a solid `stroke` of it with `dash: :cue`; `marker: %{shape: :cue}` (on `print/0`, hatched fills, §2.5) |
| `:hover` | `stroke: %{type: :solid, color: :text, width: 2}` |
| `:focused` | `stroke: %{type: :solid, color: :text, width: 2, dash: "4 2"}` |
| `:selected` | `stroke: %{width: 2}` |
| `:active` | `stroke: %{type: :solid, color: :text, width: 3}` |
| `:disabled` | `opacity: 0.4`, `stroke: %{dash: "2 2"}` |
| `:muted` | `opacity: 0.25` |
| `:emphasis` | `stroke: %{width: 3}`, `font: %{weight: :bold}` |
| `:breakpoint` | `stroke: %{type: :solid, color: :bad, width: 2, dash: "6 2 2 2"}` |
| `:axis` | a solid `stroke` of `:axis`, a solid `fill` of `:text`, `font: %{family: :font_family, size: :font_size}` |
| `:grid` | a solid `stroke` of `:grid` |
| `:label` | a solid `fill` of `:text`, `font: %{family: :font_family, size: :label_size}` |
| `:title` | as `:label` at `:title_size`, `weight: :bold` |
| `:caption` | a solid `fill` of `:text`, `font: %{family: :font_family, size: :font_size, style: :italic}` |
| `:value` | a solid `fill` of `:text`, `font: %{family: :font_family, size: :title_size, weight: :medium}` |
| `:annotation` | a solid `fill` of `:text`, `font: %{family: :font_family, size: :font_size}` |
| `:bold`, `:italic`, `:thin`, `:thick` | `font: %{weight: :bold}`, `font: %{style: :italic}`, `stroke: %{width: 1}`, `stroke: %{width: 3}` |
| `:dashed`, `:dotted`, `:outline` | `stroke: %{dash: "6 3"}`, `stroke: %{dash: "1 3", cap: :round}`, `fill: %{type: :none}` |

`style(theme, name)` is an entry — a name, or `{:style, i}` cycling — as a flat node, the default theme's entry whole when the theme lacks it, `:cue` replaced by the role's cue (its dash left out where solid). `style_names/1` lists the names: the style series, then roles, states, furniture and modifiers, then the extensions'. **Fallback** is whole, never key by key, since a partial entry laid over another theme's would be a look neither chose.

```planned-test:themes-palette-entries
the built-in palette gives every entry of the table on every built-in theme; style resolves cues and cycles style positions; a missing entry falls back to the default's whole; a theme cannot add a name; a list entry stacks and may not reach itself
```

### 2.5 The built-in themes {#themes-builtins}

<!-- surfex: deferred #134: the theme document -->

| Field | `default/0` | `dark/0` |
|---|---|---|
| `series` | `#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480` | `#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6` |
| `axis`, `grid`, `text` | `#666666`, `#e0e0e0`, `#333333` | `#a0a4ab`, `#33373f`, `#e6e6e6` |
| `background`, `surface` | `#ffffff`, `#eef2f6` | `#1b1e24`, `#23272f` |
| `ramps.status` | `color(:green) color(:amber) color(:red)` | the same names |
| `ramps.thermal` | `#0e68ad #e8e8e8 #c02e31` | `#7fb3e6 #3a3f48 #f47c7c` |
| `ramps.diverging` | `#b35806 #ededed #62448e` | `#f7a35c #3a3f48 #c1acee` |
| `ramps.sequential` | `#e9f2fc #5e95d3 #004580` | `#273b4f #457cb1 #aad1f9` |
| `dark`, `light` | `:dark`, `nil` | `nil`, `:default` |
| fonts | `sans-serif`, `10`, `12`, `16` | the same |

- **`color_safe/0`** is the default named `:color_safe`, its `status` running blue → orange → red, `#5996d6 #cd6012 #b92931`, which survives the commonest color-vision deficiencies. Its lightness still falls at each step.
- **`print/0`** is paper:
  - a white `background` and `surface`, text `#111111`, axis `#333333`, grid `#c8c8c8`;
  - the color-safe `status` ramp;
  - role styles whose fills are hatches of the role's color: `:good` lines at 45°, `:warning` at 135°, `:bad` a crosshatch, `:info` dots, each spacing 6 and width 1, and `:neutral` solid.

`builtin/1` is the theme of a built-in name, else `nil`. `new/1` is `default/0` with the given fields replaced and `ramps`, `colors`, `styles` and `defaults` merged key by key. `merge/2` does the same for any theme. An unknown field raises `KeyError`, an empty `series` raises `ArgumentError`, and a contract broken raises `ArgumentError` (§2.6).

```planned-test:themes-builtins-values
each built-in theme has the table's values and pairs default with dark; color_safe and print change exactly what the section says; new and merge replace fields and merge ramps, colors, styles and defaults by key; an unknown field and an empty series raise
```

### 2.6 Contracts and contrast {#themes-contracts}

<!-- surfex: deferred #134: the theme document -->

**Contracts are checked when a theme is built:** `new/1` and `merge/2` check every ramp, color and palette entry, and raise `ArgumentError` naming the theme, the subject and the term it breaks:

> `theme "house": ramp :status breaks its contract: lightness must change one way along the ramp, by at least 3 L* a step …`

`check/1` gives the same answer as `{:error, subject, message}` for the first fault, `subject` being `{:ramp, name}`, `{:color, name}` or `{:style, name}`. `violations/1` lists every fault, each contract run alone. A struct written literally is not checked: it is the escape hatch.

**The palette's contracts:**
- **A name of the palette.** A name outside the groups, or `:style_k` with a gap below it, is refused.
- **A node or a list.** An entry is a node with no `extends`, or a list of palette names and nodes that does not reach itself.
- **`:cue` only on a role's dash or marker shape.**
- **The role styles, as a set,** each read with its cue:
  - no two are the same once the color of their fill and stroke is taken out;
  - their colors are at least ΔEOK 0.02 apart;
  - a solid fill or stroke reaches **3:1** against the background (WCAG 1.4.11), and an entry with a font part has its fill reach **4.5:1** (WCAG 1.4.3). A translucent color is laid over the background first, and a refusal names the part, the color, the ratio and the rule.
- **Every color name resolves** in the table.
- **A state style is distinguishable without hue:** it changes stroke width, outline, opacity, dash or effect, never only a color.
- **Neighboring style series differ in more than hue,** the last and the first included.
- **A text furniture entry resolves a font family and size.**
- **`:grid` resolves a stroke.**
- **A modifier changes exactly one key.**

**Contrast floors** (visualize spec/08 §7.4) are what a theme **offered to people** must hold against its own background:
- `text` at least 4.5:1;
- `axis` and every `series` color at least 3:1;
- `grid` at least 1.2:1;
- `surface` different from `grid`.

The built-ins hold them. `floors/1` answers `:ok` or `{:error, faults}`. **Contrast is checked once, on the theme** (macaw_compose spec/10): a host offers a theme only when `floors/1` and `check/1` pass, and a user-defined theme that fails is refused (macaw_compose spec/11 §1).

```planned-test:themes-palette-contracts
each palette contract refuses its fault with the theme, the entry and the measured value named: an unknown name, a gap, extends, a misplaced cue, two roles alike without hue, two role colors too close, a role paint under 3:1 or text under 4.5:1, an unknown color, a state that changes only color, neighbors alike, a font missing, a grid with no stroke, a modifier of two keys
```

```planned-test:themes-floors-builtins
every built-in theme meets the floors and every contract; floors refuses text under 4.5:1, an axis or series color under 3:1, a grid under 1.2:1 and a surface equal to the grid
```

## 3. Resolution, the ink and extensions {#themes-rules}

<!-- surfex: deferred #134: the theme document -->

### 3.1 Resolution {#themes-resolution}

<!-- surfex: deferred #134: the theme document -->

`resolve(theme, slot_or_name, mode)` is the one door through which anything reads a theme:
- **`:literal`:** the value as stored, a color or font string or a size number. A canvas and a PNG resolve this way.
- **`:css`:** a custom-property reference with the literal as its fallback: `var(--mw-axis, #666666)`, `var(--mw-series-3, #c8373b)`, `var(--mw-font-size, 10px)` (a size gains `px`). This is what an SVG or HTML output carries.
- **Roles and names:** a role, and a name of the table, resolve the same way, `:red` to `var(--mw-red, #c23238)`. A name in no part of the table raises `ArgumentError`.
- **Ramp positions:** `{:ramp, name, t}` is a **literal in both modes** (CSS has no property per position), except the status roles' positions, which resolve as the roles. `t` is clamped, and a ramp name not of §2.3 raises.

`css_name/1` is `--mw-` and the name with `_` as `-` (`:series_1` → `--mw-series-1`).

**The reference carries its fallback rather than the root declaring the property** (visualize D-55): a declaration on an element would beat every ancestor rule, so a theme could not be switched from a class. With the fallback, output rendered outside any stylesheet still draws in its theme, and a class on any ancestor overrides it.

```planned-test:themes-resolve-modes
resolve gives a literal or a var reference with the literal fallback for every slot, role and name, sizes in px; ramp positions are literals except the status roles' positions; css_name maps names; an unknown name raises
```

### 3.2 The contrast ink {#themes-ink}

<!-- surfex: deferred #134: the theme document -->

`ink(theme, under)` (visualize D-123) is the color a text drawn on `under` takes: the theme's `text` or `background`, whichever contrasts more with `under` (`text` on a tie), **always as a literal**. When the better of the two is under 4.5:1, it is `#000000` or `#ffffff` instead, one of which always reaches 4.58:1 or better. `under` is a color string, a `%Color{}`, or `nil` for the theme's background. A string that does not parse is `nil`, and a slot whose own value does not parse is skipped. It is a literal because the choice is made between literals: a re-pointed custom property would undo it.

```planned-test:themes-ink-aa
ink chooses text or background by contrast, text on a tie, and black or white when neither reaches 4.5:1, so the ink always meets 4.5:1; nil is the background and an unreadable color is nil
```

### 3.3 Precedence {#themes-precedence}

<!-- surfex: deferred #134: the theme document -->

Where a color comes from, highest first:
1. a choice the document makes: under the `:open` profile a literal, or a document's own color scale or palette entry of a name;
2. the theme's rendering of a role, ramp position or palette name the document names;
3. the default theme's;
4. an extension's default.

**One theme per page.** A component's own theme setting (a visualize design's `theme`) is an override the page **masks** (spec/02 §4); standalone, it applies. **Themes stack** like any fragment (§5): a host's theme is a layer over a built-in.

```planned-test:themes-precedence-layers
a document's palette entry beats the theme's, the theme's the default's and the default's an extension's; a page masks a component's theme key; a theme document stacked over a built-in is the merged theme
```

### 3.4 Extensions: what adopters register {#themes-extensions}

<!-- surfex: deferred #134: the theme document -->

**Adopters register what their documents name beyond the library's vocabulary**, so one theme styles them (visualize's mark roles). An extension is a module implementing `Macaw.Layers.Theme.Extension`:

| Callback | Contract |
|---|---|
| `name() :: String.t()` | the extension's name, for faults |
| `styles() :: %{atom => {group, entry}}` | palette names it adds, each in a group of §2.4 (`:state`, `:furniture`, `:modifier`), with its default entry |
| `colors() :: %{atom => color}` | names it adds to the color table, each with a default value |

A theme carries its extensions in `extensions`, given explicitly (`new(extensions: [Visualize.Theme.Roles])`). The list is **default closed**: a palette name or color name that neither the library nor an extension has is a fault naming it. The names an extension adds are held to the contracts of their group, its default entries included. Two extensions adding one name, or an extension adding a library name, raise `ArgumentError` naming both.

```planned-test:themes-extensions-registered
a registered extension's names are in the palette and the table with their defaults, held to their group's contracts; an unregistered name is a fault naming it; two extensions adding one name raise naming both
```

## 4. Literal and data colors: the profile {#themes-profile}

<!-- surfex: deferred #134: the theme document -->

- **Drawing colors are theme roles and tokens, and values derived from them** (`lighten(:warning)`), so contrast is checked on the theme (metresis.md C3).
- **Literal colors are a profile's.** `Theme.check_color(value, profile)` answers `:ok` or `{:error, {:literal_color, value}}`:
  - under **`:roles`**, the profile every Macaw page validates against, a color value whose leaves include a literal string is refused;
  - under **`:open`**, an adopter's standalone default (visualize's), literals are allowed.

  The profile is the host's authority: nothing derives it.
- **Data colors are typed content.** A `:color` column or a schema's value color (a team's color) is shown only with a non-color cue (a glyph, a label or a dash), which is the component's obligation, and under a **contrast guard**. `Theme.data_color(theme, value)` is:
  - `{:ok, literal}` where the color reaches 3:1 against the theme's background;
  - `{:error, {:contrast, ratio}}` otherwise;
  - `{:error, :unreadable}` for a value that does not resolve.

  A data color is never the sole carrier of meaning (macaw_data spec/01 §1; macaw_compose#22, decision 7; visualize D-233).

```planned-test:themes-profile-colors
under roles a literal anywhere in a color value is refused and every typed value passes; under open both pass; a data color under 3:1 against the background is refused with its ratio and one that reaches it is its literal
```

## 5. A theme as a document {#themes-document}

<!-- surfex: deferred #134: the theme document -->

A theme is stored and shipped as a value, so it is a **document** (spec/01): `Macaw.Layers.Theme.Document` implements `Macaw.Layers.Document`, `Version`, `Form` and `Fragment` (spec/02 §1), its root kind `:theme`. A theme document is the theme's fields under `theme`:

| Form | What |
|---|---|
| map | `%{version: v, theme: node}`; the store's fragment `%{theme: node}`, a library entry of kind `:theme`, reads as the same document |
| JSON | `{"$version": v, "theme": {…}}`, pinned steps as `$steps` |

**Fragment rules:** `ramps`, `colors`, `styles` and `defaults` are `:union` name maps, and every other key is `:override`, so a theme stacks over a built-in as `new/1` merges (§2.5).

**Reading.** `Document.read/3` reads in the order of every reader (spec/01 §5):
1. the version gate;
2. the limits;
3. migration;
4. the contracts, each broken one `{:contract, message}` at `[:theme, :ramps, name]`, `[:theme, :colors, name]` or `[:theme, :styles, name]`;
5. then the theme.

**What a theme document cannot hold:**
- **variables:** nothing applies a theme, so a variable is `{:unresolved, :var, name}`;
- **an unknown name:** a node that is a **name** reads as the built-in theme of that name, and any other name is `{:unknown_theme, name}`;
- **atoms from the document:** no atom is made, a host's name and its own colors being strings.

`from_map(to_map(t))` and `from_json(to_json(t))` are `{:ok, t}` for every theme `new/1` builds, the built-ins included.

```planned-test:themes-document-forms
a theme round-trips through its map and JSON forms, the built-ins and host themes with pinned steps included; a newer stamp, a broken contract at its path, a variable, an unknown theme name and an unknown key are refused; a theme fragment stacks over a built-in
```

## 6. Delivery {#themes-delivery}

<!-- surfex: deferred #135: theme delivery and v0.2.0 -->

A theme compiles to **custom properties scoped by a class**, `.mw-theme-<name>` (`.mw-theme-dark`), in the site's static stylesheet, served from `'self'`. Adopters emit the same class, so a visualize chart standalone and on a page reads the same properties.

- **`Sheet.rule(theme)`** is the theme's rule:
  1. `.mw-theme-<name> {`;
  2. one `  --mw-<slot>: <value>;` per slot of `slots/1`, sizes with `px`;
  3. one line per name of the theme's own `colors` that is not a slot, in name order, as its literal, followed by one per step it pins other than 500 (`--mw-red-100`);
  4. `}`.

  Then comes a **forced-colors block**: `@media (forced-colors: active)` declaring `--mw-text` and `--mw-axis` as `CanvasText`, `--mw-background` and `--mw-surface` as `Canvas`, and `--mw-grid` as `GrayText`. In high-contrast mode what is drawn from the theme then agrees with the user's palette, and a role still reads by its dash and glyph.
- **"Auto"** follows `prefers-color-scheme` through a media query in that same stylesheet. `Sheet.auto(light, dark)` is the rule `.mw-theme-auto` declaring `light`'s properties, then `@media (prefers-color-scheme: dark)` declaring `dark`'s under the same class. There is **never a `<style>` element per component** (macaw_compose spec/10).
- **`Sheet.stylesheet(themes, auto: {light, dark})`** is the whole static sheet: one rule per theme offered, in order, then the auto rule. Its bytes are a pure function of its themes, so it is cached and served by its digest (spec/01 §7), and a user-defined theme's sheet is served the same way (`/themes/<hash>.css`, macaw_compose spec/11 §1).
- **Per-element styles resolve on the server** into SVG presentation attributes or classes, which is the adopter's rendering, through `resolve/3` in `:css` mode.

```planned-test:themes-sheet-rules
a theme's rule declares every slot, its own colors and pinned steps as custom properties under its class, with the forced-colors block; auto declares the light theme and switches to the dark one under prefers-color-scheme; the stylesheet is the rules in order and depends only on its themes
```
