defmodule Macaw.Layers.Theme do
  @moduledoc """
  The colors, fonts and sizes a page draws with (spec/04 §2, §3).

  A theme is a struct of named **slots**: `:series_1` … `:series_n` for the categorical
  colors; the furniture `:axis`, `:grid`, `:text`, `:background` and `:surface`; the five
  **roles** `:good`, `:warning`, `:bad`, `:info` and `:neutral`; and `:font_family`,
  `:font_size`, `:label_size` and `:title_size`. Its colors are one **color table** (§2.2):
  the theme's own `colors` over the default theme's, its extensions' and the CSS named
  colors, with the furniture and the series as names too, so `Macaw.Layers.Color.color(:red)`
  is the theme's red. Everything reads a theme through `resolve/3`, in the mode its output
  needs:

    * `:literal` - the stored value, which a canvas needs;
    * `:css` - a custom-property reference with the literal as its fallback,
      `var(--mw-axis, #666666)`, so a stylesheet can override it from any ancestor.

  ## Meaning: ramps, roles and cues

  A series color promises *distinct*, never a meaning. A theme also carries four **ramps**
  whose meaning the library fixes (§2.3): `:status`, `:thermal`, `:diverging` and
  `:sequential`, each a list of anchors interpolated in CIE Lab, and every role and ramp is
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
      "#7fb3e6"
      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.default(), :warning, :literal)
      "#bd7407"
      iex> Macaw.Layers.Theme.resolve(Macaw.Layers.Theme.default(), {:ramp, :status, 0.5}, :css)
      "var(--mw-warning, #bd7407)"

  Ported from visualize's `Visualize.Theme`.
  """

  alias Macaw.Layers.Color
  alias Macaw.Layers.Theme.{Contract, Contrast, Extension, Names, Palette, Roles, Slots, Table}

  @light_series ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480)
  @dark_series ~w(#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6)

  # The ramps of §2.5, chosen in CIE LCh to hold the contracts of §2.3 with room.
  @light_ramps %{
    # The status ramp is defined from the theme's green, amber and red.
    status: [{:color, :green}, {:color, :amber}, {:color, :red}],
    thermal: ~w(#0e68ad #e8e8e8 #c02e31),
    diverging: ~w(#b35806 #ededed #62448e),
    sequential: ~w(#e9f2fc #5e95d3 #004580)
  }
  @dark_ramps %{
    status: [{:color, :green}, {:color, :amber}, {:color, :red}],
    thermal: ~w(#7fb3e6 #3a3f48 #f47c7c),
    diverging: ~w(#f7a35c #3a3f48 #c1acee),
    sequential: ~w(#273b4f #457cb1 #aad1f9)
  }
  # Blue → orange → red: the status order survives the commonest color-vision deficiencies.
  @safe_status ~w(#5996d6 #cd6012 #b92931)

  # The theme's own part of its color table (§2.2): its status hues, the hues of `:info`
  # and `:neutral`, and the five roles by use, the status three as their positions on the
  # status ramp, so a role and its position never disagree.
  @by_use %{good: {:ramp, :status, 0}, warning: {:ramp, :status, 0.5}, bad: {:ramp, :status, 1}}
  @light_colors Map.merge(@by_use, %{
                  red: "#c23238",
                  amber: "#bd7407",
                  green: "#4ca34b",
                  blue: "#3b6fa8",
                  gray: "#6f7480",
                  info: "#3b6fa8",
                  neutral: "#6f7480"
                })
  @dark_colors Map.merge(@by_use, %{
                 red: "#ff8f8a",
                 amber: "#db8e1c",
                 green: "#4f924c",
                 blue: "#7fb3e6",
                 gray: "#b7bcc6",
                 info: "#7fb3e6",
                 neutral: "#b7bcc6"
               })
  # The CSS named colors, the table's base (§1.1, §2.2).
  @css_names Macaw.Layers.Color.Names.atoms()

  defstruct name: :default,
            series: @light_series,
            axis: "#666666",
            grid: "#e0e0e0",
            text: "#333333",
            background: "#ffffff",
            surface: "#eef2f6",
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

  @typedoc "One of the four ramps whose meaning the library fixes (§2.3)."
  @type ramp_name :: :status | :thermal | :diverging | :sequential

  @typedoc "A slot name, or `{:series, i}` for the i-th series color, cycling."
  @type slot :: atom() | String.t() | {:series, pos_integer()}

  @typedoc "A position along a ramp: `t` in `0..1`, clamped."
  @type ramp_position :: {:ramp, ramp_name(), number()}

  @typedoc "A name of the style palette, or `{:style, i}` for the i-th style series entry."
  @type style_name :: atom() | String.t() | {:style, pos_integer()}

  @typedoc "How a slot renders: a CSS reference with its fallback, or the stored value."
  @type mode :: :css | :literal

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          series: [String.t(), ...],
          axis: String.t(),
          grid: String.t(),
          text: String.t(),
          background: String.t(),
          surface: String.t(),
          ramps: %{optional(ramp_name()) => list()},
          colors: %{optional(atom() | String.t()) => term()},
          styles: %{optional(atom()) => map() | list()},
          defaults: map(),
          font_family: String.t(),
          font_size: number(),
          label_size: number(),
          title_size: number(),
          dark: atom() | String.t() | nil,
          light: atom() | String.t() | nil,
          extensions: [module()]
        }

  @color_slots [:axis, :grid, :text, :background, :surface]
  # Where the status roles stand on the status ramp, by default (§2.3).
  @status_roles [good: 0, warning: 0.5, bad: 1]
  @role_slots [:good, :warning, :bad, :info, :neutral]
  @size_slots [:font_size, :label_size, :title_size]
  @fixed_slots @color_slots ++ @role_slots ++ [:font_family] ++ @size_slots
  @builtin [:default, :dark, :color_safe, :print]
  # Every color name the library itself gives (§2.2): a document's color name is read as
  # one of these atoms, and any other as the string it is, a name the theme declares.
  @library_color_names Enum.uniq(
                         @fixed_slots ++
                           Map.keys(@light_colors) ++ Map.keys(@dark_colors) ++ @css_names
                       )

  @doc false
  @spec library_color_names() :: [atom(), ...]
  def library_color_names, do: @library_color_names

  @doc false
  # The default theme's own colors, the table's second part (§2.2).
  @spec default_colors() :: map()
  def default_colors, do: @light_colors

  @doc false
  @spec default_ramps() :: map()
  def default_ramps, do: @light_ramps

  @doc false
  @spec fixed_slots() :: [atom(), ...]
  def fixed_slots, do: @fixed_slots

  @doc false
  @spec size_slots() :: [atom(), ...]
  def size_slots, do: @size_slots

  # -- the built-in themes (§2.5) ----------------------------------------------------------

  @doc "The light theme: dark text and axes on white."
  @spec default() :: t()
  def default, do: %__MODULE__{dark: :dark}

  @doc "The dark theme: light text and axes on `#1b1e24`."
  @spec dark() :: t()
  def dark do
    %__MODULE__{
      name: :dark,
      series: @dark_series,
      axis: "#a0a4ab",
      grid: "#33373f",
      text: "#e6e6e6",
      background: "#1b1e24",
      surface: "#23272f",
      ramps: @dark_ramps,
      colors: @dark_colors,
      light: :default
    }
  end

  @doc """
  The color-vision-safe theme: `default/0` with its `status` ramp blue → orange → red, which
  survives the commonest color-vision deficiencies, in place of green → amber → red.
  """
  @spec color_safe() :: t()
  def color_safe,
    do: %__MODULE__{name: :color_safe, ramps: %{@light_ramps | status: @safe_status}}

  @doc """
  The print theme: paper. A white background and surface, near-black text and axes, a grid
  dark enough to survive a photocopy, the color-safe `status` ramp, and role styles whose
  fills are hatches of the role's color, so a grayscale copy keeps each role apart.
  """
  @spec print() :: t()
  def print do
    %__MODULE__{
      name: :print,
      axis: "#333333",
      grid: "#c8c8c8",
      text: "#111111",
      background: "#ffffff",
      surface: "#ffffff",
      ramps: %{@light_ramps | status: @safe_status},
      styles: Palette.print()
    }
  end

  @doc """
  The built-in theme of a name, `:default`, `:dark`, `:color_safe` or `:print`, by either
  spelling, or `nil`.

      iex> Macaw.Layers.Theme.builtin("color_safe").name
      :color_safe
      iex> Macaw.Layers.Theme.builtin(:house)
      nil
  """
  @spec builtin(atom() | String.t()) :: t() | nil
  def builtin(name) when is_binary(name) do
    case Enum.find(@builtin, &(Atom.to_string(&1) == name)) do
      nil -> nil
      found -> builtin(found)
    end
  end

  def builtin(:default), do: default()
  def builtin(:dark), do: dark()
  def builtin(:color_safe), do: color_safe()
  def builtin(:print), do: print()
  def builtin(_name), do: nil

  @doc false
  @spec builtins() :: [atom(), ...]
  def builtins, do: @builtin

  # -- ramps, roles and cues (§2.3) ------------------------------------------------------

  @doc "The four ramps whose meaning the library fixes."
  @spec ramp_names() :: [ramp_name(), ...]
  def ramp_names, do: Contract.ramps()

  @doc "The five roles: the status ramp's three fixed points, then `:info` and `:neutral`."
  @spec role_names() :: [atom(), ...]
  def role_names, do: @role_slots

  # Each role's cue besides its hue: the library's, not a theme's, as the hue order is.
  @cues %{
    good: %{glyph: :circle, dash: nil},
    warning: %{glyph: :triangle, dash: "6 3"},
    bad: %{glyph: :cross, dash: "2 3"},
    info: %{glyph: :square, dash: "8 3 2 3"},
    neutral: %{glyph: :diamond, dash: "1 4"}
  }

  @doc """
  A role's cue besides its hue: its glyph and its dash (`nil` for solid), so a status reads
  without its hue. Raises `ArgumentError` for anything but a role.

      iex> Macaw.Layers.Theme.cue(:warning)
      %{glyph: :triangle, dash: "6 3"}
  """
  @spec cue(atom()) :: %{glyph: atom(), dash: String.t() | nil}
  def cue(role) do
    case Map.fetch(@cues, role) do
      {:ok, cue} ->
        cue

      :error ->
        raise ArgumentError,
              "a cue is a role's, one of #{inspect(@role_slots)}; got: #{inspect(role)}"
    end
  end

  @doc """
  The color at `t` along the theme's ramp `name`, as a literal: the anchors spread evenly
  over `0..1` and interpolated in CIE Lab, a position on an anchor the anchor as written,
  `t` clamped. A theme that lacks the ramp takes the default theme's, never a series color.

      iex> Macaw.Layers.Theme.ramp(Macaw.Layers.Theme.default(), :thermal, 0.25)
      "#8da5cb"
  """
  @spec ramp(t(), ramp_name(), number()) :: String.t()
  def ramp(%__MODULE__{} = theme, name, t) when is_number(t) do
    anchors = Table.anchors(theme, name)
    n = length(anchors) - 1
    position = (t |> max(0) |> min(1)) * n
    i = min(trunc(position), n - 1)
    u = position - i

    if u == 0 do
      Enum.at(anchors, i)
    else
      Color.interpolate_lab(
        anchor!(name, Enum.at(anchors, i)),
        anchor!(name, Enum.at(anchors, i + 1)),
        u
      )
      |> Color.to_hex()
    end
  end

  def ramp(%__MODULE__{}, name, t),
    do:
      raise(
        ArgumentError,
        "ramp #{inspect(name)}: a position is a number in 0..1, got #{inspect(t)}"
      )

  defp anchor!(name, anchor) do
    (is_binary(anchor) && Color.parse(anchor)) ||
      raise ArgumentError, "ramp #{inspect(name)}: anchor #{inspect(anchor)} is not a color"
  end

  # -- the style palette (§2.4) ------------------------------------------------------------

  @doc """
  The palette entry `name` as one style node in its parts: the theme's own, the default
  theme's entry whole where the theme lacks it, or an extension's default. `{:style, i}`
  cycles over the style series; in a role's entry `:cue` becomes the role's dash and glyph,
  a solid dash leaving the key out. Any other name raises `ArgumentError`.

      iex> Macaw.Layers.Theme.style(Macaw.Layers.Theme.default(), :warning)
      %{fill: %{type: :solid, color: {:color, :warning}}, stroke: %{type: :solid, color: {:color, :warning}, dash: "6 3"}, marker: %{shape: :triangle}}
      iex> Macaw.Layers.Theme.style(Macaw.Layers.Theme.default(), :muted)
      %{opacity: 0.25}
  """
  @spec style(t(), style_name()) :: map()
  def style(%__MODULE__{} = theme, {:style, i}) when is_integer(i) and i >= 1 do
    series = theme |> own_styles() |> Palette.series()
    style(theme, Enum.at(series, rem(i - 1, length(series))))
  end

  def style(%__MODULE__{} = theme, name) when is_binary(name) do
    case Enum.find(style_names(theme), &(Atom.to_string(&1) == name)) do
      nil -> style(theme, {:unknown, name})
      found -> style(theme, found)
    end
  end

  def style(%__MODULE__{} = theme, name) when is_atom(name) do
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
  @spec style_names(t()) :: [atom(), ...]
  def style_names(%__MODULE__{} = theme),
    do: theme |> own_styles() |> Palette.series() |> Palette.names(extra_styles(theme))

  @doc false
  # Every palette entry of the theme by name, each as `style/2` answers it.
  @spec palette(t()) :: %{atom() => map()}
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
  merged key by key. An unknown field raises `KeyError`; an empty `series`, or a ramp,
  color or palette entry that breaks its contract, raises `ArgumentError` (§2.6).
  """
  @spec new(keyword() | map()) :: t()
  def new(fields), do: merge(%{default() | dark: nil}, fields)

  @doc """
  The theme with the given fields replaced, `ramps`, `colors`, `styles` and `defaults` merged
  key by key over its own; the checks of `new/1` apply.

      iex> theme = Macaw.Layers.Theme.new(name: :house, styles: %{muted: %{opacity: 0.4}})
      iex> Macaw.Layers.Theme.style(theme, :muted)
      %{opacity: 0.4}
      iex> Macaw.Layers.Theme.new(name: :house, colors: %{warning: "#f5c242"})
      ** (ArgumentError) theme "house": style :warning breaks its contract: fill {:color, :warning} is 1.65:1 against #ffffff; a role style's paint must reach 3:1 (WCAG 1.4.11, non-text contrast)
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
    fields = Map.new(fields)
    {ramps, fields} = Map.pop(fields, :ramps, %{})
    # The role colors of before visualize#663 are names of the color table.
    {roles, fields} = Map.pop(fields, :roles, %{})
    {colors, fields} = Map.pop(fields, :colors, %{})
    {styles, fields} = Map.pop(fields, :styles, %{})
    {defaults, fields} = Map.pop(fields, :defaults, %{})
    theme = struct!(theme, Names.fields(fields))

    Extension.check!(
      theme.extensions,
      Palette.fixed_names() ++ Palette.series(Palette.builtin()),
      @library_color_names
    )

    %{
      theme
      | ramps: merged(theme.ramps, ramps, :ramps),
        colors:
          theme.colors
          |> merged(Names.colors(roles), :roles)
          |> merged(Names.colors(colors), :colors),
        styles:
          theme.styles
          |> merged(styles, :styles)
          |> Map.new(fn {k, v} -> {k, typed(v)} end)
          |> Names.styles(Palette.fixed_names() ++ Map.keys(extra_styles(theme))),
        defaults: theme.defaults |> merged(defaults, :defaults) |> Names.defaults()
    }
  end

  defp merged(own, given, _key) when is_map(given), do: Map.merge(own || %{}, given)
  defp merged(own, given, key) when is_list(given), do: merged(own, Map.new(given), key)

  defp merged(_own, given, key),
    do: raise(ArgumentError, "#{key}: a map of name to value, got #{inspect(given)}")

  # A color written as a bare atom in a paint is the typed color it names (§2.4); `:none`
  # is no color.
  defp typed(entry) when is_map(entry) and not is_struct(entry) do
    Map.new(entry, fn
      {part, %{color: color} = paint}
      when part in [:fill, :stroke] and is_atom(color) and
             color not in [nil, true, false, :none, :cue] ->
        {part, %{paint | color: {:color, color}}}

      other ->
        other
    end)
  end

  defp typed(entries) when is_list(entries), do: Enum.map(entries, &typed/1)
  defp typed(entry), do: entry

  @doc """
  `:ok`, or `{:error, subject, message}` for the first ramp, color or palette entry of the
  theme that breaks its contract, `subject` being `{:ramp, name}`, `{:color, name}` or
  `{:style, name}` and `message` naming the term broken with the values measured.

      iex> Macaw.Layers.Theme.check(Macaw.Layers.Theme.dark())
      :ok
      iex> theme = %{Macaw.Layers.Theme.default() | ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}}
      iex> {:error, {:ramp, :status}, message} = Macaw.Layers.Theme.check(theme)
      iex> message =~ "good (0) must be green or blue"
      true
  """
  @spec check(t()) :: :ok | {:error, {:ramp | :color | :style, atom() | String.t()}, String.t()}
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
  @spec violations(t()) :: [{{:ramp | :color | :style, atom() | String.t()}, String.t()}]
  def violations(%__MODULE__{ramps: ramps} = theme) when is_map(ramps) do
    colors = Table.own_colors(theme)

    # A ramp's anchors are measured as the strings they name; one that names none is left
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
      for name <- colors |> Map.keys() |> Enum.sort_by(&to_string/1),
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

  @doc "The theme's slot names: `:series_1` to `:series_n`, then the fixed slots."
  @spec slots(t()) :: [atom()]
  def slots(%__MODULE__{series: series}),
    do: Enum.map(1..length(series)//1, &series_atom/1) ++ @fixed_slots

  @doc "The color slots: the series, then the furniture, then the five roles."
  @spec color_slots(t()) :: [atom(), ...]
  def color_slots(%__MODULE__{series: series}),
    do: Enum.map(1..length(series)//1, &series_atom/1) ++ @color_slots ++ @role_slots

  @doc """
  Every name of the theme's color table, sorted: its color slots, its own and the default
  theme's colors, its extensions' and the CSS named colors.

      iex> names = Macaw.Layers.Theme.color_names(Macaw.Layers.Theme.default())
      iex> Enum.all?([:red, :amber, :bad, :axis, :series_3, :steelblue], &(&1 in names))
      true
  """
  @spec color_names(t()) :: [atom() | String.t(), ...]
  def color_names(%__MODULE__{} = theme) do
    (color_slots(theme) ++
       Map.keys(Table.own_colors(theme)) ++
       Map.keys(@light_colors) ++ Map.keys(Table.extra_colors(theme)) ++ @css_names)
    |> Enum.uniq()
    |> Enum.sort_by(&{is_binary(&1), &1})
  end

  @doc """
  Whether `name` is of the theme's color table, answered without building the list.

      iex> theme = Macaw.Layers.Theme.default()
      iex> Enum.map([:red, :bad, :axis, :series_3, :steelblue, :series_99, :thick], &Macaw.Layers.Theme.color_name?(theme, &1))
      [true, true, true, true, true, false, false]
  """
  @spec color_name?(t(), term()) :: boolean()
  def color_name?(%__MODULE__{} = theme, name) when is_atom(name) or is_binary(name) do
    name in @color_slots or name in @role_slots or Table.lookup(theme, name) != nil or
      series_slot?(theme, name)
  end

  def color_name?(%__MODULE__{}, _name), do: false

  defp series_slot?(%__MODULE__{series: series}, name) do
    case Table.series_index(name) do
      k when is_integer(k) -> k >= 1 and k <= length(series) and to_string(name) == "series_#{k}"
      nil -> false
    end
  end

  @doc "The `:series_k` slot the positive index `i` cycles to over the theme's series."
  @spec series_slot(t(), pos_integer()) :: atom()
  def series_slot(%__MODULE__{series: series}, i) when is_integer(i) and i >= 1,
    do: series_atom(rem(i - 1, length(series)) + 1)

  def series_slot(%__MODULE__{}, i),
    do: raise(ArgumentError, "a series index is a positive integer, got: #{inspect(i)}")

  @doc false
  # The series slot `:series_k`, one atom per index a theme holds.
  @spec series_atom(pos_integer()) :: atom()
  def series_atom(k) when is_integer(k) and k >= 1, do: Slots.series(k)

  @doc false
  # The literal a theme pins at step `n` of a name's scale, `nil` when it pins none there.
  @spec step(t(), atom() | String.t(), number()) :: String.t() | nil
  def step(%__MODULE__{} = theme, name, n), do: Table.step(theme, name, n)

  # -- resolution (§3.1) ------------------------------------------------------------------

  @doc """
  The slot's value: the stored literal, or a CSS custom-property reference that falls back
  to it. Sizes are numbers under `:literal` and gain `px` under `:css`. A ramp position is
  its literal in both modes, except where a status role stands, `{:ramp, :status, 0 | 0.5 |
  1}`, which resolves as the role while the table holds the role there. An unknown name, or
  a series slot beyond the palette, raises `ArgumentError`.
  """
  @spec resolve(t(), slot() | ramp_position(), mode()) :: String.t() | number()
  def resolve(%__MODULE__{} = theme, {:series, i}, mode),
    do: resolve(theme, series_slot(theme, i), mode)

  def resolve(%__MODULE__{} = theme, {:ramp, :status, t}, mode) when is_number(t) do
    case Enum.find(@status_roles, fn {role, at} ->
           at == t and Table.lookup(theme, role) == {:ramp, :status, at}
         end) do
      {role, _at} -> resolve(theme, role, mode)
      nil -> ramp(theme, :status, t)
    end
  end

  def resolve(%__MODULE__{} = theme, {:ramp, name, t}, _mode), do: ramp(theme, name, t)

  def resolve(%__MODULE__{} = theme, slot, :literal) when is_atom(slot) or is_binary(slot) do
    {_kind, value} = Table.value(theme, slot)
    value
  end

  def resolve(%__MODULE__{} = theme, slot, :css) when is_atom(slot) or is_binary(slot) do
    {kind, value} = Table.value(theme, slot)
    "var(#{css_name(slot)}, #{Table.css_value(kind, value)})"
  end

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
  The contrast ink for a text drawn on `under`: the literal of the theme's `text` or
  `background`, whichever contrasts more (`text` on a tie), or `#000000`/`#ffffff`,
  whichever contrasts more, when neither reaches 4.5:1. `under` is a color string, a
  `%Macaw.Layers.Color{}`, or `nil` for the theme's background; an unreadable string is
  `nil`, and a slot whose own value does not parse is skipped.

      iex> theme = Macaw.Layers.Theme.default()
      iex> {Macaw.Layers.Theme.ink(theme, "#3b6fa8"), Macaw.Layers.Theme.ink(theme, nil), Macaw.Layers.Theme.ink(theme, "#777777")}
      {"#ffffff", "#333333", "#000000"}
  """
  @spec ink(t(), String.t() | Color.t() | nil) :: String.t()
  defdelegate ink(theme, under), to: Contrast

  # -- contrast and the profile (§2.6, §4) -----------------------------------------------

  @doc """
  The contrast floors a theme offered to people holds against its own background: `text`
  at least 4.5:1, `axis` and every series color at least 3:1, `grid` at least 1.2:1, and a
  `surface` different from the `grid`. `:ok`, or `{:error, faults}`, each `{slot,
  {:contrast, ratio, floor}}` or `{:surface, {:equal, :grid}}`.
  """
  @spec floors(t()) :: :ok | {:error, [{atom(), term()}, ...]}
  defdelegate floors(theme), to: Contrast

  @doc """
  A color value held to a profile (§4): under `:roles` a value with a literal string among
  its leaves is `{:error, {:literal_color, value}}`; under `:open` every color passes.
  """
  @spec check_color(term(), :roles | :open) :: :ok | {:error, {:literal_color, term()}}
  defdelegate check_color(value, profile), to: Contrast

  @doc """
  A data color under the contrast guard (§4): `{:ok, literal}` where it reaches 3:1 against
  the theme's background, `{:error, {:contrast, ratio}}` where it does not, and `{:error,
  :unreadable}` for a value that does not resolve.
  """
  @spec data_color(t(), term()) ::
          {:ok, String.t()} | {:error, {:contrast, float()} | :unreadable}
  defdelegate data_color(theme, value), to: Contrast
end
