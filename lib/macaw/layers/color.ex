defmodule Macaw.Layers.Color do
  @moduledoc """
  Colors (spec/04 §1): parsing, construction in RGB, HSL, Lab, HCL, OKLab and OKLCH,
  conversion, manipulation and interpolation.

      color = Macaw.Layers.Color.parse("steelblue")
      color |> Macaw.Layers.Color.darker() |> Macaw.Layers.Color.to_hex()
      #=> "#044279"

  `parse/1` reads untrusted text and answers `nil` for anything it does not read; it never
  raises. Lab is CIE L\\*a\\*b\\* against D50 with d3-color's constants, so `lab/4` of
  `to_lab/1` is the color again; OKLab is Ottosson's, and a color built from OKLab or
  OKLCH is brought into sRGB by CSS Color 4's gamut mapping (`Macaw.Layers.Color.Ok`).
  `Macaw.Layers.Color.Vision` simulates the dichromacies.

  Ported from visualize's `Visualize.Color` and `Visualize.Color.OK`.
  """

  alias Macaw.Layers.Color.{Names, Ok}

  defstruct r: 0, g: 0, b: 0, opacity: 1.0

  @type t :: %__MODULE__{
          r: number(),
          g: number(),
          b: number(),
          opacity: number()
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

  # -- constructors ------------------------------------------------------------------------

  @doc "Creates a color from RGB values (0-255)"
  @spec rgb(number(), number(), number(), number()) :: t()
  def rgb(r, g, b, opacity \\ 1.0) do
    %__MODULE__{
      r: clamp(r, 0, 255),
      g: clamp(g, 0, 255),
      b: clamp(b, 0, 255),
      opacity: clamp(opacity, 0, 1)
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

    %__MODULE__{
      r: round(r * 255),
      g: round(g * 255),
      b: round(b * 255),
      opacity: clamp(opacity, 0, 1)
    }
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

    %__MODULE__{
      r: round(clamp(r, 0, 255)),
      g: round(clamp(g, 0, 255)),
      b: round(clamp(b_val, 0, 255)),
      opacity: clamp(opacity, 0, 1)
    }
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
    %{color | opacity: clamp(opacity, 0, 1)}
  end

  @doc """
  A saturated copy: HSL saturation multiplied by `amount` (default `1.2`).
  """
  @spec saturate(t(), number()) :: t()
  def saturate(%__MODULE__{} = color, amount \\ 1.2) do
    %{h: h, s: s, l: l, opacity: opacity} = to_hsl(color)
    hsl(h, s * amount, l, opacity)
  end

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
    %__MODULE__{r: gray, g: gray, b: gray, opacity: opacity}
  end

  @doc "Inverts the color"
  @spec invert(t()) :: t()
  def invert(%__MODULE__{r: r, g: g, b: b, opacity: opacity}) do
    %__MODULE__{r: 255 - r, g: 255 - g, b: 255 - b, opacity: opacity}
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
    %__MODULE__{
      r: c1.r + (c2.r - c1.r) * t,
      g: c1.g + (c2.g - c1.g) * t,
      b: c1.b + (c2.b - c1.b) * t,
      opacity: c1.opacity + (c2.opacity - c1.opacity) * t
    }
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
        nil
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
