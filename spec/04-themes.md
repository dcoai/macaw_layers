# 04 — Themes {#themes}

**One theme system styles every surface, the site included** (decided, owner, 2026-10-25). It is visualize's theme: palettes, named whole styles and **roles** (good, warning, bad, info, neutral), with the states (hover, focused, selected, active, disabled, muted, emphasis, breakpoint) and the furniture. Collpa's brand tokens become a theme, and metresis maps its UI framework's roles from it. This file is visualize's color and theme (spec/08 §1, §7; spec/14 §2.5, §9.3; D-55, D-122, D-123, D-135, D-139, D-142, D-171–D-175, D-184, D-225, D-233), with what draws a chart left in visualize (macaw_compose#94; R11 of `design/visualize-alignment.md`):

- **the CSS names are Macaw's:** `--mw-<name>` properties under `.mw-theme-<name>`, which adopters emit too, so a visualize chart standalone and on a page reads the same properties;
- **adopters register** the palette names and color names they add (§3.4), from an explicit list, closed by default;
- **literal colors are a profile's** (§4): a Macaw page validates as `:roles`;
- **visualize keeps** its style defaults, its mark style parts, the palette's assignment to marks, its backends and its builder's theme editor.


| Module | What it is |
|---|---|
| `Macaw.Layers.Color` | colors: the struct, parsing, conversions, manipulation, interpolation, OKLab and OKLCH, contrast, typed colors and their resolution (§1) |
| `Macaw.Layers.Color.Vision` | color-vision simulation (§1.5) |
| `Macaw.Layers.Color.Form` | the colors' JSON adapter (§1.6) |
| `Macaw.Layers.Theme` | the theme: slots, the color table, ramps and roles, the style palette, contracts, resolution, the ink, the built-ins, extensions, the profile (§2–§4) |
| `Macaw.Layers.Theme.Extension` | the behavior an adopter's extension implements (§3.4) |
| `Macaw.Layers.Theme.Document` | a theme as a document of its own (§5) |
| `Macaw.Layers.Theme.Sheet` | a theme compiled to a stylesheet (§6) |

## 1. Color {#themes-color}

### 1.1 The literal color, and parsing {#themes-color-parse}

**A literal color is a term:** `%Macaw.Layers.Color{r, g, b, opacity}`, a color as data, drawn as itself. It is **canonical**: every field is a float, `r`, `g` and `b` clamped to `[0, 255]` and `opacity` to `[0, 1]` (default `1.0`), and a zero is never the negative zero. Every constructor builds that shape (`rgb`, `hsl`, `lab`, `hcl`, `oklab`, `oklch`, `parse`, the manipulations and interpolations, §1.2), so two literals of one color are one term whatever built them: equal, and of one digest (spec/01 §7), `parse!("white")` and `rgb(255, 255, 255)` alike. `literal?/1` is whether a term is a literal color: the struct of that canonical shape, so a struct written by hand with integer fields, or out of range, is not one. `hsl`, `lab` and `hcl` round channels to whole numbers, held as floats; `rgb`, `oklab` and `oklch` clamp without rounding.

CSS text is not a color but one of its encodings: text is read into a literal at the input edge and a literal written as text at the output edge (§1.6).

`name?/1` is the grammar of a name a theme gives (a color, a ramp, a style, the theme itself, §2.1, §2.2): lower-case letters, digits and `_`, starting with a letter, as an atom or a string (`nil`, `true` and `false` are not names). It is what every name meets on its way into a stylesheet (`--mw-<name>`, `.mw-theme-<name>`, §6), so no name can break out of one.

`parse/1` trims and lower-cases its argument and returns a color or `nil`. A non-binary argument returns `nil`. Accepted syntaxes:
- **hex:** `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`. Short digits are doubled; an alpha byte becomes `opacity = a / 255`. Any other length after `#`, and a non-hex digit, return `nil` (visualize raised for a non-hex digit; a parser of untrusted text answers rather than raises);
- **`rgb(r, g, b)` and `rgba(r, g, b, a)`:** integer channels, optional decimal alpha, any whitespace around separators. Percentages are not accepted;
- **`rgb(r g b)` and `rgb(r g b / a)`:** CSS Color 4's space-separated form, decimal numbers with an optional exponent (`1.0e-5`), as `to_css/1` writes them (§1.6). Percentages are not accepted;
- **`hsl(h, s, l)` and `hsla(h, s, l, a)`:** decimal components, `%` optional on `s` and `l`;
- **named colors:** the 148 CSS color keywords (the 147 classic names plus `rebeccapurple`, with `gray` in both its spellings).

A string that matches none returns `nil`. `named/1` is the lower-case hex string for a keyword (case-insensitively) or `nil`; `named_colors/0` is the keyword list.

```test:color-parse-forms
parse reads every hex length, rgb and rgba, the space-separated rgb, hsl and hsla and the 148 keywords case-insensitively and trimmed; any other text, a bad digit and a non-binary are nil; named gives a keyword's hex
```

```test:color-literal-canonical
every constructor builds the canonical struct, its fields floats in range and no negative zero; literal? refuses a struct with integer fields; equal colors built by different constructors are equal and have one digest; name? holds of lower-case words only
```

### 1.2 Constructors, conversions and manipulation {#themes-color-convert}

- **Constructors.**
  - `rgb/3,4` clamps channels to `[0, 255]` and opacity to `[0, 1]` without rounding, each a float.
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
  - `interpolate_rgb/3` is linear and unrounded, and built by `rgb/4`, so clamped.
  - `interpolate_hsl/3` and `interpolate_hcl/3` take the shorter hue arc.
  - `interpolate_lab/3` interpolates in Lab.
  - Every result other than RGB passes through its constructor and is rounded. `t` is not clamped; the result's fields are, as every constructor's are (§1.1).
- **OKLab and OKLCH** (Björn Ottosson, 2020; CSS Color 4 §9).
  - `to_oklab/1` is `%{l, a, b, opacity}`, and `to_oklch/1` is `%{l, c, h, opacity}`, with `l` in `0..1` and `h` in `[0, 360)`.
  - `oklab/3,4` and `oklch/3,4` build a color, **gamut-mapped** by CSS Color 4 §13.2: chroma is reduced in OKLCH by binary search until the clipped color is within a ΔEOK of 0.02, and a result too light or too dark becomes white or black.
  - `delta_eok/2` is the OKLab distance.

```test:color-conversions-exact
lab of to_lab is the color and a gray has a and b zero; OKLab of the sRGB primaries matches the published values; contrast and luminance follow WCAG; each manipulation and interpolation follows its formula; an out-of-gamut OKLCH is chroma-reduced at its lightness and hue to within 0.02, and one past either end is white or black
```

### 1.3 Typed colors and their transforms {#themes-color-typed}

A document names a color as a **typed value**, never a bare atom; the values are plain data, built by functions that check their arguments and compile nothing, and resolved against a theme (§3.1), so a theme swap changes every color derived from the theme's colors. **A literal is the term `%Macaw.Layers.Color{}`** of §1.1, **never a string**: CSS text is an encoding, read into a literal at the edge (`parse!/1`, `~RGB`, §1.6) before it is a color.

| Value | Built by | Meaning |
|---|---|---|
| `{:color, name}` | `color(name)` | the color `name` of the theme's color table (§2.2), the name a string (`color(:red)` is `{:color, "red"}`) |
| `{:series, i}` | `series(i)` | the i-th series color, cycling |
| `{:ramp, name, t}` | `ramp(name, t)` | the color at `t` along one of the theme's ramps (§2.3), the name a string (`ramp(:thermal, 0.7)` is `{:ramp, "thermal", 0.7}`) |
| `%Macaw.Layers.Color{}` | `parse!/1`, `~RGB"…"`, `rgb/4` … | a literal color, itself (allowed by the `:open` profile alone, §4) |
| `{:intensity, c, t}` | `intensity(c, t)` | how much of `c` is present; the rest is transparent |
| `{:blend, [c, …]}` | `blend(list)` | the colors mixed in OKLab, each weighted by its intensity |
| `{:alpha, c, a}` | `alpha(c, a)` | `c` at opacity `a` |
| `{:lighten, c, t}`, `{:darken, c, t}`, `{:saturate, c, t}` | `lighten/2`, `darken/2`, `saturate/2` | `c` moved toward white, black or full chroma in OKLCH |
| `{:contrast, c}` | `contrast(c)` | the readable ink over `c` (§3.2) |
| `{:contrast, :under}` | `contrast()` | the readable ink over whatever the text is drawn on |
| `{:shade, c, n}` | `shade(c, n)` | the step `n` of `c`'s scale, from 0 (near white) through 500 (`c` itself) to 1000 (near black); a step the theme pins is the pinned color |

**Each helper takes the color first, and every number is in `0..1`** (a shade's step in `0..1000`), so colors pipe: `[color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)] |> blend() |> alpha(0.65)`. **A name is a string** (§2.1): `color/1` and `ramp/2` take an atom or a string and build the value with its string, so a value built in Elixir is the value a theme holds and its JSON form reads back. A typed color written by hand with an atom name is still a color value, and a theme reads its name as its string wherever it stands. A helper raises `ArgumentError` for a number outside its range, an operand that is not a color value, a name that is not an atom or a string (`nil`, `true` and `false` are not names), or an empty `blend`; it does not check that a name exists, which is the theme's to resolve. Text given as an operand raises naming the edges that read it (`parse!/1`, `~RGB`). `saturate/2` on a `%Color{}` keeps §1.2's meaning; on any other color value it builds the transform, so the transform of a literal is written as its tuple, `{:saturate, literal, t}`. `value?/1` is whether a term is a color value of the table, operands included: a literal is one where `literal?/1` holds, so a string, and a struct written by hand with integer fields, are not; `value?("good")` and `value?("#fff")` are false.

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

```test:color-typed-transforms
each builder makes its value and refuses an out-of-range number, a non-color operand, text, a non-name and an empty blend; value? holds of every tree with %Color{} leaves and of none with a string leaf; each transform equals the value computed independently through CSS Color 4's XYZ route; a blend follows color-mix's weights, premultiplied, its remainder transparent
```

### 1.4 Resolution and CSS {#themes-color-resolve}

`Color.resolve(value, theme, mode)` resolves a color value in `:literal` or `:css` mode. `:literal` answers a literal `%Color{}`; `:css` answers CSS text, a literal written by `to_css/1` (§1.6):
- **Names and positions:** a name, a series position, a ramp position and a bare slot atom resolve as `Theme.resolve/3` resolves them (§3.1). A literal is itself under `:literal`, and its `to_css/1` text under `:css`. A term that is no color value, text included, raises `ArgumentError`.
- **Transforms in `:literal`:** a transform is computed to a literal **quantized to 8 bits**, its channels and its alpha each a whole number of 255ths, exactly the color its hex `#rrggbb` (or `#rrggbbaa` below full opacity) names. Its operands are resolved as literals first, and an operand that resolves to no literal (a theme built by hand holding text) raises `ArgumentError`.
- **Transforms in `:css`:** a transform is written as CSS, so a stylesheet's theme switch carries through every derived color without a re-render. Each operand is written in its own `:css` form, a name as `var(--mw-red, #c23238)`:

  | Transform | CSS |
  |---|---|
  | `intensity(c, t)` | `color-mix(in oklab, C t%, transparent)` |
  | `blend([…])` | `color-mix(in oklab, C1 p1%, C2 p2%)`, the weights scaled to sum to 1 when they sum above 1. Three or more nest: the first n − 1 mixed at weights normalized among them, then mixed with the last at their sum. A weight of 0 is left out, a blend of nothing is `transparent` |
  | `alpha(c, a)` | `oklch(from C l c h / a)` |
  | `lighten(c, t)` | `oklch(from C calc(l + (1 - l) * t) c h / alpha)` |
  | `darken(c, t)` | `oklch(from C calc(l * k) c h / alpha)`, `k = 1 − t` |
  | `saturate(c, t)` | `oklch(from C l calc(c + (0.4 - c) * t) h / alpha)` |
  | `contrast(c)`, `contrast()` | the ink's literal, as its CSS text (visualize D-123) |
  | `shade(color(name), n)`, `n` pinned | `var(--mw-<name>-<n>, literal)`, a property the sheet declares |
  | `shade(c, n)` toward white / black | `oklch(from C calc(l + (0.97 - l) * u) calc(c * k) h / alpha)` / `oklch(from C calc(l - (l - 0.2) * u) calc(c * k) h / alpha)`, `u` and `k = 1 − u²` as numbers |
  | `shade(c, 500)` | `C` |

  A number is written with at most four decimals and no trailing zeros. The literal a browser evaluates from this CSS by CSS Color 4 and 5 is the literal `:literal` mode computes, within a channel's rounding; the tests hold the two to it with an evaluator of the CSS written from the CSS specifications alone.

```test:color-css-agrees
every transform's CSS, evaluated by an evaluator written from CSS Color 4 and 5, gives the literal mode's color within a channel's rounding; names resolve to var references with their literal fallback
```

### 1.5 Color-vision simulation {#themes-color-vision}

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

```test:color-vision-machado
each deficiency's matrix is Machado's at severity 1, every gray is its own simulation, opacity is kept, none is the identity, and recolor replaces hex literals but not url references
```

### 1.6 The adapters {#themes-color-adapters}

A literal color is a term (§1.1); its encodings are made and read at the edges, by the adapters, and nothing inside judges a color by one.

**In, from text.** `parse/1` reads untrusted text and answers `nil` for anything it does not read (§1.1). Two edges read text a program holds:
- **`parse!/1`** is `parse/1` that raises `ArgumentError`, naming the text, for text it does not read: `parse!("nope")` raises;
- **`~RGB"#3b6fa8"`**, a sigil (`import Macaw.Layers.Color, only: [sigil_RGB: 2]`), reads its text with `parse/1` when the code compiles and compiles the color in, so text it does not read is a `CompileError` at that line, never a fault at run time. It takes no modifiers.

**Out, to CSS.** `to_css/1` writes a literal as CSS: `#rrggbb`, or `#rrggbbaa` when `opacity < 1`, where the color is **8-bit exact** (`exact?/1`: whole channels and an opacity that is a whole number of 255ths), else `rgb(r g b / a)`, each number in its shortest form that reads back exactly. `parse!(to_css(c)) == c` for every literal `c`.

**JSON.** `Macaw.Layers.Color.Form` is the colors' JSON adapter, for a document type that holds colors (spec/01 §6) to call from its `Form` callbacks: `tags/0`, the colors' tags for its tag table; `encode_value/1`, a color's map form or `:default`; and `decode_value/2`, the value of one of those tags, its payload already read, or `:default`, which the kernel refuses at its path. A literal is the tag `$rgb`:

| Literal | Map form |
|---|---|
| 8-bit exact | `{"$rgb": "#3b6fa8"}`, eight digits when `opacity < 1` |
| any other | `{"$rgb": [r, g, b, a]}`, its four fields |

Reading `$rgb` builds the canonical literal, so `decode_value("$rgb", p)` of the payload `p` that `encode_value(c)` writes is `c` for every literal `c`. A payload other than `#` and six or eight hex digits, or four numbers in their ranges, is no color, and a struct that is not a literal has no form. The color values' tags are §5's: a name in `$color` and `$ramp` is written from either spelling and read as its string (§2.1), never an atom, and a `$ramp` of a name that is none of `ramp_names/0` is no color. A theme document's tag table lists `$rgb` (§5).

```test:color-adapters-edges
parse! of to_css is the color for every 8-bit-exact literal and for literals that are not; parse! raises naming the text; the sigil compiles a literal in and an unreadable text is a compile error; to_css writes hex where exact and rgb() otherwise
```

```test:color-adapters-json
the $rgb payload encode_value writes of any literal decodes to that literal, as hex where 8-bit exact and as four numbers otherwise; a malformed payload is refused at its path; a theme document's map form carries a literal through $rgb
```

## 2. The theme {#themes-theme}

### 2.1 Fields and slots {#themes-slots}

`%Macaw.Layers.Theme{name, series, axis, grid, text, background, surface, ramps, colors, styles, defaults, font_family, font_size, label_size, title_size, dark, light, extensions}`:

- **`name`** — the theme's name, a string, a built-in theme's (`"default"`, `"dark"`, `"color_safe"`, `"print"`) and a host's alike (macaw_layers#16). An atom given is its string (`name: :house` is held as `"house"`), so `new(name: :house)` and `new(name: "house")` are one theme, and a theme built in Elixir and the one its document reads are one value.
- **`series`** — a non-empty list of at most 64 literal colors, far past the categories a reader can tell apart by color; its slots are `"series_1"` … `"series_64"`.
- **`axis`, `grid`, `text`, `background`, `surface`** — the **furniture**, literal colors.
- **`ramps`** — each ramp name of §2.3 to its anchors.
- **`colors`** — the theme's own part of its color table (§2.2).
- **`styles`** — each palette name of §2.4 to its entry.
- **`defaults`** — the theme's own root defaults, an adopter's node (visualize's `:defaults`, its spec/14 §3.8), keyed by name, carried and merged key by key and otherwise not read here: its names are strings and the words of its entries are kept as given.
- **`font_family`** — a CSS font-family string; **`font_size`, `label_size`, `title_size`** — numbers in pixels.
- **`dark` and `light`** — the name of the built-in theme that stands for this one in the viewer's dark or light color scheme, a string as `name` is (an atom given is its string), or `nil` (§6).
- **`extensions`** — the registered extensions (§3.4), `[]` by default.

Every field is plain data, so a theme is stored and compared as a value. **Its colors are terms:** every color it holds — the series, the furniture, the ramps' anchors, the entries of `colors` and their pinned steps, and the paint colors of `styles` — is a literal `%Macaw.Layers.Color{}` (§1.1) or a typed color of §1.3 with literal leaves, **never a string**. `new/1` and `merge/2` raise `ArgumentError` for text where a color belongs, naming the field and the edges that read text (`Theme.new(axis: "#555")` raises `theme "default": axis "#555" is text, and a string is never a color: read it with Macaw.Layers.Color.parse!/1, or write ~RGB"#555"`), and for any other term there that is no literal. Compare two literals with `===` or by digest where identity matters: a struct written by hand with integer fields is `==` to the canonical one but is no literal (§1.1).

**Names are strings** (macaw#188, decision 2 applied to themes): every name inside a `%Theme{}` is a string, the library's, its extensions' and a host's alike. The names are the theme's own `name` and its `dark` and `light`, the keys of the four name maps — `ramps`, `colors`, `styles` and `defaults` — the slots, the name in every typed color (`{:color, "good"}`, `{:ramp, "status", 0.5}`) wherever it stands (a ramp's anchors, a color entry and its pinned steps, a palette entry's paints and nodes, `defaults`), and a palette name in a list entry. **Atom input is normalized once, at construction** (`new/1`, `merge/2`, and a document read, §5), by one function: an atom name is its string, so `colors: %{"info" => c}` and `colors: %{info: c}` are one name, and a host's name spelled like the library's (`"info"`) is that name, **the host's entry winning** over the default it replaces. A typed color's name normalizes the same way: `{:color, :good}` given is `{:color, "good"}` held, and `{:ramp, :status, t}` is `{:ramp, "status", t}`. A bare atom in a paint's color (§2.4) is the typed color of its string. One name given **both as its atom and as its string in one map** is a mistake, never silently resolved: `new/1` and `merge/2` raise `ArgumentError` naming the theme, the map and the name, and a document is `{:duplicate, :name}` at the name's path (§5). Every function that takes a name — `resolve/3`, `style/2`, `cue/1`, `color_name?/2`, `ramp/3` — takes either spelling, and every list of names (`slots/1`, `color_slots/1`, `color_names/1`, `style_names/1`, `ramp_names/0`, `role_names/0`, `series_slot/2`) answers strings.

**Words are kept as given.** A palette entry's and a default's keys and atom values (`curve: %{type: :monotone_x}`, `font: %{line_height: 1.2}`) are words, not names: a theme built in Elixir holds them as written, whatever the library's vocabulary. The vocabulary bounds only what reading a document may make an atom of (§5; spec/01 §6), never what a theme may hold.

A **slot** names one value of a theme:

| Slot | Field | Used for |
|---|---|---|
| `"series_1"` … `"series_n"`, or `{:series, i}` | `series` | the i-th categorical color; `{:series, i}` cycles, so on ten colors `{:series, 11}` is `"series_1"` |
| `"axis"`, `"grid"`, `"text"`, `"background"`, `"surface"` | the furniture | lines, grids and links behind the data, text, the page, the plane the data lies on |
| `"good"`, `"warning"`, `"bad"` | `colors` | the status roles, by default the `status` ramp at 0, 0.5 and 1 |
| `"info"`, `"neutral"` | `colors` | the remaining roles |
| `"font_family"`, `"font_size"`, `"label_size"`, `"title_size"` | the font fields | every text, the smallest, the labels, the titles |

A slot is a name, a string; a function that takes one takes its atom too (`resolve(theme, :axis, :css)`). `slots/1` lists a theme's slots in that order. `series_slot/2` is the `"series_k"` that `{:series, i}` cycles to. A slot that is none of these, or `"series_k"` outside `1..n`, raises `ArgumentError` in every function that takes a slot. `color_slots/1` is the color slots alone: the series, the furniture, then the five roles. A style's font part names the font slots by their words (`font: %{size: :label_size}`, §2.4), which are not names.

```test:themes-slots-order
slots lists the series then the furniture, roles and font slots in order; series positions cycle; an unknown slot or a series slot beyond the palette raises
```

```test:themes-colors-terms
new raises for text in the series, the furniture, a colors entry, a pinned step, a ramp anchor or a style's paint color, naming parse!/1 and ~RGB, and for a struct that is no literal; Theme.new(axis: "#555") raises with the message
```

```test:themes-names-strings
a host's "info", ramp "status" and style "muted" are the library's names, the host's entry resolving; one name given both as its atom and its string in one map raises; over generated themes every name the theme holds is a string, one key per spelling, and atom and string inputs and queries agree; a typed color's name is held as its string wherever it stands, a ramp anchor {:color, :brand} included
```

```test:themes-names-own
new(name: :house) and new(name: "house") are one theme; every built-in's name, dark and light are strings and builtin("dark") is builtin(:dark); a theme document naming dark: "dark" or :dark reads to the same theme, a version 1 document's {"$atom": "dark"} migrates to "dark", and at version 2 a $atom there is refused
```

```test:themes-words-given
a palette entry's and a default's words outside the library's vocabulary survive new/1 as given
```

### 2.2 The color table {#themes-color-table}

Every color a document names with `color(name)` is looked up in the theme's **color table**, in this order:
1. the theme's own `colors`;
2. the default theme's `colors`;
3. the colors the theme's extensions add (§3.4);
4. the **CSS named colors** (§1.1).

The furniture and `"series_1"` … `"series_n"` are names of the table too, read from their fields. A theme may change any value, and add names, each held by its string (`colors: %{brand: …}` is held under `"brand"`); a host's name spelled like one of the library's (`colors: %{"info" => …}`) is that name, its value replacing the default's (§2.1). A name is asked of the table by either spelling, and must be lower-case letters, digits and `_`, starting with a letter. A value is a literal color, or a color value of §1.3 that resolves through the same theme (`{:ramp, "status", 1}`); text is refused, naming the edges that read it. A CSS named color is the table's literal of its keyword (`color(:steelblue)` is `parse!("steelblue")`).

**A theme may pin steps** of a name: `colors: %{red: %{500 => ~RGB"#d62728", 100 => ~RGB"#fde8e8"}}`, a map of integer steps in `0..1000` with 500 among them to literal colors. Step 500 is the name's own color, and a step not pinned is computed on §1.3's curve. A pinned entry without step 500, with a step outside `0..1000` or not an integer, or with a value that is no literal color, text included, is refused.

The built-in themes' own `colors`, each a literal written here by its hex:

| Name | `default/0` | `dark/0` |
|---|---|---|
| `"red"`, `"amber"`, `"green"` | `#c23238`, `#bd7407`, `#4ca34b` | `#ff8f8a`, `#db8e1c`, `#4f924c` |
| `"blue"`, `"gray"` | `#3b6fa8`, `#6f7480` | `#7fb3e6`, `#b7bcc6` |
| `"good"`, `"warning"`, `"bad"` | `{:ramp, "status", 0}`, `{:ramp, "status", 0.5}`, `{:ramp, "status", 1}` | as the default |
| `"info"`, `"neutral"` | `#3b6fa8`, `#6f7480` | `#7fb3e6`, `#b7bcc6` |

`color_names/1` lists a theme's table, sorted. `color_name?/2` answers membership without building the list (visualize D-184). A theme's `roles` key, the role colors of before visualize#663, is read as `colors`.

```test:themes-color-table-lookup
a name resolves from the theme's colors, then the default's, then an extension's, then the CSS names; furniture and series are names; a host's name is held by its string and found by either spelling, a host's name spelled like the library's replacing it; pinned steps need 500 and integer steps in range
```

### 2.3 Ramps and roles {#themes-ramps}

A palette position promises *distinct*, never a meaning. Colors that carry meaning a reader brings with them — the stop-light, cold and hot, below and above a target — are carried as **ramps**, whose meaning the library fixes and whose tones the theme tunes (visualize D-135).

**A ramp** is two or more anchors (a literal color, a name of the table, or a transform of those, measured as the literal it computes; text is no anchor), evenly spaced along `0..1`, the color at `t` interpolated between its two neighbors in **CIE Lab**, a literal `%Color{}` (`interpolate_lab/3`). A position on an anchor is that anchor's literal. Four ramps, each with its **contract**:

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

```test:themes-ramps-contracts
ramp interpolates in Lab between evenly spaced anchors and clamps t; each built-in theme holds every ramp and role contract; a ramp breaking hue order, lightness, neutrality, chroma or family is refused naming the anchor and the term; a missing ramp falls back to the default's; cue gives each role's glyph and dash
```

### 2.4 The style palette {#themes-palette}

`styles` carries the palette over to **whole styles** — fill, stroke and its width, dash, opacity, marker, font — so a document can name a whole look by position, by meaning or by view state, and a theme swap restyles it.

| Group | Names | Promises |
|---|---|---|
| style series | `"style_1"` … `"style_n"`; `{:style, i}` cycles | distinct whole looks for categories, differing between neighbors in more than hue |
| style roles | `"good"`, `"warning"`, `"bad"`, `"info"`, `"neutral"` | a meaning as a whole style: the role's color and its cue |
| state styles | `"hover"`, `"focused"`, `"selected"`, `"active"`, `"disabled"`, `"muted"`, `"emphasis"`, `"breakpoint"` | what a view state looks like, laid over an object's own look |
| furniture styles | `"axis"`, `"grid"`, `"label"`, `"title"`, `"caption"`, `"value"`, `"annotation"` | the furniture's lines and each kind of text |
| modifiers | `"bold"`, `"italic"`, `"thin"`, `"thick"`, `"dashed"`, `"dotted"`, `"outline"` | one change each, to stack on a look |

A palette name is a string, as every name of a theme is (§2.1); `style/2` takes its atom too.

A theme chooses only how many style series it has, at most 64 with no gap, and how each entry looks. **It cannot add a name**: the names are the library's and its registered extensions' (§3.4), so a document that names one reads the same on every theme.

**An entry is a style node in parts, written in slots:** its keys are the parts `fill`, `stroke`, `font`, `text`, `effect`, `marker`, `curve`, and `opacity`, `blend` and `class`. Its colors are typed values or slots, never literals where a slot says the same, and never text (a string paint color is refused, §2.6) (`fill: %{type: :solid, color: {:color, "bad"}}`, `stroke: %{type: :solid, color: {:series, 3}, width: 1.5}`, `font: %{size: :label_size}`). A bare atom in a paint's color is the typed color it names, its name a string (`color: :text` is held as `{:color, "text"}`). An entry's keys and atom values are words, kept as given (§2.1). In a role's entry, `stroke: %{dash: :cue}` and `marker: %{shape: :cue}` take the role's cue. An entry may be **a list** of palette names and nodes, stacked left to right. It may not use `extends`: the palette is the end of every chain. Entries may be partial: a state or a modifier gives a few keys.

**The built-in palette**, the same entries on every built-in theme, each taking that theme's colors:

| Name | Entry |
|---|---|
| `"style_1"` … `"style_10"` | a solid `fill` and `stroke` of `{:series, k}`, `width: 1.5`; markers `:circle :square :triangle :diamond :cross :star :wye :circle :square :triangle`; dashes solid, `"8 3"`, `"3 3"`, `"8 3 3 3"`, `"1 3"`, repeated |
| `"good"` … `"neutral"` | a solid `fill` of `{:color, role}`, the role's name; a solid `stroke` of it with `dash: :cue`; `marker: %{shape: :cue}` (on `print/0`, hatched fills, §2.5) |
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

`style(theme, name)` is an entry — a name, or `{:style, i}` cycling — as a flat node, the default theme's entry whole when the theme lacks it, `:cue` replaced by the role's cue (its dash left out where solid). `style_names/1` lists the names, strings: the style series, then roles, states, furniture and modifiers, then the extensions'. **Fallback** is whole, never key by key, since a partial entry laid over another theme's would be a look neither chose.

```test:themes-palette-entries
the built-in palette gives every entry of the table on every built-in theme; style resolves cues and cycles style positions; a missing entry falls back to the default's whole; a theme cannot add a name; a list entry stacks and may not reach itself
```

### 2.5 The built-in themes {#themes-builtins}

Every color below is a literal `%Color{}`, written here by its hex and in the source by `~RGB`: the values, the resolution of every slot and name, the stylesheet and the answers of `check/1` and `floors/1` are those of the themes that held them as text (v0.2.4).

| Field | `default/0` | `dark/0` |
|---|---|---|
| `series` | `#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480` | `#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6` |
| `axis`, `grid`, `text` | `#666666`, `#e0e0e0`, `#333333` | `#a0a4ab`, `#33373f`, `#e6e6e6` |
| `background`, `surface` | `#ffffff`, `#eef2f6` | `#1b1e24`, `#23272f` |
| `ramps.status` | `color(:green) color(:amber) color(:red)` | the same names |
| `ramps.thermal` | `#0e68ad #e8e8e8 #c02e31` | `#7fb3e6 #3a3f48 #f47c7c` |
| `ramps.diverging` | `#b35806 #ededed #62448e` | `#f7a35c #3a3f48 #c1acee` |
| `ramps.sequential` | `#e9f2fc #5e95d3 #004580` | `#273b4f #457cb1 #aad1f9` |
| `dark`, `light` | `"dark"`, `nil` | `nil`, `"default"` |
| fonts | `sans-serif`, `10`, `12`, `16` | the same |

- **`color_safe/0`** is the default named `"color_safe"`, its `status` running blue → orange → red, `#5996d6 #cd6012 #b92931`, which survives the commonest color-vision deficiencies. Its lightness still falls at each step.
- **`print/0`** is paper:
  - a white `background` and `surface`, text `#111111`, axis `#333333`, grid `#c8c8c8`;
  - the color-safe `status` ramp;
  - role styles whose fills are hatches of the role's color: `:good` lines at 45°, `:warning` at 135°, `:bad` a crosshatch, `:info` dots, each spacing 6 and width 1, and `:neutral` solid.

`builtin/1` is the theme of a built-in name, given as its string or its atom (`builtin("dark") == builtin(:dark)`), else `nil`. `new/1` is `default/0` with the given fields replaced and `ramps`, `colors`, `styles` and `defaults` merged key by key. `merge/2` does the same for any theme. An unknown field raises `KeyError`, an empty `series` raises `ArgumentError`, and a contract broken raises `ArgumentError` (§2.6).

```test:themes-builtins-values
each built-in theme has the table's values and pairs default with dark; color_safe and print change exactly what the section says; new and merge replace fields and merge ramps, colors, styles and defaults by key; an unknown field and an empty series raise
```

```test:themes-colors-goldens
every slot, name, series and ramp position of every built-in and of a host theme resolves to parse! of its v0.2.4 hex and its CSS to v0.2.4's; their stylesheet is v0.2.4's byte for byte; check, violations and floors answer as on v0.2.4
```

### 2.6 Contracts and contrast {#themes-contracts}

**Contracts are checked when a theme is built:** `new/1` and `merge/2` check every ramp, color and palette entry, and raise `ArgumentError` naming the theme, the subject and the term it breaks:

> `theme "house": ramp "status" breaks its contract: lightness must change one way along the ramp, by at least 3 L* a step …`

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
- **A paint's color is no text:** a `fill` or `stroke` whose `color` is a string is refused, naming the edges that read it.
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

The built-ins hold them. `floors/1` answers `:ok` or `{:error, faults}`, each fault `{slot, {:contrast, ratio, floor}}`, the slot by its name (`"text"`, `"series_2"`; the ratio floored to two decimals, a translucent color laid over the background first), or `{"surface", {:equal, "grid"}}`. **Contrast is checked once, on the theme** (macaw_compose spec/10): a host offers a theme only when `floors/1` and `check/1` pass, and a user-defined theme that fails is refused (macaw_compose spec/11 §1).

```test:themes-palette-contracts
each palette contract refuses its fault with the theme, the entry and the measured value named: an unknown name, a gap, extends, a misplaced cue, two roles alike without hue, two role colors too close, a role paint under 3:1 or text under 4.5:1, an unknown color, a state that changes only color, neighbors alike, a font missing, a grid with no stroke, a modifier of two keys
```

```test:themes-floors-builtins
every built-in theme meets the floors and every contract; floors refuses text under 4.5:1, an axis or series color under 3:1, a grid under 1.2:1 and a surface equal to the grid
```

## 3. Resolution, the ink and extensions {#themes-rules}

### 3.1 Resolution {#themes-resolution}

`resolve(theme, slot_or_name, mode)` is the one door through which anything reads a theme:
- **`:literal`:** the value as stored: a color a literal `%Color{}`, a font a string, a size a number. A canvas and a PNG resolve this way.
- **`:css`:** a custom-property reference with the literal as its fallback, a color written by `to_css/1` (§1.6): `var(--mw-axis, #666666)`, `var(--mw-series-3, #c8373b)`, `var(--mw-font-size, 10px)` (a size gains `px`). This is what an SVG or HTML output carries.
- **Roles and names:** a role, and a name of the table, resolve the same way, `:red` to `var(--mw-red, #c23238)`. A name in no part of the table raises `ArgumentError`.
- **Ramp positions:** `{:ramp, name, t}` is a **literal in both modes** (CSS has no property per position), its `to_css/1` text under `:css`, except the status roles' positions, which resolve as the roles. `t` is clamped, and a ramp name not of §2.3 raises.

`css_name/1` is `--mw-` and the name with `_` as `-` (`"series_1"` → `--mw-series-1`).

**The reference carries its fallback rather than the root declaring the property** (visualize D-55): a declaration on an element would beat every ancestor rule, so a theme could not be switched from a class. With the fallback, output rendered outside any stylesheet still draws in its theme, and a class on any ancestor overrides it.

```test:themes-resolve-modes
resolve gives a literal or a var reference with the literal fallback for every slot, role and name, sizes in px; ramp positions are literals except the status roles' positions; css_name maps names; an unknown name raises
```

### 3.2 The contrast ink {#themes-ink}

`ink(theme, under)` (visualize D-123) is the color a text drawn on `under` takes: the theme's `text` or `background`, whichever contrasts more with `under` (`text` on a tie), **always as a literal `%Color{}`**. When the better of the two is under 4.5:1, it is black or white instead, one of which always reaches 4.58:1 or better. `under` is a literal `%Color{}`, or `nil` for the theme's background; text raises `ArgumentError` naming the edges that read it, as any other term does. A slot that holds no literal, in a struct written by hand, is skipped. It is a literal because the choice is made between literals: a re-pointed custom property would undo it.

```test:themes-ink-aa
ink chooses text or background by contrast, text on a tie, and black or white when neither reaches 4.5:1, so the ink always meets 4.5:1, a literal; nil is the background, text under it raises, and a slot holding no literal is skipped
```

### 3.3 Precedence {#themes-precedence}

Where a color comes from, highest first:
1. a choice the document makes: under the `:open` profile a literal, or a document's own color scale or palette entry of a name;
2. the theme's rendering of a role, ramp position or palette name the document names;
3. the default theme's;
4. an extension's default.

**One theme per page.** A component's own theme setting (a visualize design's `theme`) is an override the page **masks** (spec/02 §4); standalone, it applies. **Themes stack** like any fragment (§5): a host's theme is a layer over a built-in.

```test:themes-precedence-layers
a document's palette entry beats the theme's, the theme's the default's and the default's an extension's; a page masks a component's theme key; a theme document stacked over a built-in is the merged theme
```

### 3.4 Extensions: what adopters register {#themes-extensions}

**Adopters register what their documents name beyond the library's vocabulary**, so one theme styles them (visualize's mark roles). An extension is a module implementing `Macaw.Layers.Theme.Extension`:

| Callback | Contract |
|---|---|
| `name() :: String.t()` | the extension's name, for faults |
| `styles() :: %{name => {group, entry}}` | palette names it adds, each in a group of §2.4 (`:state`, `:furniture`, `:modifier`), with its default entry |
| `colors() :: %{name => color}` | names it adds to the color table, each with a default value: a color value of §1.3, a literal `%Color{}` or a typed color, or pinned steps of literals; text raises `ArgumentError` naming the extension |
| `words() :: %{keys: [atom], atoms: [atom]}`, optional | the words its styles and defaults use beyond the library's: the keys and the atom values a theme document's JSON form may spell (§5) |

A theme carries its extensions in `extensions`, given explicitly (`new(extensions: [MyApp.Marks])`). The list is **default closed**: a palette name or color name that neither the library nor an extension has is a fault naming it. **An extension's names are strings in the theme,** as the library's are (§2.1): a name `styles/0` or `colors/0` gives as an atom (`lane:`), and the names in its entries' typed colors, are read as their strings by the theme's one normalization, and a name given both ways in one map raises `ArgumentError` naming the extension. The names an extension adds are held to the contracts of their group, its default entries included: a state's, a modifier's, and a furniture entry's as text furniture's when it has a font part and as the grid's otherwise. An extension's names follow the library's in `style_names/1` and `color_names/1`. Two extensions adding one name, an extension adding a library name, or a style in another group, raise `ArgumentError` naming both.

**An adopter's words are the JSON reader's vocabulary, never the theme's.** A theme built in Elixir keeps its words as given (§2.1), whatever an extension registers. `words/0` serves the theme document (§5): `to_json/1` writes the theme's words with its extensions' keys, and `from_json/2` makes atoms of the library's words and those of the extensions it is given (`extensions:`), and of no other. A theme whose styles or defaults use an adopter's words reads back from its JSON form only with that adopter's extension given; without it, a word the reader may not make is refused at its path (an atom value `{:enum, allowed}`).

```test:themes-extensions-registered
a registered extension's names are in the palette and the table with their defaults, held to their group's contracts; an unregistered name is a fault naming it; two extensions adding one name raise naming both
```

```test:themes-extension-words
an extension's words in a theme's styles and defaults survive new/1 and read back from JSON with the extension given, its words the reader's vocabulary; without it the reader refuses the word at its path, and no atom is made from the document
```

## 4. Literal and data colors: the profile {#themes-profile}

- **Drawing colors are theme roles and tokens, and values derived from them** (`lighten(:warning)`), so contrast is checked on the theme (metresis.md C3).
- **Literal colors are a profile's.** `Theme.check_color(value, profile)` answers `:ok` or `{:error, {:literal_color, value}}`:
  - under **`:roles`**, the profile every Macaw page validates against, a color value whose leaves include a literal `%Color{}` is refused;
  - under **`:open`**, an adopter's standalone default (visualize's), literals are allowed.

  A term that is no color value, text included, raises `ArgumentError` under either profile: a string is never a color.

  The profile is the host's authority: nothing derives it.
- **Data colors are typed content.** A `:color` column or a schema's value color (a team's color) is shown only with a non-color cue (a glyph, a label or a dash), which is the component's obligation, and under a **contrast guard**. `Theme.data_color(theme, value)` is:
  - `{:ok, literal}`, the literal `%Color{}` it resolves to, where the color reaches 3:1 against the theme's background;
  - `{:error, {:contrast, ratio}}` otherwise;
  - `{:error, :unreadable}` for a term that is no color value, text included, or does not resolve; it never raises, since a data color comes from data.

  A data color is never the sole carrier of meaning (macaw_data spec/01 §1; macaw_compose#22, decision 7; visualize D-233).

```test:themes-profile-colors
under roles a literal anywhere in a color value is refused and every typed value passes; under open both pass; text raises under both; a data color under 3:1 against the background is refused with its ratio, one that reaches it is its literal, and text is unreadable
```

## 5. A theme as a document {#themes-document}

A theme is stored and shipped as a value, so it is a **document** (spec/01): `Macaw.Layers.Theme.Document` implements `Macaw.Layers.Document`, `Version`, `Form` and `Fragment` (spec/02 §1), its one kind `:theme`, so `%{theme: node}` derives to it. A theme document is the theme's fields under `theme`, all but `extensions`, which are the host's and never travel:

| Form | What |
|---|---|
| value | `%{version: v, theme: node}` (`to_map/1`); the store's fragment `%{theme: node}` (`fragment/1`), a library entry of kind `:theme`, reads as the same document; every name a string, as the theme holds it (§2.1) |
| JSON | `{"$version": v, "theme": {…}}` (`to_json/1`, through the JSON adapter, `Form.to_json/2`), each color a tag: a literal color `{"$rgb": …}` (§1.6), `{"$color": name}`, `{"$series": i}`, `{"$ramp": [name, t]}`, each transform by its name with `[C, number]` (`{"$lighten": [C, 0.3]}`), `{"$blend": [C, …]}`, `{"$contrast": "under" \| C}`; pinned steps as `{"$steps": [[n, C], …]}`; each `C` a color's own tag, a literal's `$rgb`, never a bare string |

`from_map(document, opts)` takes `extensions:`, the extensions the host registers, which the theme read carries and its contracts hold; `from_json(json, opts)` takes `extensions:` and `limits:`, the JSON adapter's (spec/01 §5), and reads with the extensions' words as the reader's vocabulary (§3.4, spec/01 §6). `to_json/1` writes with the theme's own extensions' words. A `series` longer than 64 is `{:limit, :series, 64, n}`.

**The version line is at 2** (`current/0`). Version 1 wrote a literal as CSS text; its **step to 2** (spec/01 §4) tags each string at a color position of the map form that `parse/1` reads as the literal's `$rgb` (`ColorForm.encode_value/1`): each `series` entry; the furniture `axis`, `grid`, `text`, `background` and `surface`; each ramp's anchors; each entry of `colors`; each value of a `$steps`; the operand of each transform (`$intensity`, `$alpha`, `$lighten`, `$darken`, `$saturate`, `$shade`), of `$contrast` but `"under"` and each color of a `$blend`, at any depth; and the `color` of each `fill` and `stroke` of a style node, in a list entry too. A string it does not read is left as it is, for the reader to refuse at its path; a name in a list entry, a node that is a theme's name, `defaults` and every other key are not color positions. Version 1 also wrote a built-in theme's name as a `$atom`; the step makes a `$atom` that is the node itself, or its `name`, `dark` or `light`, the string it spells (#16), so those are strings at version 2. So a version 1 document reads to the same theme, and a bundle's entry of one does too, since a bundle migrates each entry by its type (spec/03 §3.2).

**Fragment rules:** `ramps`, `colors`, `styles` and `defaults` are `:union` name maps, and every other key is `:override`, so a theme stacks over a built-in as `new/1` merges (§2.5).

**Names are strings.** The four are name maps (`name_map?/1` by `Fragment.name_map?/2`, spec/01 §6), whose names are strings (spec/01 §1), as the theme holds them (§2.1): `node/1`, and so `fragment/1`, `to_map/1` and `to_json/1`, writes the theme's names as they are, so a theme fragment is written by the JSON adapter like any other (`Form.to_map/2`, a bundle's entry), and the JSON form's names read back as the strings they are. The theme's own `name` and its `dark` and `light` are names too, written as JSON strings (`"dark": "dark"`); a node built in Elixir spelling one as an atom reads as its string. Version 1 (macaw_layers 0.2.4) wrote a built-in's as a `$atom`; the step to version 2 makes it the string it spells, and at version 2 the JSON form spells them as strings only. Reading has one path: `from_map/2` and `from_json/2` give the node to the theme's one normalization (§2.1), so a node built in Elixir with atom names reads as the same theme, and a value giving one name both as its atom and as its string in one name map is `{:duplicate, :name}` at `[:theme, map, name]`. `Form.to_map/2` refuses a node with atom names, `{:type, :name}` at each. The words of an entry are read by the JSON adapter against the library's vocabulary (`Macaw.Layers.Theme.Words`: the fields, the style parts and their keys, the built-in palette's atom values and the font slots' words) and the given extensions' (§3.4).

**Reading.** A theme document is judged on its value, never on a form of it (spec/01 §5):
1. **the value's way in:** `from_map/2` checks the value's `version` against the line (`{[], {:newer_schema, needs, this}}`, or `{["$version"], {:type, :pos_integer}}`), nothing of a newer document judged, and writes and reads no form; `from_json/2` reads the JSON form through the JSON adapter (`Form.read/3`): the limits, the version, the migration, the recount, then the value from the map form;
2. the envelope, by the type's `validate/1` (`Document.check/2`): a key beside `theme` is `:unknown_key`, and a missing `theme` `:required`;
3. a variable anywhere in the node, and then the theme's fields, each of its shape: an unknown key `:unknown_key`, a `series` entry or furniture that is not a literal color `{:type, :color}`, a `series` that is not a non-empty list `{:type, :colors}`, a `font_family` that is not a string `{:type, :string}`, sizes that are not positive numbers `{:type, :pos_number}`, a `name` that is not a string `{:type, :string}`, `ramps`, `colors`, `styles` and `defaults` that are not maps `{:type, :map}`, a counterpart that is no built-in `{:unknown_theme, name}`;
4. the contracts, each broken one `{:contract, message}` at `[:theme, :ramps, name]`, `[:theme, :colors, name]` or `[:theme, :styles, name]`;
5. then the theme.

A value no form can write but the theme takes, such as root defaults built under an atom name, reads by `from_map/2`; the JSON adapter refuses only what it can't write, when it writes it.

**What a theme document cannot hold:**
- **variables:** nothing applies a theme, so a variable is `{:unresolved, :var, name}`;
- **an unknown name:** a node that is a **name** reads as the built-in theme of that name, and any other name is `{:unknown_theme, name}`;
- **one name twice:** a name given both as its atom and as its string in one name map of a value, `{:duplicate, :name}`;
- **atoms from the document:** no atom is made beyond the library's vocabulary and the given extensions' words; every name is a string.

`from_map(to_map(t), extensions: t.extensions)` and `from_json(to_json(t), extensions: t.extensions)` are `{:ok, t}` for every theme `new/1` builds, the built-ins included.

```test:themes-document-forms
a theme round-trips through its value and JSON form, the built-ins and host themes with pinned steps included, its name maps holding every name as a string and read back as that string, a ramp anchor {:color, :brand} as {:color, "brand"} both ways, and a theme entry of a store through a bundle's forms and import; a newer stamp, a broken contract at its path, a variable, an unknown theme name, an unknown key and a name given both ways are refused; a theme fragment stacks over a built-in
```

```test:themes-document-v1-step
a v0.2.4 version 1 document of every built-in and of a host theme with pinned steps, transforms and literal paints reads to the same theme, also as a bundle's entry; the step tags every color position and leaves text it does not read, refused at its path; a version 2 document holding text where a color belongs is refused
```

```test:themes-document-value
from_map/2 judges a theme document's value with no form written or read: a node Form.to_map/2 refuses (an atom name in a name map) builds its theme, no limit applies to a value, and from_json/2 of the JSON form gives what from_map/2 gives of the value
```

## 6. Delivery {#themes-delivery}

A theme compiles to **custom properties scoped by a class**, `.mw-theme-<name>` (`.mw-theme-dark`), in the site's static stylesheet, served from `'self'`. Adopters emit the same class, so a visualize chart standalone and on a page reads the same properties.

- **`Sheet.rule(theme)`** is the theme's rule, its class the theme's name with `_` as `-` (a name that is not lower-case words raises `ArgumentError`, so a sheet can never be broken out of through a name):
  1. `.mw-theme-<name> {`;
  2. one `  --mw-<slot>: <value>;` per slot of `slots/1`, a color by `to_css/1` (§1.6), sizes with `px`;
  3. one line per name of the theme's own `colors` that is not a slot, in name order, as its literal's CSS text, followed by one per step it pins other than 500 (`--mw-red-100`);
  4. `}`.

  Then comes a **forced-colors block**: `@media (forced-colors: active)` declaring `--mw-text` and `--mw-axis` as `CanvasText`, `--mw-background` and `--mw-surface` as `Canvas`, and `--mw-grid` as `GrayText`. In high-contrast mode what is drawn from the theme then agrees with the user's palette, and a role still reads by its dash and glyph.
- **"Auto"** follows `prefers-color-scheme` through a media query in that same stylesheet. `Sheet.auto(light, dark)` is the rule `.mw-theme-auto` declaring `light`'s properties, then `@media (prefers-color-scheme: dark)` declaring `dark`'s under the same class, then the forced-colors block for `.mw-theme-auto`, so high contrast holds whichever class a page carries. There is **never a `<style>` element per component** (macaw_compose spec/10).
- **`Sheet.stylesheet(themes, auto: {light, dark})`** is the whole static sheet: one rule per theme offered, in order, then the auto rule. Its bytes are a pure function of its themes, so it is cached and served by its digest (spec/01 §7), and a user-defined theme's sheet is served the same way (`/themes/<hash>.css`, macaw_compose spec/11 §1).
- **Per-element styles resolve on the server** into SVG presentation attributes or classes, which is the adopter's rendering, through `resolve/3` in `:css` mode.

```test:themes-sheet-rules
a theme's rule declares every slot, its own colors and pinned steps as custom properties under its class, with the forced-colors block; auto declares the light theme and switches to the dark one under prefers-color-scheme; the stylesheet is the rules in order and depends only on its themes
```
