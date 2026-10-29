defmodule Macaw.Layers.Color do
  @moduledoc """
  Colors (spec/04 §1): parsing, construction in RGB, HSL, Lab, HCL, OKLab and OKLCH,
  conversion, manipulation and interpolation.

      color = Macaw.Layers.Color.parse("steelblue")
      color |> Macaw.Layers.Color.darker() |> Macaw.Layers.Color.to_hex()
      #=> "#044279"

  A literal color is the term `%Macaw.Layers.Color{}`, every field a float in its range
  (`literal?/1`), whatever constructor built it. CSS text is an encoding of one, read and
  written at the edges (spec/04 §1.6): `parse!/1` and `~RGB"#3b6fa8"` in, `to_css/1` out,
  and `Macaw.Layers.Color.Form` for JSON.

  `parse/1` reads untrusted text and answers `nil` for anything it does not read; it never
  raises. Lab is CIE L\\*a\\*b\\* against D50 with d3-color's constants, so `lab/4` of
  `to_lab/1` is the color again; OKLab is Ottosson's, and a color built from OKLab or
  OKLCH is brought into sRGB by CSS Color 4's gamut mapping (`Macaw.Layers.Color.Ok`).
  `Macaw.Layers.Color.Vision` simulates the dichromacies.

  Ported from visualize's `Visualize.Color` and `Visualize.Color.OK`.
  """

  alias Macaw.Layers.Color.{Names, Ok, Typed}

  defstruct r: 0.0, g: 0.0, b: 0.0, opacity: 1.0

  @typedoc """
  A literal color (spec/04 §1.1): every field a float, `r`, `g` and `b` in `0..255` and
  `opacity` in `0..1`, as every constructor builds it (`literal?/1`).
  """
  @type t :: %__MODULE__{
          r: float(),
          g: float(),
          b: float(),
          opacity: float()
        }

  # The D50 white point, with the sRGB matrices Bradford-adapted to it, as d3-color has them:
  # CIE Lab is defined against D50, and `to_lab/1` and `lab/4` are each other's inverse.
  @xn 0.96422
  @yn 1.0
  @zn 0.82521

  # Lab constants
  @t0 4 / 29
  @t1 6 / 29
  @t2 3 * @t1 * @t1
  @t3 @t1 * @t1 * @t1

  # Brighter/darker constant
  @kn 18

  # A theme's name (`name?/1`).
  @name ~r/\A[a-z][a-z0-9_]*\z/

  # -- constructors ------------------------------------------------------------------------

  @doc "Creates a color from RGB values (0-255)"
  @spec rgb(number(), number(), number(), number()) :: t()
  def rgb(r, g, b, opacity \\ 1.0) do
    %__MODULE__{
      r: channel(r),
      g: channel(g),
      b: channel(b),
      opacity: fraction(opacity)
    }
  end

  @doc "Creates a color from HSL values (h: 0-360, s: 0-100, l: 0-100)"
  @spec hsl(number(), number(), number(), number()) :: t()
  def hsl(h, s, l, opacity \\ 1.0) do
    h = rem(trunc(h), 360)
    h = if h < 0, do: h + 360, else: h
    s = clamp(s, 0, 100) / 100
    l = clamp(l, 0, 100) / 100

    {r, g, b} = hsl_to_rgb(h, s, l)

    rgb(round(r * 255), round(g * 255), round(b * 255), opacity)
  end

  @doc "Creates a color from Lab values (l: 0-100, a: -128 to 127, b: -128 to 127)"
  @spec lab(number(), number(), number(), number()) :: t()
  def lab(l, a, b, opacity \\ 1.0) do
    # Lab -> XYZ -> RGB
    y = (l + 16) / 116
    x = if is_number(a), do: y + a / 500, else: y
    z = if is_number(b), do: y - b / 200, else: y

    y = @yn * lab_xyz(y)
    x = @xn * lab_xyz(x)
    z = @zn * lab_xyz(z)

    # XYZ -> RGB (sRGB)
    r = xyz_rgb(3.1338561 * x - 1.6168667 * y - 0.4906146 * z)
    g = xyz_rgb(-0.9787684 * x + 1.9161415 * y + 0.0334540 * z)
    b_val = xyz_rgb(0.0719453 * x - 0.2289914 * y + 1.4052427 * z)

    rgb(round(clamp(r, 0, 255)), round(clamp(g, 0, 255)), round(clamp(b_val, 0, 255)), opacity)
  end

  @doc "Creates a color from HCL values (h: 0-360, c: 0-~230, l: 0-100)"
  @spec hcl(number(), number(), number(), number()) :: t()
  def hcl(h, c, l, opacity \\ 1.0) do
    h_rad = h * :math.pi() / 180
    a = c * :math.cos(h_rad)
    b = c * :math.sin(h_rad)
    lab(l, a, b, opacity)
  end

  # -- parsing -----------------------------------------------------------------------------

  @doc """
  Parses a color string into a Color struct.

  Supports:
  - Hex: "#rgb", "#rrggbb", "#rgba", "#rrggbbaa"
  - RGB: "rgb(r, g, b)", "rgba(r, g, b, a)"
  - HSL: "hsl(h, s%, l%)", "hsla(h, s%, l%, a)"
  - Named colors: "steelblue", "red", etc.
  """
  @spec parse(term()) :: t() | nil
  def parse(string) when is_binary(string) do
    string = String.trim(string) |> String.downcase()

    cond do
      String.starts_with?(string, "#") -> parse_hex(string)
      String.starts_with?(string, "rgb") -> parse_rgb_string(string)
      String.starts_with?(string, "hsl") -> parse_hsl_string(string)
      true -> parse_named(string)
    end
  end

  def parse(_), do: nil

  @doc """
  The color `text` spells, as `parse/1` reads it (spec/04 §1.6): the input edge for text a
  program holds. Text `parse/1` does not read raises `ArgumentError` naming it.

      iex> Macaw.Layers.Color.parse!("#3b6fa8")
      %Macaw.Layers.Color{r: 59.0, g: 111.0, b: 168.0, opacity: 1.0}

  """
  @spec parse!(String.t()) :: t()
  def parse!(text) do
    parse(text) ||
      raise ArgumentError,
            "not a color: #{inspect(text)}; a color is hex, rgb(), hsl() or a CSS keyword " <>
              "(spec/04 §1.1)"
  end

  @doc """
  A literal color written in the source, `~RGB"#3b6fa8"` (spec/04 §1.6): the text is read
  by `parse/1` when the code compiles and the color is compiled in, so text it does not
  read is a `CompileError` there, never a fault at run time. Import it with
  `import Macaw.Layers.Color, only: [sigil_RGB: 2]`.

      iex> import Macaw.Layers.Color, only: [sigil_RGB: 2]
      iex> ~RGB"steelblue"
      %Macaw.Layers.Color{r: 70.0, g: 130.0, b: 180.0, opacity: 1.0}

  """
  defmacro sigil_RGB({:<<>>, _meta, [text]}, []) when is_binary(text) do
    case parse(text) do
      %__MODULE__{} = color ->
        Macro.escape(color)

      nil ->
        raise CompileError,
          file: __CALLER__.file,
          line: __CALLER__.line,
          description: "~RGB: not a color: #{inspect(text)}"
    end
  end

  defmacro sigil_RGB(_text, modifiers) do
    raise CompileError,
      file: __CALLER__.file,
      line: __CALLER__.line,
      description: "~RGB takes no modifiers, got: #{inspect(List.to_string(modifiers))}"
  end

  @doc """
  Whether a term is a literal color (spec/04 §1.1): a `%Macaw.Layers.Color{}` of the
  canonical shape every constructor builds, each field a float in its range. A struct
  written by hand with integer fields, or out of range, is not one.

      iex> Macaw.Layers.Color.literal?(Macaw.Layers.Color.rgb(59, 111, 168))
      true
      iex> Macaw.Layers.Color.literal?(%Macaw.Layers.Color{r: 59, g: 111, b: 168, opacity: 1})
      false

  """
  @spec literal?(term()) :: boolean()
  def literal?(%__MODULE__{r: r, g: g, b: b, opacity: opacity} = color)
      when map_size(color) == 5 do
    canonical?(r, 255.0) and canonical?(g, 255.0) and canonical?(b, 255.0) and
      canonical?(opacity, 1.0)
  end

  def literal?(_term), do: false

  # A float in `0..max`, and not the negative zero, which `+ 0.0` makes the zero.
  defp canonical?(v, max), do: is_float(v) and v >= 0.0 and v <= max and v === v + 0.0

  @doc """
  Whether a term is a name a theme may give a color, a ramp, a style or itself
  (spec/04 §1.1, §2.1, §2.2, §6): lower-case letters, digits and `_`, starting with a letter,
  as an atom or a string. It is the grammar every name meets on its way into a stylesheet
  (`--mw-<name>`, `.mw-theme-<name>`), so no name can break out of one.

      iex> Enum.map([:info, "series_3", "Info", "3d", "", nil], &Macaw.Layers.Color.name?/1)
      [true, true, false, false, false, false]

  """
  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name), do: Regex.match?(@name, name)

  def name?(name) when is_atom(name) and name not in [nil, true, false],
    do: name?(Atom.to_string(name))

  def name?(_name), do: false

  @doc "Gets a named color's hex value"
  @spec named(String.t()) :: String.t() | nil
  def named(name) when is_binary(name) do
    Map.get(Names.table(), String.downcase(name))
  end

  @doc "Returns all named color names"
  @spec named_colors() :: [String.t()]
  def named_colors, do: Names.table() |> Map.keys() |> Enum.sort()

  # -- conversions -------------------------------------------------------------------------

  @doc "Converts to RGB tuple {r, g, b}"
  @spec to_rgb(t()) :: {integer(), integer(), integer()}
  def to_rgb(%__MODULE__{r: r, g: g, b: b}) do
    {round(r), round(g), round(b)}
  end

  @doc "Converts to RGBA tuple {r, g, b, a}"
  @spec to_rgba(t()) :: {integer(), integer(), integer(), float()}
  def to_rgba(%__MODULE__{r: r, g: g, b: b, opacity: a}) do
    {round(r), round(g), round(b), a}
  end

  @doc "Converts to HSL map %{h: h, s: s, l: l, opacity: a}"
  @spec to_hsl(t()) :: %{h: float(), s: float(), l: float(), opacity: float()}
  def to_hsl(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    r = r / 255
    g = g / 255
    b = b / 255

    max_c = max(max(r, g), b)
    min_c = min(min(r, g), b)
    l = (max_c + min_c) / 2

    if max_c == min_c do
      %{h: 0.0, s: 0.0, l: l * 100, opacity: opacity}
    else
      d = max_c - min_c

      s =
        if l > 0.5 do
          d / (2 - max_c - min_c)
        else
          d / (max_c + min_c)
        end

      h =
        cond do
          max_c == r -> (g - b) / d + if(g < b, do: 6, else: 0)
          max_c == g -> (b - r) / d + 2
          true -> (r - g) / d + 4
        end

      %{h: h * 60, s: s * 100, l: l * 100, opacity: opacity}
    end
  end

  @doc "Converts to Lab map %{l: l, a: a, b: b, opacity: opacity}"
  @spec to_lab(t()) :: %{l: float(), a: float(), b: float(), opacity: float()}
  def to_lab(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    # RGB -> XYZ
    r = rgb_xyz(r / 255)
    g = rgb_xyz(g / 255)
    b_val = rgb_xyz(b / 255)

    # The D50-adapted matrix, the inverse of `lab/4`'s; a gray is exactly neutral, a = b = 0.
    y = (0.2225045 * r + 0.7168786 * g + 0.0606169 * b_val) / @yn

    {x, z} =
      if r == g and g == b_val,
        do: {y, y},
        else:
          {(0.4360747 * r + 0.3850649 * g + 0.1430804 * b_val) / @xn,
           (0.0139322 * r + 0.0971045 * g + 0.7141733 * b_val) / @zn}

    x = xyz_lab(x)
    y = xyz_lab(y)
    z = xyz_lab(z)

    %{
      l: 116 * y - 16,
      a: 500 * (x - y),
      b: 200 * (y - z),
      opacity: opacity
    }
  end

  @doc "Converts to HCL map %{h: h, c: c, l: l, opacity: opacity}"
  @spec to_hcl(t()) :: %{h: float(), c: float(), l: float(), opacity: float()}
  def to_hcl(%__MODULE__{} = color) do
    %{l: l, a: a, b: b, opacity: opacity} = to_lab(color)
    c = :math.sqrt(a * a + b * b)
    h = :math.atan2(b, a) * 180 / :math.pi()
    h = if h < 0, do: h + 360, else: h

    %{h: h, c: c, l: l, opacity: opacity}
  end

  @doc "Converts to hex string"
  @spec to_hex(t()) :: String.t()
  def to_hex(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    hex = "#" <> hex_byte(round(r)) <> hex_byte(round(g)) <> hex_byte(round(b))

    if opacity < 1 do
      hex <> hex_byte(round(opacity * 255))
    else
      hex
    end
  end

  @doc """
  The color as CSS writes it (spec/04 §1.6), the output edge: `#rrggbb`, or `#rrggbbaa` when
  translucent, where the color is 8-bit exact (`exact?/1`), else `rgb(r g b / a)` with each
  number in its shortest exact form. `parse/1` reads either back to the color.

      iex> Macaw.Layers.Color.to_css(Macaw.Layers.Color.rgb(59, 111, 168))
      "#3b6fa8"
      iex> Macaw.Layers.Color.to_css(Macaw.Layers.Color.rgb(59.5, 111, 168, 0.5))
      "rgb(59.5 111.0 168.0 / 0.5)"

  """
  @spec to_css(t()) :: String.t()
  def to_css(%__MODULE__{r: r, g: g, b: b, opacity: opacity} = color) do
    if exact?(color),
      do: to_hex(color),
      else: "rgb(#{number(r)} #{number(g)} #{number(b)} / #{number(opacity)})"
  end

  @doc """
  Whether the color is 8-bit exact: whole channels, and an opacity that is a whole number of
  255ths, so a hex literal writes it with nothing lost.

      iex> Macaw.Layers.Color.exact?(Macaw.Layers.Color.parse("#3b6fa880"))
      true
      iex> Macaw.Layers.Color.exact?(Macaw.Layers.Color.rgb(59.5, 111, 168))
      false

  """
  @spec exact?(t()) :: boolean()
  def exact?(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    whole?(r) and whole?(g) and whole?(b) and opacity == round(opacity * 255) / 255
  end

  defp whole?(v), do: v == round(v)

  defp number(v), do: :erlang.float_to_binary(v * 1.0, [:short])

  @doc "Converts to CSS string"
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    if opacity == 1.0 do
      "rgb(#{round(r)}, #{round(g)}, #{round(b)})"
    else
      "rgba(#{round(r)}, #{round(g)}, #{round(b)}, #{opacity})"
    end
  end

  # -- manipulation ------------------------------------------------------------------------

  @doc """
  Returns a brighter copy of the color.

  k=1 is one "unit" brighter (default). k=2 is two units, etc.
  """
  @spec brighter(t(), number()) :: t()
  def brighter(%__MODULE__{} = color, k \\ 1) do
    %{l: l, a: a, b: b, opacity: opacity} = to_lab(color)
    lab(l + @kn * k, a, b, opacity)
  end

  @doc """
  Returns a darker copy of the color.

  k=1 is one "unit" darker (default). k=2 is two units, etc.
  """
  @spec darker(t(), number()) :: t()
  def darker(%__MODULE__{} = color, k \\ 1) do
    %{l: l, a: a, b: b, opacity: opacity} = to_lab(color)
    lab(l - @kn * k, a, b, opacity)
  end

  @doc "Returns a copy with the specified opacity"
  @spec with_opacity(t(), number()) :: t()
  def with_opacity(%__MODULE__{} = color, opacity) do
    %{color | opacity: fraction(opacity)}
  end

  @doc """
  On a `%Macaw.Layers.Color{}`, a saturated copy: HSL saturation multiplied by `amount`
  (default `1.2`).

  On any other color value (spec/04 §1.3), the transform `{:saturate, c, t}`: chroma moved
  toward full in OKLCH by `t` in `0..1`, resolved against the theme. A literal keeps the
  first meaning, so the transform of a literal is written as its tuple,
  `{:saturate, literal, t}`.

      iex> Macaw.Layers.Color.color(:red) |> Macaw.Layers.Color.saturate(0.2)
      {:saturate, {:color, :red}, 0.2}
  """
  @spec saturate(t(), number()) :: t()
  @spec saturate(value(), number()) :: value()
  def saturate(color, amount \\ 1.2)

  def saturate(%__MODULE__{} = color, amount) do
    %{h: h, s: s, l: l, opacity: opacity} = to_hsl(color)
    hsl(h, s * amount, l, opacity)
  end

  def saturate(value, t), do: transform(:saturate, value, t)

  @doc "Returns a desaturated copy (in HSL space)"
  @spec desaturate(t(), number()) :: t()
  def desaturate(%__MODULE__{} = color, amount \\ 0.8) do
    saturate(color, amount)
  end

  @doc "Rotates the hue by the specified degrees"
  @spec rotate(t(), number()) :: t()
  def rotate(%__MODULE__{} = color, degrees) do
    %{h: h, s: s, l: l, opacity: opacity} = to_hsl(color)
    hsl(h + degrees, s, l, opacity)
  end

  @doc "Returns a grayscale version of the color"
  @spec grayscale(t()) :: t()
  def grayscale(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    # Use luminance formula
    gray = round(0.299 * r + 0.587 * g + 0.114 * b)
    rgb(gray, gray, gray, opacity)
  end

  @doc "Inverts the color"
  @spec invert(t()) :: t()
  def invert(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    rgb(255 - r, 255 - g, 255 - b, opacity)
  end

  # -- color operations --------------------------------------------------------------------

  @doc "Returns the relative luminance (0-1)"
  @spec luminance(t()) :: float()
  def luminance(%__MODULE__{r: r, g: g, b: b}) do
    r = luminance_channel(r / 255)
    g = luminance_channel(g / 255)
    b = luminance_channel(b / 255)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  @doc "Returns the contrast ratio between two colors (1-21)"
  @spec contrast(t(), t()) :: float()
  def contrast(%__MODULE__{} = c1, %__MODULE__{} = c2) do
    l1 = luminance(c1)
    l2 = luminance(c2)
    {lighter, darker} = if l1 > l2, do: {l1, l2}, else: {l2, l1}
    (lighter + 0.05) / (darker + 0.05)
  end

  @doc "Mixes two colors equally (in RGB space)"
  @spec mix(t(), t()) :: t()
  def mix(c1, c2), do: interpolate_rgb(c1, c2, 0.5)

  # -- interpolation -----------------------------------------------------------------------

  @doc "Interpolates between two colors in RGB space"
  @spec interpolate_rgb(t(), t(), number()) :: t()
  def interpolate_rgb(%__MODULE__{} = c1, %__MODULE__{} = c2, t) do
    rgb(
      c1.r + (c2.r - c1.r) * t,
      c1.g + (c2.g - c1.g) * t,
      c1.b + (c2.b - c1.b) * t,
      c1.opacity + (c2.opacity - c1.opacity) * t
    )
  end

  @doc "Interpolates between two colors in HSL space"
  @spec interpolate_hsl(t(), t(), number()) :: t()
  def interpolate_hsl(%__MODULE__{} = c1, %__MODULE__{} = c2, t) do
    hsl1 = to_hsl(c1)
    hsl2 = to_hsl(c2)

    # Shortest path for hue
    dh = hsl2.h - hsl1.h

    dh =
      cond do
        dh > 180 -> dh - 360
        dh < -180 -> dh + 360
        true -> dh
      end

    h = hsl1.h + dh * t
    s = hsl1.s + (hsl2.s - hsl1.s) * t
    l = hsl1.l + (hsl2.l - hsl1.l) * t
    opacity = hsl1.opacity + (hsl2.opacity - hsl1.opacity) * t

    hsl(h, s, l, opacity)
  end

  @doc "Interpolates between two colors in Lab space"
  @spec interpolate_lab(t(), t(), number()) :: t()
  def interpolate_lab(%__MODULE__{} = c1, %__MODULE__{} = c2, t) do
    lab1 = to_lab(c1)
    lab2 = to_lab(c2)

    l = lab1.l + (lab2.l - lab1.l) * t
    a = lab1.a + (lab2.a - lab1.a) * t
    b = lab1.b + (lab2.b - lab1.b) * t
    opacity = lab1.opacity + (lab2.opacity - lab1.opacity) * t

    lab(l, a, b, opacity)
  end

  @doc "Interpolates between two colors in HCL space (perceptually uniform)"
  @spec interpolate_hcl(t(), t(), number()) :: t()
  def interpolate_hcl(%__MODULE__{} = c1, %__MODULE__{} = c2, t) do
    hcl1 = to_hcl(c1)
    hcl2 = to_hcl(c2)

    # Shortest path for hue
    dh = hcl2.h - hcl1.h

    dh =
      cond do
        dh > 180 -> dh - 360
        dh < -180 -> dh + 360
        true -> dh
      end

    h = hcl1.h + dh * t
    c = hcl1.c + (hcl2.c - hcl1.c) * t
    l = hcl1.l + (hcl2.l - hcl1.l) * t
    opacity = hcl1.opacity + (hcl2.opacity - hcl1.opacity) * t

    hcl(h, c, l, opacity)
  end

  # -- oklab and oklch ---------------------------------------------------------------------

  @doc """
  The color in OKLab (spec/04 §1.2): `%{l, a, b, opacity}`, `l` in `0..1`.

      iex> %{l: l} = Macaw.Layers.Color.to_oklab(Macaw.Layers.Color.parse("#ffffff"))
      iex> Float.round(l, 4)
      1.0

  """
  @spec to_oklab(t()) :: %{l: float(), a: float(), b: float(), opacity: number()}
  def to_oklab(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    {l, a, b} = Ok.from_srgb({r / 255, g / 255, b / 255})
    %{l: l, a: a, b: b, opacity: opacity}
  end

  @doc "The color in OKLCH (spec/04 §1.2): `%{l, c, h, opacity}`, `h` in degrees `[0, 360)`."
  @spec to_oklch(t()) :: %{l: float(), c: float(), h: float(), opacity: number()}
  def to_oklch(%__MODULE__{opacity: opacity} = color) do
    %{l: l, a: a, b: b} = to_oklab(color)
    {l, c, h} = Ok.to_lch({l, a, b})
    %{l: l, c: c, h: h, opacity: opacity}
  end

  @doc """
  A color from OKLab, brought into sRGB by CSS Color 4's gamut mapping (spec/04 §1.2).
  Channels are left unrounded.
  """
  @spec oklab(number(), number(), number(), number()) :: t()
  def oklab(l, a, b, opacity \\ 1.0) do
    {r, g, b} = Ok.map_to_srgb({l, a, b})
    rgb(r * 255, g * 255, b * 255, opacity)
  end

  @doc """
  ΔEOK, the distance between two colors in OKLab, their opacities aside.

      iex> Macaw.Layers.Color.delta_eok(Macaw.Layers.Color.parse("#fff"), Macaw.Layers.Color.parse("#000"))
      ...> |> Float.round(6)
      1.0
  """
  @spec delta_eok(t(), t()) :: float()
  def delta_eok(%__MODULE__{} = c1, %__MODULE__{} = c2) do
    %{l: l1, a: a1, b: b1} = to_oklab(c1)
    %{l: l2, a: a2, b: b2} = to_oklab(c2)
    :math.sqrt((l1 - l2) ** 2 + (a1 - a2) ** 2 + (b1 - b2) ** 2)
  end

  @doc "A color from OKLCH (`h` in degrees), gamut-mapped as `oklab/4` is."
  @spec oklch(number(), number(), number(), number()) :: t()
  def oklch(l, c, h, opacity \\ 1.0) do
    {l, a, b} = Ok.from_lch({l, c, h})
    oklab(l, a, b, opacity)
  end

  # -- typed colors (spec/04 §1.3) ---------------------------------------------------

  @typedoc """
  A color as a design names it (spec/04 §1.3): a name of the theme's color table, a series
  or a ramp position, a literal color (`t:t/0`), or a transform of colors. A string is never
  a color.
  """
  @type value ::
          t()
          | {:color, atom() | String.t()}
          | {:series, pos_integer()}
          | {:ramp, atom(), number()}
          | {:intensity | :alpha | :lighten | :darken | :saturate | :shade, value(), number()}
          | {:blend, [value(), ...]}
          | {:contrast, value() | :under}

  @doc """
  The color `name` of the theme's color table (spec/04 §1.3, §2.2): the library's names are
  atoms, and a color a theme declares may be named by its string.

      iex> Macaw.Layers.Color.color(:red)
      {:color, :red}

  """
  @spec color(atom() | String.t()) :: value()
  def color(name) do
    if Typed.name?(name),
      do: {:color, name},
      else: raise(ArgumentError, "a color name is an atom or a string, got: #{inspect(name)}")
  end

  @doc """
  The color at `t` in `0..1` along the theme's ramp `name` (spec/04 §2.3).

      iex> Macaw.Layers.Color.ramp(:thermal, 0.7)
      {:ramp, :thermal, 0.7}

  """
  @spec ramp(atom(), number()) :: value()
  def ramp(name, t) do
    cond do
      not Typed.name?(name) ->
        raise ArgumentError, "a ramp name is an atom, got: #{inspect(name)}"

      not Typed.unit?(t) ->
        raise ArgumentError, "ramp #{inspect(name)}: #{unit(t)}"

      true ->
        {:ramp, name, t}
    end
  end

  @doc """
  How much of the color `c` is present, `t` in `0..1`; the rest is transparent. On its own
  it is `c` at `t` of its alpha; in `blend/1` it is the color's weight (spec/04 §1.3).

      iex> Macaw.Layers.Color.color(:blue) |> Macaw.Layers.Color.intensity(0.65)
      {:intensity, {:color, :blue}, 0.65}

  """
  @spec intensity(value(), number()) :: value()
  def intensity(c, t), do: transform(:intensity, c, t)

  @doc """
  The colors mixed in OKLab, each weighted by its `intensity/2` (1 without one), as CSS's
  `color-mix` mixes them: weights summing below 1 leave the remainder transparent, and
  above 1 are scaled to sum to 1 (spec/04 §1.3).

      iex> import Macaw.Layers.Color, only: [color: 1, intensity: 2, blend: 1, alpha: 2]
      iex> [color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)] |> blend() |> alpha(0.65)
      {:alpha, {:blend, [{:intensity, {:color, :blue}, 0.65}, {:intensity, {:color, :red}, 0.3}]}, 0.65}

  """
  @spec blend([value(), ...]) :: value()
  def blend([_ | _] = colors) do
    case Enum.reject(colors, &Typed.value?/1) do
      [] -> {:blend, colors}
      [bad | _] -> raise ArgumentError, operand(:blend, bad)
    end
  end

  def blend(other) do
    raise ArgumentError, "blend takes a non-empty list of colors, got: #{inspect(other)}"
  end

  @doc """
  The color `c` at opacity `a` in `0..1`, whatever its opacity was (spec/04 §1.3).

      iex> Macaw.Layers.Color.color(:red) |> Macaw.Layers.Color.alpha(0.5)
      {:alpha, {:color, :red}, 0.5}

  """
  @spec alpha(value(), number()) :: value()
  def alpha(c, a), do: transform(:alpha, c, a)

  @doc """
  The color `c` moved toward white by `t` in `0..1`, in OKLCH lightness (spec/04 §1.3).

      iex> Macaw.Layers.Color.color(:red) |> Macaw.Layers.Color.lighten(0.3)
      {:lighten, {:color, :red}, 0.3}

  """
  @spec lighten(value(), number()) :: value()
  def lighten(c, t), do: transform(:lighten, c, t)

  @doc """
  The color `c` moved toward black by `t` in `0..1`, in OKLCH lightness (spec/04 §1.3).

      iex> Macaw.Layers.Color.color(:red) |> Macaw.Layers.Color.darken(0.3)
      {:darken, {:color, :red}, 0.3}

  """
  @spec darken(value(), number()) :: value()
  def darken(c, t), do: transform(:darken, c, t)

  @doc """
  The readable ink over whatever the text is drawn on (spec/04 §3.2): a mark's inline label
  inks against its element's fill, any other text against the theme's background.

      iex> Macaw.Layers.Color.contrast()
      {:contrast, :under}

  """
  @spec contrast() :: value()
  def contrast, do: {:contrast, :under}

  @doc """
  The readable ink over `c`: the theme's text or background, else black or white,
  whichever contrasts more (spec/04 §1.4, §3.2).

      iex> Macaw.Layers.Color.color(:bad) |> Macaw.Layers.Color.contrast()
      {:contrast, {:color, :bad}}

  """
  @spec contrast(value()) :: value()
  def contrast(c) do
    if Typed.value?(c), do: {:contrast, c}, else: raise(ArgumentError, operand(:contrast, c))
  end

  @doc """
  The step `n` of `c`'s scale, `n` in `0..1000` as designers number them (spec/04 §1.3):
  500 is `c`, 0 near white and 1000 near black, on one OKLCH curve that keeps the hue and
  eases the chroma toward the ends. A step the theme pins of a name is the pinned color.

      iex> Macaw.Layers.Color.color(:red) |> Macaw.Layers.Color.shade(100)
      {:shade, {:color, :red}, 100}

  """
  @spec shade(value(), number()) :: value()
  def shade(c, n) do
    cond do
      not Typed.value?(c) ->
        raise ArgumentError, operand(:shade, c)

      not (is_number(n) and n >= 0 and n <= 1000) ->
        raise ArgumentError, "shade: a step in 0..1000, got: #{inspect(n)}"

      true ->
        {:shade, c, n}
    end
  end

  @doc """
  Whether a term is a color value (spec/04 §1.3), every operand of a transform included. A
  literal is the canonical `%Macaw.Layers.Color{}` (`literal?/1`); a string is never a color.

      iex> Macaw.Layers.Color.value?({:alpha, {:color, :red}, 0.5})
      true
      iex> Macaw.Layers.Color.value?({:alpha, Macaw.Layers.Color.parse!("#3b6fa8"), 0.5})
      true
      iex> Enum.map([:red, "#3b6fa8", {:alpha, "#3b6fa8", 0.5}], &Macaw.Layers.Color.value?/1)
      [false, false, false]

  """
  @spec value?(term()) :: boolean()
  def value?(term), do: Typed.value?(term)

  @doc """
  A color value resolved against a theme in `mode` (spec/04 §1.4, §3.2): a name, a series
  or a ramp position exactly as `Macaw.Layers.Theme.resolve/3` resolves the slot, a literal as
  itself, and a transform as the literal it computes to, quantized to 8 bits. `:literal`
  answers a literal color, `:css` CSS text (`to_css/1` for a literal).

      iex> theme = Macaw.Layers.Theme.default()
      iex> Macaw.Layers.Color.resolve(Macaw.Layers.Color.color(:axis), theme, :css)
      "var(--mw-axis, #666666)"
      iex> red = Macaw.Layers.Color.parse!("#ff0000")
      iex> Macaw.Layers.Color.resolve({:intensity, red, 0.5}, theme, :literal)
      %Macaw.Layers.Color{r: 255.0, g: 0.0, b: 0.0, opacity: 128 / 255}
      iex> Macaw.Layers.Color.resolve({:intensity, red, 0.5}, theme, :literal) |> Macaw.Layers.Color.to_css()
      "#ff000080"

  """
  @spec resolve(value() | atom(), Macaw.Layers.Theme.t(), Macaw.Layers.Theme.mode()) ::
          t() | String.t()
  def resolve(value, theme, mode), do: Typed.resolve(value, theme, mode)

  defp transform(op, c, t) do
    cond do
      not Typed.value?(c) -> raise ArgumentError, operand(op, c)
      not Typed.unit?(t) -> raise ArgumentError, "#{op}: #{unit(t)}"
      true -> {op, c, t}
    end
  end

  defp operand(op, c) when is_atom(c) and c not in [nil, true, false] do
    "#{op}: a bare atom is a style, not a color; write color(#{inspect(c)})"
  end

  defp operand(op, c) when is_binary(c), do: "#{op}: #{Typed.text_hint(c)}"

  defp operand(op, c) do
    "#{op}: not a color value: #{inspect(c)}; a color is color(name), ramp(name, t), a " <>
      "literal %Macaw.Layers.Color{} or a transform of them"
  end

  defp unit(t), do: "a number in 0..1, got: #{inspect(t)}"

  # -- helpers ----------------------------------------------------------------------------

  # A hex color of 3, 4, 6 or 8 digits; any other length, or a digit that is not hex, is no
  # color, answered rather than raised, since the text is untrusted.
  defp parse_hex("#" <> hex) do
    case if(String.match?(hex, ~r/\A[0-9a-f]*\z/), do: byte_size(hex), else: 0) do
      3 ->
        <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> = hex

        rgb(
          String.to_integer(r <> r, 16),
          String.to_integer(g <> g, 16),
          String.to_integer(b <> b, 16)
        )

      4 ->
        <<r::binary-size(1), g::binary-size(1), b::binary-size(1), a::binary-size(1)>> = hex

        rgb(
          String.to_integer(r <> r, 16),
          String.to_integer(g <> g, 16),
          String.to_integer(b <> b, 16),
          String.to_integer(a <> a, 16) / 255
        )

      6 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex

        rgb(
          String.to_integer(r, 16),
          String.to_integer(g, 16),
          String.to_integer(b, 16)
        )

      8 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2), a::binary-size(2)>> = hex

        rgb(
          String.to_integer(r, 16),
          String.to_integer(g, 16),
          String.to_integer(b, 16),
          String.to_integer(a, 16) / 255
        )

      _ ->
        nil
    end
  end

  defp parse_rgb_string(string) do
    pattern = ~r/\Argba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)\z/

    case Regex.run(pattern, string) do
      [_, r, g, b] ->
        rgb(String.to_integer(r), String.to_integer(g), String.to_integer(b))

      [_, r, g, b, a] ->
        rgb(String.to_integer(r), String.to_integer(g), String.to_integer(b), parse_float(a))

      _ ->
        parse_rgb_spaced(string)
    end
  end

  # CSS Color 4's space-separated `rgb(r g b)` and `rgb(r g b / a)`, decimal numbers with an
  # optional exponent: what `to_css/1` writes of a color that is not 8-bit exact.
  @css_number "(\\d+(?:\\.\\d+)?(?:e[+-]?\\d+)?)"
  @rgb_spaced Regex.compile!(
                "\\Argba?\\s*\\(\\s*#{@css_number}\\s+#{@css_number}\\s+#{@css_number}" <>
                  "\\s*(?:/\\s*#{@css_number}\\s*)?\\)\\z"
              )

  defp parse_rgb_spaced(string) do
    case Regex.run(@rgb_spaced, string) do
      [_, r, g, b] -> rgb(parse_float(r), parse_float(g), parse_float(b))
      [_, r, g, b, a] -> rgb(parse_float(r), parse_float(g), parse_float(b), parse_float(a))
      nil -> nil
    end
  end

  defp parse_hsl_string(string) do
    pattern =
      ~r/\Ahsla?\s*\(\s*([\d.]+)\s*,\s*([\d.]+)%?\s*,\s*([\d.]+)%?\s*(?:,\s*([\d.]+)\s*)?\)\z/

    case Regex.run(pattern, string) do
      [_, h, s, l] ->
        hsl(parse_float(h), parse_float(s), parse_float(l))

      [_, h, s, l, a] ->
        hsl(parse_float(h), parse_float(s), parse_float(l), parse_float(a))

      _ ->
        nil
    end
  end

  defp parse_named(name) do
    case Map.get(Names.table(), name) do
      nil -> nil
      hex -> parse_hex(hex)
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp hsl_to_rgb(h, s, l) do
    if s == 0 do
      {l, l, l}
    else
      q = if l < 0.5, do: l * (1 + s), else: l + s - l * s
      p = 2 * l - q

      r = hue_to_rgb(p, q, h / 360 + 1 / 3)
      g = hue_to_rgb(p, q, h / 360)
      b = hue_to_rgb(p, q, h / 360 - 1 / 3)

      {r, g, b}
    end
  end

  defp hue_to_rgb(p, q, t) do
    t = if t < 0, do: t + 1, else: if(t > 1, do: t - 1, else: t)

    cond do
      t < 1 / 6 -> p + (q - p) * 6 * t
      t < 1 / 2 -> q
      t < 2 / 3 -> p + (q - p) * (2 / 3 - t) * 6
      true -> p
    end
  end

  defp hex_byte(n),
    do: n |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()

  defp clamp(value, min_val, max_val), do: value |> max(min_val) |> min(max_val)

  # A field of the canonical struct: a float, clamped, and `+ 0.0` so a negative zero is
  # the zero every other constructor gives (the digest tells the two apart).
  defp channel(v) when is_number(v), do: clamp(v * 1.0, 0.0, 255.0) + 0.0
  defp fraction(v) when is_number(v), do: clamp(v * 1.0, 0.0, 1.0) + 0.0

  # Lab <-> XYZ conversion helpers
  defp lab_xyz(t) when t > @t1, do: t * t * t
  defp lab_xyz(t), do: @t2 * (t - @t0)

  defp xyz_lab(t) when t > @t3, do: :math.pow(t, 1 / 3)
  defp xyz_lab(t), do: t / @t2 + @t0

  # RGB <-> XYZ conversion helpers
  defp rgb_xyz(r) when r <= 0.04045, do: r / 12.92
  defp rgb_xyz(r), do: :math.pow((r + 0.055) / 1.055, 2.4)

  defp xyz_rgb(x) do
    x = if x <= 0.0031308, do: 12.92 * x, else: 1.055 * :math.pow(x, 1 / 2.4) - 0.055
    x * 255
  end

  defp luminance_channel(c) when c <= 0.03928, do: c / 12.92
  defp luminance_channel(c), do: :math.pow((c + 0.055) / 1.055, 2.4)
end
