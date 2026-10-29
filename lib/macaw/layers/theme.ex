defmodule Macaw.Layers.Theme do
  @moduledoc """
  The colors, fonts and sizes a page draws with (spec/04 §2, §3).

  A theme is a struct of named **slots**: `"series_1"` … `"series_n"` for the categorical
  colors; the furniture `"axis"`, `"grid"`, `"text"`, `"background"` and `"surface"`; the
  five **roles** `"good"`, `"warning"`, `"bad"`, `"info"` and `"neutral"`; and
  `"font_family"`, `"font_size"`, `"label_size"` and `"title_size"`. Its colors are one
  **color table** (§2.2):
  the theme's own `colors` over the default theme's, its extensions' and the CSS named
  colors, with the furniture and the series as names too, so `Macaw.Layers.Color.color(:red)`
  is the theme's red. Everything reads a theme through `resolve/3`, in the mode its output
  needs:

    * `:literal` - the stored value, which a canvas needs: a color a literal
      `%Macaw.Layers.Color{}`;
    * `:css` - a custom-property reference with the literal as its fallback,
      `var(--mw-axis, #666666)`, so a stylesheet can override it from any ancestor.

  Its colors are terms (§2.1): a literal is `%Macaw.Layers.Color{}`, read from text at the
  edge (`Macaw.Layers.Color.parse!/1`, `~RGB"#3b6fa8"`), and a string is never a color.

  **Its names are strings** (§2.1), the library's, its extensions' and a host's alike: its
  own `name` and its `dark` and `light`, the slots, the keys of `ramps`, `colors` and `styles`, and the name in every typed color
  (`{:color, "good"}`, `{:ramp, "status", 0.5}`). A name given as an atom is read as its
  string, once, when the theme is built (`new/1`, `merge/2`, a document read), so `:info`
  and `"info"` are one name; every function that takes a name takes either spelling. Its
  **words** — a style's keys and atom values, `defaults` — are kept as given.

  ## Meaning: ramps, roles and cues

  A series color promises *distinct*, never a meaning. A theme also carries four **ramps**
  whose meaning the library fixes (§2.3): `"status"`, `"thermal"`, `"diverging"` and
  `"sequential"`, each a list of anchors interpolated in CIE Lab, and every role and ramp is
  held to its contract when a theme is built by `new/1` or `merge/2`.

  ## Whole styles: the style palette

  `styles` carries the design over to whole styles (§2.4): style series, the roles as whole
  looks, view states, furniture styles and modifiers, the names the library's and its
  registered extensions' (§3.4). `style/2` reads one, the default theme's where the theme
  lacks it.

  ## Examples

      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.default(), :axis, :css)
      "var(--mw-axis, #666666)"
      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.dark(), {:series, 11}, :literal)
      %Macaw.Layers.Color{r: 127.0, g: 179.0, b: 230.0, opacity: 1.0}
      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.default(), :warning, :css)
      "var(--mw-warning, #bd7407)"
      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.default(), {:ramp, :status, 0.5}, :css)
      "var(--mw-warning, #bd7407)"

  Ported from visualize's `Visualize.Theme`.
  """

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.Color
  alias Macaw.Layers.Color.Typed
  alias Macaw.Layers.Theme.{Contract, Contrast, Extension, Names, Palette, Roles, Slots, Table}

  # Every color of the built-ins a literal term, read from its text when this compiles.
  @light_series Enum.map(
                  ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480),
                  &Color.parse!/1
                )
  @dark_series Enum.map(
                 ~w(#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6),
                 &Color.parse!/1
               )

  # The ramps of §2.5, chosen in CIE LCh to hold the contracts of §2.3 with room.
  # Every name a theme holds is a string (§2.1), the library's own included.
  @light_ramps %{
    # The status ramp is defined from the theme's green, amber and red.
    "status" => [{:color, "green"}, {:color, "amber"}, {:color, "red"}],
    "thermal" => [~RGB"#0e68ad", ~RGB"#e8e8e8", ~RGB"#c02e31"],
    "diverging" => [~RGB"#b35806", ~RGB"#ededed", ~RGB"#62448e"],
    "sequential" => [~RGB"#e9f2fc", ~RGB"#5e95d3", ~RGB"#004580"]
  }
  @dark_ramps %{
    "status" => [{:color, "green"}, {:color, "amber"}, {:color, "red"}],
    "thermal" => [~RGB"#7fb3e6", ~RGB"#3a3f48", ~RGB"#f47c7c"],
    "diverging" => [~RGB"#f7a35c", ~RGB"#3a3f48", ~RGB"#c1acee"],
    "sequential" => [~RGB"#273b4f", ~RGB"#457cb1", ~RGB"#aad1f9"]
  }
  # Blue → orange → red: the status order survives the commonest color-vision deficiencies.
  @safe_status [~RGB"#5996d6", ~RGB"#cd6012", ~RGB"#b92931"]

  # The theme's own part of its color table (§2.2): its status hues, the hues of `:info`
  # and `:neutral`, and the five roles by use, the status three as their positions on the
  # status ramp, so a role and its position never disagree.
  @by_use %{
    "good" => {:ramp, "status", 0},
    "warning" => {:ramp, "status", 0.5},
    "bad" => {:ramp, "status", 1}
  }
  @light_colors Map.merge(@by_use, %{
                  "red" => ~RGB"#c23238",
                  "amber" => ~RGB"#bd7407",
                  "green" => ~RGB"#4ca34b",
                  "blue" => ~RGB"#3b6fa8",
                  "gray" => ~RGB"#6f7480",
                  "info" => ~RGB"#3b6fa8",
                  "neutral" => ~RGB"#6f7480"
                })
  @dark_colors Map.merge(@by_use, %{
                 "red" => ~RGB"#ff8f8a",
                 "amber" => ~RGB"#db8e1c",
                 "green" => ~RGB"#4f924c",
                 "blue" => ~RGB"#7fb3e6",
                 "gray" => ~RGB"#b7bcc6",
                 "info" => ~RGB"#7fb3e6",
                 "neutral" => ~RGB"#b7bcc6"
               })
  # The CSS named colors, the table's base (§1.1, §2.2).
  @css_names Color.named_colors()

  defstruct name: "default",
            series: @light_series,
            axis: ~RGB"#666666",
            grid: ~RGB"#e0e0e0",
            text: ~RGB"#333333",
            background: ~RGB"#ffffff",
            surface: ~RGB"#eef2f6",
            ramps: @light_ramps,
            colors: @light_colors,
            styles: Palette.builtin(),
            defaults: %{},
            font_family: "sans-serif",
            font_size: 10,
            label_size: 12,
            title_size: 16,
            dark: nil,
            light: nil,
            extensions: []

  @typedoc """
  One of the four ramps whose meaning the library fixes (§2.3): `"status"`, `"thermal"`,
  `"diverging"` or `"sequential"`, an atom given read as its string.
  """
  @type ramp_name :: String.t() | atom()

  @typedoc "A slot name, or `{:series, i}` for the i-th series color, cycling."
  @type slot :: String.t() | atom() | {:series, pos_integer()}

  @typedoc "A position along a ramp: `t` in `0..1`, clamped."
  @type ramp_position :: {:ramp, ramp_name(), number()}

  @typedoc "A name of the style palette, or `{:style, i}` for the i-th style series entry."
  @type style_name :: String.t() | atom() | {:style, pos_integer()}

  @typedoc "How a slot renders: a CSS reference with its fallback, or the stored value."
  @type mode :: :css | :literal

  @type t :: %__MODULE__{
          name: String.t(),
          series: [Color.t(), ...],
          axis: Color.t(),
          grid: Color.t(),
          text: Color.t(),
          background: Color.t(),
          surface: Color.t(),
          ramps: %{optional(String.t()) => list()},
          colors: %{optional(String.t()) => term()},
          styles: %{optional(String.t()) => map() | list() | String.t()},
          defaults: map(),
          font_family: String.t(),
          font_size: number(),
          label_size: number(),
          title_size: number(),
          dark: String.t() | nil,
          light: String.t() | nil,
          extensions: [module()]
        }

  # The slots are names, strings (§2.1); each fixed slot reads the field it names.
  @furniture [:axis, :grid, :text, :background, :surface]
  @color_slots Enum.map(@furniture, &Atom.to_string/1)
  # Where the status roles stand on the status ramp, by default (§2.3).
  @status_roles [{"good", 0}, {"warning", 0.5}, {"bad", 1}]
  @role_slots ~w(good warning bad info neutral)
  # The font slots' atoms are also words: a style's font part names them (§2.4).
  @size_slots [:font_size, :label_size, :title_size]
  @font_slots [:font_family | @size_slots]
  @fields Map.new(@furniture ++ @font_slots, &{Atom.to_string(&1), &1})
  @fixed_slots @color_slots ++ @role_slots ++ Enum.map(@font_slots, &Atom.to_string/1)
  @builtin ~w(default dark color_safe print)
  # Every color name the library itself gives (§2.2), each a string as a host's is.
  @library_color_names Enum.uniq(
                         @fixed_slots ++
                           Map.keys(@light_colors) ++ Map.keys(@dark_colors) ++ @css_names
                       )

  @doc false
  @spec library_color_names() :: [String.t(), ...]
  def library_color_names, do: @library_color_names

  @doc false
  # The default theme's own colors, the table's second part (§2.2).
  @spec default_colors() :: map()
  def default_colors, do: @light_colors

  @doc false
  @spec default_ramps() :: map()
  def default_ramps, do: @light_ramps

  @doc false
  @spec fixed_slots() :: [String.t(), ...]
  def fixed_slots, do: @fixed_slots

  @doc false
  # The font sizes' slots as the words a style's font part names them by.
  @spec size_slots() :: [atom(), ...]
  def size_slots, do: @size_slots

  @doc false
  # The field a fixed slot other than a role reads, by the slot's name, or `nil`.
  @spec field(String.t()) :: atom() | nil
  def field(name), do: Map.get(@fields, name)

  # -- the built-in themes (§2.5) ----------------------------------------------------------

  @doc "The light theme: dark text and axes on white."
  @spec default() :: t()
  def default, do: %__MODULE__{dark: "dark"}

  @doc "The dark theme: light text and axes on `#1b1e24`."
  @spec dark() :: t()
  def dark do
    %__MODULE__{
      name: "dark",
      series: @dark_series,
      axis: ~RGB"#a0a4ab",
      grid: ~RGB"#33373f",
      text: ~RGB"#e6e6e6",
      background: ~RGB"#1b1e24",
      surface: ~RGB"#23272f",
      ramps: @dark_ramps,
      colors: @dark_colors,
      light: "default"
    }
  end

  @doc """
  The color-vision-safe theme: `default/0` with its `status` ramp blue → orange → red, which
  survives the commonest color-vision deficiencies, in place of green → amber → red.
  """
  @spec color_safe() :: t()
  def color_safe,
    do: %__MODULE__{name: "color_safe", ramps: %{@light_ramps | "status" => @safe_status}}

  @doc """
  The print theme: paper. A white background and surface, near-black text and axes, a grid
  dark enough to survive a photocopy, the color-safe `status` ramp, and role styles whose
  fills are hatches of the role's color, so a grayscale copy keeps each role apart.
  """
  @spec print() :: t()
  def print do
    %__MODULE__{
      name: "print",
      axis: ~RGB"#333333",
      grid: ~RGB"#c8c8c8",
      text: ~RGB"#111111",
      background: ~RGB"#ffffff",
      surface: ~RGB"#ffffff",
      ramps: %{@light_ramps | "status" => @safe_status},
      styles: Palette.print()
    }
  end

  @doc """
  The built-in theme of a name, `"default"`, `"dark"`, `"color_safe"` or `"print"`, an atom
  read as its string, or `nil`.

      iex> Macaw.Layers.Theme.builtin(:color_safe).name
      "color_safe"
      iex> Macaw.Layers.Theme.builtin(:house)
      nil
  """
  @spec builtin(atom() | String.t()) :: t() | nil
  def builtin(name) do
    case Names.name(name) do
      "default" -> default()
      "dark" -> dark()
      "color_safe" -> color_safe()
      "print" -> print()
      _other -> nil
    end
  end

  @doc false
  @spec builtins() :: [String.t(), ...]
  def builtins, do: @builtin

  # -- ramps, roles and cues (§2.3) ------------------------------------------------------

  @doc """
  The four ramps whose meaning the library fixes, by name.

      iex> Macaw.Layers.Theme.ramp_names()
      ["status", "thermal", "diverging", "sequential"]
  """
  @spec ramp_names() :: [String.t(), ...]
  def ramp_names, do: Contract.ramps()

  @doc """
  The five roles: the status ramp's three fixed points, then `"info"` and `"neutral"`.
  """
  @spec role_names() :: [String.t(), ...]
  def role_names, do: @role_slots

  # Each role's cue besides its hue: the library's, not a theme's, as the hue order is.
  @cues %{
    "good" => %{glyph: :circle, dash: nil},
    "warning" => %{glyph: :triangle, dash: "6 3"},
    "bad" => %{glyph: :cross, dash: "2 3"},
    "info" => %{glyph: :square, dash: "8 3 2 3"},
    "neutral" => %{glyph: :diamond, dash: "1 4"}
  }

  @doc """
  A role's cue besides its hue: its glyph and its dash (`nil` for solid), so a status reads
  without its hue. The role by its name, an atom read as its string. Raises
  `ArgumentError` for anything but a role.

      iex> Macaw.Layers.Theme.cue(:warning)
      %{glyph: :triangle, dash: "6 3"}
  """
  @spec cue(String.t() | atom()) :: %{glyph: atom(), dash: String.t() | nil}
  def cue(role) do
    case Map.fetch(@cues, Names.name(role)) do
      {:ok, cue} ->
        cue

      :error ->
        raise ArgumentError,
              "a cue is a role's, one of #{inspect(@role_slots)}; got: #{inspect(role)}"
    end
  end

  @doc """
  The color at `t` along the theme's ramp `name`, as a literal color: the anchors spread
  evenly over `0..1` and interpolated in CIE Lab, a position on an anchor the anchor's
  literal, `t` clamped. A theme that lacks the ramp takes the default theme's, never a series
  color.

      iex> Macaw.Layers.Theme.ramp(Macaw.Layers.Theme.default(), :thermal, 0.25)
      %Macaw.Layers.Color{r: 141.0, g: 165.0, b: 203.0, opacity: 1.0}
  """
  @spec ramp(t(), ramp_name(), number()) :: Color.t()
  def ramp(%__MODULE__{} = theme, name, t) when is_number(t) do
    name = Names.name(name)
    anchors = Table.anchors(theme, name)
    n = length(anchors) - 1
    position = (t |> max(0) |> min(1)) * n
    i = min(trunc(position), n - 1)
    u = position - i

    if u == 0 do
      anchor!(name, Enum.at(anchors, i))
    else
      Color.interpolate_lab(
        anchor!(name, Enum.at(anchors, i)),
        anchor!(name, Enum.at(anchors, i + 1)),
        u
      )
    end
  end

  def ramp(%__MODULE__{}, name, t),
    do:
      raise(
        ArgumentError,
        "ramp #{inspect(name)}: a position is a number in 0..1, got #{inspect(t)}"
      )

  defp anchor!(name, anchor) do
    if Color.literal?(anchor),
      do: anchor,
      else: raise(ArgumentError, "ramp #{inspect(name)}: anchor #{not_color(anchor)}")
  end

  defp not_color(text) when is_binary(text), do: Typed.text_hint(text)
  defp not_color(other), do: "#{inspect(other)} is not a color"

  # -- the style palette (§2.4) ------------------------------------------------------------

  @doc """
  The palette entry `name` as one style node in its parts: the theme's own, the default
  theme's entry whole where the theme lacks it, or an extension's default. `{:style, i}`
  cycles over the style series; in a role's entry `:cue` becomes the role's dash and glyph,
  a solid dash leaving the key out. Any other name raises `ArgumentError`.

      iex> Macaw.Layers.Theme.style(Macaw.Layers.Theme.default(), :warning)
      %{fill: %{type: :solid, color: {:color, "warning"}}, stroke: %{type: :solid, color: {:color, "warning"}, dash: "6 3"}, marker: %{shape: :triangle}}
      iex> Macaw.Layers.Theme.style(Macaw.Layers.Theme.default(), :muted)
      %{opacity: 0.25}
  """
  @spec style(t(), style_name()) :: map()
  def style(%__MODULE__{} = theme, {:style, i}) when is_integer(i) and i >= 1 do
    series = theme |> own_styles() |> Palette.series()
    style(theme, Enum.at(series, rem(i - 1, length(series))))
  end

  def style(%__MODULE__{} = theme, name) when is_atom(name) and name not in [nil, true, false],
    do: style(theme, Names.name(name))

  def style(%__MODULE__{} = theme, name) when is_binary(name) do
    if name not in style_names(theme) do
      raise ArgumentError,
            "unknown palette style #{inspect(name)} of theme #{inspect(theme.name)}; see " <>
              "Macaw.Layers.Theme.style_names/1"
    end

    cued(name, composed(theme, name))
  end

  def style(%__MODULE__{} = theme, name) do
    raise ArgumentError,
          "a palette style is a name of Macaw.Layers.Theme.style_names/1 or {:style, i}, " <>
            "i a positive integer; theme #{inspect(theme.name)} got #{inspect(name)}"
  end

  @doc """
  The theme's palette names: its style series, the default's ten when it has none of its
  own, then the roles, the states, the furniture and the modifiers, then its extensions'.
  """
  @spec style_names(t()) :: [String.t(), ...]
  def style_names(%__MODULE__{} = theme),
    do: theme |> own_styles() |> Palette.series() |> Palette.names(extra_styles(theme))

  @doc false
  # Every palette entry of the theme by name, each as `style/2` answers it.
  @spec palette(t()) :: %{String.t() => map()}
  def palette(%__MODULE__{} = theme),
    do: theme |> style_names() |> Map.new(&{&1, cued(&1, composed(theme, &1))})

  # A theme `new/1` built holds no entry that does not compose; a struct written by hand
  # may, and its entry then lays nothing.
  defp composed(theme, name) do
    case Palette.compose(own_styles(theme), name, extra_styles(theme)) do
      {:ok, node} -> node
      {:error, _message} -> %{}
    end
  end

  defp own_styles(%__MODULE__{styles: styles}) when is_map(styles), do: styles
  defp own_styles(%__MODULE__{}), do: %{}

  @doc false
  @spec extra_styles(t()) :: map()
  def extra_styles(%__MODULE__{extensions: extensions}) when is_list(extensions),
    do: Extension.styles(extensions)

  def extra_styles(%__MODULE__{}), do: %{}

  defp cued(name, entry) do
    if name in @role_slots and is_map(entry) do
      %{glyph: glyph, dash: dash} = cue(name)
      entry |> cue_part(:marker, :shape, glyph) |> cue_part(:stroke, :dash, dash)
    else
      entry
    end
  end

  defp cue_part(entry, part, key, value) do
    case entry do
      %{^part => %{^key => :cue} = map} when value == nil ->
        %{entry | part => Map.delete(map, key)}

      %{^part => %{^key => :cue} = map} ->
        %{entry | part => Map.put(map, key, value)}

      _other ->
        entry
    end
  end

  # -- building (§2.5, §2.6) ---------------------------------------------------------------

  @doc """
  `default/0` with the given fields replaced; `ramps`, `colors`, `styles` and `defaults`
  merged key by key. An unknown field raises `KeyError`; an empty `series`, a series or
  furniture color that is not a literal color, or a ramp, color or palette entry that breaks
  its contract, raises `ArgumentError` (§2.6). A string is never a color: read text with
  `Macaw.Layers.Color.parse!/1`, or write it in the source as `~RGB"#555555"`.

      iex> Macaw.Layers.Theme.new(axis: Macaw.Layers.Color.parse!("#555555")).axis
      %Macaw.Layers.Color{r: 85.0, g: 85.0, b: 85.0, opacity: 1.0}
      iex> Macaw.Layers.Theme.new(axis: "#555")
      ** (ArgumentError) theme "default": axis "#555" is text, and a string is never a color: read it with Macaw.Layers.Color.parse!/1, or write ~RGB"#555"
  """
  @spec new(keyword() | map()) :: t()
  def new(fields), do: merge(%{default() | dark: nil}, fields)

  @doc """
  The theme with the given fields replaced, `ramps`, `colors`, `styles` and `defaults` merged
  key by key over its own; the checks of `new/1` apply.

      iex> theme = Macaw.Layers.Theme.new(name: :house, styles: %{muted: %{opacity: 0.4}})
      iex> Macaw.Layers.Theme.style(theme, :muted)
      %{opacity: 0.4}
      iex> Macaw.Layers.Theme.new(name: :house, colors: %{warning: Macaw.Layers.Color.parse!("#f5c242")})
      ** (ArgumentError) theme "house": style "warning" breaks its contract: fill {:color, "warning"} is 1.65:1 against #ffffff; a role style's paint must reach 3:1 (WCAG 1.4.11, non-text contrast)

  Names are strings (§2.1): a name given as an atom is its string, so a host's `"info"`
  and the library's `:info` are one name, the one given winning; a name given both ways in
  one map raises.

      iex> Macaw.Layers.Theme.new(colors: %{"info" => Macaw.Layers.Color.parse!("#2f5d8a")})
      ...> |> Macaw.Layers.Theme.resolve(:info, :css)
      "var(--mw-info, #2f5d8a)"
  """
  @spec merge(t(), keyword() | map()) :: t()
  def merge(%__MODULE__{} = theme, fields) do
    theme = build(theme, fields)

    if theme.series == [], do: raise(ArgumentError, "series: a theme needs at least one color")

    if length(theme.series) > Slots.max(),
      do:
        raise(
          ArgumentError,
          "series: a theme holds at most #{Slots.max()} colors, got #{length(theme.series)}"
        )

    literals!(theme)

    case check(theme) do
      :ok ->
        theme

      {:error, {kind, name}, message} ->
        raise ArgumentError,
              "theme #{inspect(theme.name)}: #{kind} #{inspect(name)} breaks its contract: " <>
                message
    end
  end

  @doc false
  # `merge/2`'s first half: the fields replaced and merged, the extensions checked, nothing
  # else checked.
  @spec build(t(), keyword() | map()) :: t()
  def build(%__MODULE__{} = theme, fields) do
    # Every name a string, once, here (§2.1); words as given.
    fields = fields |> Map.new() |> Names.normalize!(theme.name)
    {ramps, fields} = Map.pop(fields, :ramps, %{})
    # The role colors of before visualize#663 are names of the color table.
    {roles, fields} = Map.pop(fields, :roles, %{})
    {colors, fields} = Map.pop(fields, :colors, %{})
    {styles, fields} = Map.pop(fields, :styles, %{})
    {defaults, fields} = Map.pop(fields, :defaults, %{})
    theme = struct!(theme, fields)

    Extension.check!(
      theme.extensions,
      Palette.fixed_names() ++ Palette.series(Palette.builtin()),
      @library_color_names
    )

    %{
      theme
      | ramps: merged(theme.ramps, ramps, :ramps),
        colors: theme.colors |> merged(roles, :roles) |> merged(colors, :colors),
        styles: merged(theme.styles, styles, :styles),
        defaults: merged(theme.defaults, defaults, :defaults)
    }
  end

  # The series and the furniture hold literal colors, terms (§2.1): text is refused naming
  # the edges that read it.
  defp literals!(theme) do
    fields =
      Enum.with_index(List.wrap(theme.series), &{"series[#{&2}]", &1}) ++
        Enum.map(@furniture, &{Atom.to_string(&1), Map.fetch!(theme, &1)})

    for {field, value} <- fields, not Color.literal?(value) do
      raise ArgumentError, "theme #{inspect(theme.name)}: #{field} #{not_color(value)}"
    end

    :ok
  end

  defp merged(own, given, _key) when is_map(given) and not is_struct(given),
    do: Map.merge(own || %{}, given)

  defp merged(_own, given, key),
    do: raise(ArgumentError, "#{key}: a map of name to value, got #{inspect(given)}")

  @doc """
  `:ok`, or `{:error, subject, message}` for the first ramp, color or palette entry of the
  theme that breaks its contract, `subject` being `{:ramp, name}`, `{:color, name}` or
  `{:style, name}` and `message` naming the term broken with the values measured.

      iex> Macaw.Layers.Theme.check(Macaw.Layers.Theme.dark())
      :ok
      iex> status = Enum.map(~w(#c23238 #bd7407 #4ca34b), &Macaw.Layers.Color.parse!/1)
      iex> theme = %{Macaw.Layers.Theme.default() | ramps: %{"status" => status}}
      iex> {:error, {:ramp, "status"}, message} = Macaw.Layers.Theme.check(theme)
      iex> message =~ "good (0) must be green or blue"
      true
  """
  @spec check(t()) :: :ok | {:error, {:ramp | :color | :style, String.t()}, String.t()}
  def check(%__MODULE__{ramps: ramps} = theme) when is_map(ramps) do
    case violations(theme) do
      [] -> :ok
      [{subject, message} | _] -> {:error, subject, message}
    end
  end

  @doc """
  Every ramp, color and palette entry of the theme that breaks its contract, as
  `{subject, message}` in `check/1`'s order, each contract run alone.
  """
  @spec violations(t()) :: [{{:ramp | :color | :style, String.t()}, String.t()}]
  def violations(%__MODULE__{ramps: ramps} = theme) when is_map(ramps) do
    colors = Table.own_colors(theme)

    # A ramp's anchors are measured as the literals they name; one that names none is left
    # as written, which the contract refuses as no color.
    resolved =
      Map.new(ramps, fn
        {name, anchors} when is_list(anchors) ->
          {name, Enum.map(anchors, &(Table.anchor_literal(theme, &1) || &1))}

        other ->
          other
      end)

    ramp_faults =
      for name <- ordered(ramps, Contract.ramps()),
          {:error, subject, message} <- [Contract.check(Map.take(resolved, [name]), %{})],
          do: {subject, message}

    entry_faults =
      for name <- colors |> Map.keys() |> Enum.sort(),
          {:error, message} <- [Table.entry(theme, name)],
          do: {{:color, name}, message}

    broken = Enum.map(entry_faults, fn {{:color, name}, _} -> name end)

    role_faults =
      for name <- Contract.roles(),
          Map.has_key?(colors, name) and name not in broken,
          roles = %{name => Table.literal(theme, name)},
          {:error, subject, message} <- [Contract.check(%{}, roles)],
          do: {subject, message}

    palette_faults = Palette.violations(own_styles(theme), extra_styles(theme))
    broken = for {{:style, name}, _message} <- palette_faults, do: name

    # The role styles as a set and every palette color name, once the table reads.
    set_faults =
      if entry_faults == [] and ramp_faults == [], do: Roles.violations(theme, broken), else: []

    ramp_faults ++ entry_faults ++ role_faults ++ palette_faults ++ set_faults
  end

  defp ordered(map, known) do
    keys = Map.keys(map)
    Enum.filter(known, &(&1 in keys)) ++ Enum.sort(keys -- known)
  end

  # -- slots and the color table (§2.1, §2.2) ---------------------------------------------

  @doc """
  The theme's slot names: `"series_1"` to `"series_n"`, then the fixed slots.

      iex> Macaw.Layers.Theme.new(series: [Macaw.Layers.Color.parse!("#3b6fa8"), Macaw.Layers.Color.parse!("#d9730d")])
      ...> |> Macaw.Layers.Theme.slots()
      ...> |> Enum.take(4)
      ["series_1", "series_2", "axis", "grid"]
  """
  @spec slots(t()) :: [String.t()]
  def slots(%__MODULE__{series: series}),
    do: Enum.map(1..length(series)//1, &series_name/1) ++ @fixed_slots

  @doc "The color slots: the series, then the furniture, then the five roles."
  @spec color_slots(t()) :: [String.t(), ...]
  def color_slots(%__MODULE__{series: series}),
    do: Enum.map(1..length(series)//1, &series_name/1) ++ @color_slots ++ @role_slots

  @doc """
  Every name of the theme's color table, sorted: its color slots, its own and the default
  theme's colors, its extensions' and the CSS named colors.

      iex> names = Macaw.Layers.Theme.color_names(Macaw.Layers.Theme.default())
      iex> Enum.all?(~w(red amber bad axis series_3 steelblue), &(&1 in names))
      true
  """
  @spec color_names(t()) :: [String.t(), ...]
  def color_names(%__MODULE__{} = theme) do
    (color_slots(theme) ++
       Map.keys(Table.own_colors(theme)) ++
       Map.keys(@light_colors) ++ Map.keys(Table.extra_colors(theme)) ++ @css_names)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Whether `name` is of the theme's color table, answered without building the list. A
  name is its string, an atom read as its string.

      iex> theme = Macaw.Layers.Theme.default()
      iex> Enum.map([:red, "bad", :axis, "series_3", :steelblue, :series_99, :thick], &Macaw.Layers.Theme.color_name?(theme, &1))
      [true, true, true, true, true, false, false]
  """
  @spec color_name?(t(), term()) :: boolean()
  def color_name?(%__MODULE__{} = theme, name) when is_atom(name) or is_binary(name) do
    name = Names.name(name)

    name in @color_slots or name in @role_slots or Table.lookup(theme, name) != nil or
      series_slot?(theme, name)
  end

  def color_name?(%__MODULE__{}, _name), do: false

  defp series_slot?(%__MODULE__{series: series}, name) do
    case Table.series_index(name) do
      k when is_integer(k) -> k >= 1 and k <= length(series) and name == "series_#{k}"
      nil -> false
    end
  end

  @doc """
  The `"series_k"` slot the positive index `i` cycles to over the theme's series.

      iex> Macaw.Layers.Theme.series_slot(Macaw.Layers.Theme.default(), 11)
      "series_1"
  """
  @spec series_slot(t(), pos_integer()) :: String.t()
  def series_slot(%__MODULE__{series: series}, i) when is_integer(i) and i >= 1,
    do: series_name(rem(i - 1, length(series)) + 1)

  def series_slot(%__MODULE__{}, i),
    do: raise(ArgumentError, "a series index is a positive integer, got: #{inspect(i)}")

  @doc false
  # The series slot `"series_k"`.
  @spec series_name(pos_integer()) :: String.t()
  def series_name(k) when is_integer(k) and k >= 1, do: Slots.series(k)

  @doc false
  # The literal a theme pins at step `n` of a name's scale, `nil` when it pins none there.
  @spec step(t(), atom() | String.t(), number()) :: Color.t() | nil
  def step(%__MODULE__{} = theme, name, n), do: Table.step(theme, Names.name(name), n)

  # -- resolution (§3.1) ------------------------------------------------------------------

  @doc """
  The slot's value: the stored literal, or a CSS custom-property reference that falls back
  to its CSS text. A color is a literal `%Macaw.Layers.Color{}` under `:literal`; sizes are
  numbers under `:literal` and gain `px` under `:css`. A ramp position is its literal in
  both modes, as CSS text under `:css`, except where a status role stands, `{:ramp,
  "status", 0 | 0.5 | 1}`, which resolves as the role while the table holds the role there.
  A name, of a slot, a color or a ramp, is its string, an atom read as its string. An
  unknown name, or a series slot beyond the palette, raises `ArgumentError`.
  """
  @spec resolve(t(), slot() | ramp_position(), mode()) :: Color.t() | String.t() | number()
  def resolve(%__MODULE__{} = theme, {:series, i}, mode),
    do: resolve(theme, series_slot(theme, i), mode)

  def resolve(%__MODULE__{} = theme, {:ramp, name, t}, mode) when is_atom(name),
    do: resolve(theme, {:ramp, Names.name(name), t}, mode)

  def resolve(%__MODULE__{} = theme, {:ramp, "status", t}, mode) when is_number(t) do
    case Enum.find(@status_roles, fn {role, at} ->
           at == t and Table.lookup(theme, role) == {:ramp, "status", at}
         end) do
      {role, _at} -> resolve(theme, role, mode)
      nil -> theme |> ramp("status", t) |> written(mode)
    end
  end

  def resolve(%__MODULE__{} = theme, {:ramp, name, t}, mode),
    do: theme |> ramp(name, t) |> written(mode)

  def resolve(%__MODULE__{} = theme, slot, :literal) when is_atom(slot) or is_binary(slot) do
    {_kind, value} = Table.value(theme, Names.name(slot))
    value
  end

  def resolve(%__MODULE__{} = theme, slot, :css) when is_atom(slot) or is_binary(slot) do
    {kind, value} = Table.value(theme, Names.name(slot))
    "var(#{css_name(slot)}, #{Table.css_value(kind, value)})"
  end

  # A ramp position is a literal in both modes (§3.1): in `:css`, its CSS text.
  defp written(literal, :css), do: Color.to_css(literal)
  defp written(literal, :literal), do: literal

  @doc """
  The custom-property name of a slot or a color name: `--mw-` and the name with `_` as `-`.
  A name is lower-case letters, digits and `_`, starting with a letter; any other raises
  `ArgumentError`, so a stylesheet can never be broken out of through a name.

      iex> Macaw.Layers.Theme.css_name(:series_1)
      "--mw-series-1"
  """
  @spec css_name(atom() | String.t()) :: String.t()
  def css_name(name) when is_atom(name) or is_binary(name) do
    spelled = to_string(name)

    if Table.word?(spelled),
      do: "--mw-" <> String.replace(spelled, "_", "-"),
      else: raise(ArgumentError, "a color name is lower-case words, got #{inspect(name)}")
  end

  # -- the ink (§3.2) ---------------------------------------------------------------------

  @doc """
  The contrast ink for a text drawn on `under`: the literal color of the theme's `text` or
  `background`, whichever contrasts more (`text` on a tie), or black or white, whichever
  contrasts more, when neither reaches 4.5:1. `under` is a literal `%Macaw.Layers.Color{}`,
  or `nil` for the theme's background; anything else, text included, raises
  `ArgumentError`. A slot that holds no literal color, in a theme built by hand, is skipped.

      iex> import Macaw.Layers.Color, only: [sigil_RGB: 2]
      iex> theme = Macaw.Layers.Theme.default()
      iex> [Macaw.Layers.Theme.ink(theme, ~RGB"#3b6fa8"), Macaw.Layers.Theme.ink(theme, nil), Macaw.Layers.Theme.ink(theme, ~RGB"#777777")]
      ...> |> Enum.map(&Macaw.Layers.Color.to_css/1)
      ["#ffffff", "#333333", "#000000"]
  """
  @spec ink(t(), Color.t() | nil) :: Color.t()
  defdelegate ink(theme, under), to: Contrast

  # -- contrast and the profile (§2.6, §4) -----------------------------------------------

  @doc """
  The contrast floors a theme offered to people holds against its own background: `text`
  at least 4.5:1, `axis` and every series color at least 3:1, `grid` at least 1.2:1, and a
  `surface` different from the `grid`. `:ok`, or `{:error, faults}`, each `{slot,
  {:contrast, ratio, floor}}`, the slot by its name, or `{"surface", {:equal, "grid"}}`.
  """
  @spec floors(t()) :: :ok | {:error, [{String.t(), term()}, ...]}
  defdelegate floors(theme), to: Contrast

  @doc """
  A color value held to a profile (§4): under `:roles` a value with a literal color among
  its leaves is `{:error, {:literal_color, value}}`; under `:open` every color passes. A term
  that is no color value, text included, raises `ArgumentError`.
  """
  @spec check_color(term(), :roles | :open) :: :ok | {:error, {:literal_color, term()}}
  defdelegate check_color(value, profile), to: Contrast

  @doc """
  A data color under the contrast guard (§4): `{:ok, literal}`, its literal color, where it
  reaches 3:1 against the theme's background, `{:error, {:contrast, ratio}}` where it does
  not, and `{:error, :unreadable}` for a term that is no color value or does not resolve,
  text included.
  """
  @spec data_color(t(), term()) ::
          {:ok, Color.t()} | {:error, {:contrast, float()} | :unreadable}
  defdelegate data_color(theme, value), to: Contrast
end
