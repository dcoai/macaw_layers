defmodule Macaw.Layers.Theme.Tags do
  @moduledoc false
  # The tag table of a theme document (spec/01 §6): the color tags and `$var`, read so a
  # variable is refused by name rather than as an unknown tag.
  use Macaw.Layers.Tags, live: ["$var" | Macaw.Layers.Color.Form.tags()]
end

defmodule Macaw.Layers.Theme.Document do
  @moduledoc """
  A theme as a document (spec/04 §5): stored and shipped as a value, and judged as one.

    * the value is `%{version: v, theme: node}` (`to_map/1`), and a store's fragment
      `%{theme: node}` (`fragment/1`), a library entry of kind `:theme`, reads as the same
      document;
    * the JSON form is `{"$version": v, "theme": {…}}` (`to_json/1`), each color a tag (a
      literal `$rgb`, `$color`, `$series`, `$ramp`, the transforms by name, `$blend`,
      `$contrast`) and pinned steps `$steps`, written and read by the JSON adapter
      (`Macaw.Layers.Form`, `Macaw.Layers.Color.Form`), every name in `ramps`, `colors`,
      `styles` and `defaults` a string, as the theme holds it, and every word (an entry's
      keys and atom values) read from the library's vocabulary and the registered
      extensions' words (`Macaw.Layers.Theme.Extension.words/0`).

  `from_map/2` judges the value as terms, after the version check, with no form written
  or read; `from_json/2` reads the JSON form through the adapter's gates (spec/01 §5: the
  limits, the version, the migration) to the same value. A name given both as its atom and
  as its string in one name map of a value is `{:duplicate, :name}` at its path. Then: a
  node that is a **name** reads as the built-in theme of that name, any other name is
  `{:unknown_theme, name}`; a variable anywhere is `{:unresolved, :var, name}`, since
  nothing applies a theme; a key the theme does not have is `:unknown_key`; and every
  contract a ramp, color or palette entry breaks is `{:contract, message}` at
  `[:theme, :ramps | :colors | :styles, name]`.

  The line is at version 2: a literal color is a term, tagged `$rgb` in the JSON form.
  Version 1 wrote it as CSS text; its step tags each string at a color position that
  `Macaw.Layers.Color.parse/1` reads, so a version 1 document, or a bundle's entry of one,
  reads to the same theme.

  As a fragment type (spec/02 §1), `ramps`, `colors`, `styles` and `defaults` are `:union`
  name maps and every other key `:override`, so a theme document stacks over a built-in as
  `Macaw.Layers.Theme.new/1` merges.

      iex> theme = Macaw.Layers.Theme.new(name: :house, axis: Macaw.Layers.Color.parse!("#555555"))
      iex> Macaw.Layers.Theme.Document.from_map(Macaw.Layers.Theme.Document.to_map(theme))
      {:ok, theme}
      iex> Macaw.Layers.Theme.Document.from_map(%{theme: :dark})
      {:ok, Macaw.Layers.Theme.dark()}

  Ported from visualize's `Visualize.Chart.Theme`.
  """

  @behaviour Macaw.Layers.Document
  @behaviour Macaw.Layers.Version
  @behaviour Macaw.Layers.Form
  @behaviour Macaw.Layers.Fragment

  import Kernel, except: [node: 1]

  alias Macaw.Layers.{Color, Document, Fault, Form, Fragment, Theme, Var, Version}
  alias Macaw.Layers.Color.Form, as: ColorForm
  alias Macaw.Layers.Theme.{Extension, Names, Words}

  @unions [:ramps, :colors, :styles, :defaults]
  @furniture [:axis, :grid, :text, :background, :surface]
  @series_max Macaw.Layers.Theme.Slots.max()

  # -- the document ------------------------------------------------------------------------

  @doc """
  The theme as its node: every field but `extensions`, an unset counterpart and empty
  defaults left out. Its names are strings, as the theme holds them (spec/04 §2.1), and
  its words as given.
  """
  @spec node(Theme.t()) :: map()
  def node(%Theme{} = theme) do
    theme
    |> Map.take(Words.fields())
    |> Map.reject(fn {k, v} ->
      (k in [:dark, :light] and v == nil) or (k == :defaults and v == %{})
    end)
  end

  @doc "`%{theme: node}`: a store's fragment of kind `:theme`."
  @spec fragment(Theme.t()) :: %{theme: map()}
  def fragment(%Theme{} = theme), do: %{theme: node(theme)}

  @doc "`%{version: current, theme: node}`."
  @spec to_map(Theme.t()) :: %{version: pos_integer(), theme: map()}
  def to_map(%Theme{} = theme), do: %{version: current(), theme: node(theme)}

  @doc """
  The JSON document, `{:ok, json}`, stamped `\"$version\"`, its words written with the
  theme's extensions' (`Macaw.Layers.Theme.Extension.words/0`).
  """
  @spec to_json(Theme.t()) :: {:ok, String.t()} | {:error, [Fault.t(), ...]}
  def to_json(%Theme{} = theme) do
    Form.to_json(fragment(theme), __MODULE__, vocabulary: words(theme.extensions))
  end

  defp words(extensions) when is_list(extensions), do: Extension.words(extensions)
  defp words(_other), do: %{}

  @doc """
  The theme a document value or a theme fragment holds, judged as terms, or every fault.
  `extensions:` the extensions the host registers, which the theme carries and its
  contracts hold. No form is written or read, so no limit applies: the limits bound what
  reading an encoding costs (`from_json/2`).
  """
  @spec from_map(term(), keyword()) :: {:ok, Theme.t()} | {:error, [Fault.t(), ...]}
  def from_map(document, opts \\ [])

  def from_map(document, opts) when is_map(document) and not is_struct(document) do
    {version, value} = Map.pop(document, :version, current())

    # The version first: nothing of a newer document is judged.
    with {:ok, _version} <- Version.check(%{Version.stamp() => version}, __MODULE__),
         {:ok, %{theme: node}} <- Document.check(value, __MODULE__) do
      build(node, Keyword.get(opts, :extensions, []))
    end
  end

  def from_map(_other, _opts), do: {:error, [{[], {:type, :map}}]}

  @doc """
  The theme a JSON document holds: read through the JSON adapter (`Macaw.Layers.Form.read/3`:
  every gate, then the value, judged), then built as `from_map/2` builds it. `limits:` as
  `Macaw.Layers.Form.gates/3` takes them, and `extensions:` as `from_map/2`: the reader's
  vocabulary is the library's words and these extensions' (`Extension.words/0`), so an
  adopter's words read back only with its extension given, and no other atom is made.
  """
  @spec from_json(String.t(), keyword()) :: {:ok, Theme.t()} | {:error, [Fault.t(), ...]}
  def from_json(json, opts \\ []) when is_binary(json) do
    extensions = Keyword.get(opts, :extensions, [])
    read = [vocabulary: words(extensions)] ++ Keyword.take(opts, [:limits])

    with {:ok, %{theme: node}} <- Form.read(json, __MODULE__, read),
         do: build(node, extensions)
  end

  # -- the theme ---------------------------------------------------------------------------

  defp build(name, _extensions) when is_atom(name) or is_binary(name) do
    case Theme.builtin(name) do
      nil -> {:error, [{[:theme], {:unknown_theme, to_string(name)}}]}
      theme -> {:ok, theme}
    end
  end

  defp build(node, extensions) when is_map(node) do
    with {:ok, node} <- names(node),
         :ok <- faults(variables(node, [:theme])),
         :ok <- faults(shape(node)) do
      theme = Theme.build(%{Theme.default() | dark: nil}, Map.put(node, :extensions, extensions))

      case Theme.violations(theme) do
        [] -> {:ok, theme}
        violations -> {:error, violations |> Enum.map(&contract/1) |> Fault.sort()}
      end
    end
  end

  defp build(_other, _extensions), do: {:error, [{[:theme], {:type, :map}}]}

  defp faults([]), do: :ok
  defp faults(faults), do: {:error, Fault.sort(faults)}

  defp contract({{kind, name}, message}),
    do: {[:theme, plural(kind), name], {:contract, message}}

  defp plural(:ramp), do: :ramps
  defp plural(:color), do: :colors
  defp plural(:style), do: :styles

  # The node's names as strings, by the theme's one normalization (`Theme.Names`), whichever
  # way the node came: the JSON form's are strings already, and a value built in Elixir may
  # spell them as atoms. A name given both ways in one map is `{:duplicate, :name}`.
  defp names(node) do
    case Names.normalize(node) do
      {:ok, node} -> {:ok, node}
      {:duplicate, [key, name]} -> {:error, [{[:theme, key, name], {:duplicate, :name}}]}
    end
  end

  defp variables(%Var{name: name}, path), do: [{path, {:unresolved, :var, name}}]
  defp variables(%_{}, _path), do: []

  defp variables(map, path) when is_map(map),
    do: Enum.flat_map(map, fn {k, v} -> variables(v, path ++ [k]) end)

  defp variables(list, path) when is_list(list),
    do: list |> Enum.with_index() |> Enum.flat_map(fn {v, i} -> variables(v, path ++ [i]) end)

  defp variables(_leaf, _path), do: []

  # Every field a theme has, each of the shape it holds.
  defp shape(node) do
    Enum.flat_map(node, fn {key, value} ->
      cond do
        key not in Words.fields() -> [{[:theme, key], :unknown_key}]
        true -> field(key, value)
      end
    end)
  end

  defp field(:series, series) when is_list(series) and length(series) > @series_max,
    do: [{[:theme, :series], {:limit, :series, @series_max, length(series)}}]

  # The series and the furniture are literal colors, terms: a string is never one.
  defp field(:series, [_ | _] = series) do
    for {c, i} <- Enum.with_index(series),
        not Color.literal?(c),
        do: {[:theme, :series, i], {:type, :color}}
  end

  defp field(:series, _other), do: [{[:theme, :series], {:type, :colors}}]

  defp field(key, value) when key in @furniture,
    do: if(Color.literal?(value), do: [], else: [{[:theme, key], {:type, :color}}])

  defp field(:font_family, value) when is_binary(value), do: []
  defp field(:font_family, _value), do: [{[:theme, :font_family], {:type, :string}}]

  defp field(key, value)
       when key in [:font_size, :label_size, :title_size] and is_number(value) and value > 0,
       do: []

  defp field(key, _value) when key in [:font_size, :label_size, :title_size],
    do: [{[:theme, key], {:type, :pos_number}}]

  defp field(key, value) when key in @unions and is_map(value) and not is_struct(value), do: []
  defp field(key, _value) when key in @unions, do: [{[:theme, key], {:type, :map}}]
  defp field(:name, value) when is_binary(value) or is_atom(value), do: []
  defp field(:name, _value), do: [{[:theme, :name], {:type, :string}}]

  defp field(key, value) when key in [:dark, :light] do
    if value == nil or Theme.builtin(value) != nil,
      do: [],
      else: [{[:theme, key], {:unknown_theme, value}}]
  end

  # -- the behaviors -----------------------------------------------------------------------

  @impl Version
  def current, do: 2

  # 1 -> 2: a literal color is a term, tagged `$rgb` (spec/04 §1.6, §5); version 1 wrote it
  # as CSS text. Each string at a color position that `Color.parse/1` reads is tagged; any
  # other string is left as it is, for the reader to refuse at its path. A node that is a
  # name holds no color.
  @impl Version
  def step(%{"theme" => node} = document, 1) when is_map(node),
    do: {:ok, %{document | "theme" => tag_colors(node)}}

  def step(document, 1), do: {:ok, document}

  @furniture_keys Enum.map(@furniture, &Atom.to_string/1)
  @op_keys Enum.map(Macaw.Layers.Color.Typed.ops(), &"$#{&1}")

  # The color positions of a node's map form: the series, the furniture, the ramps'
  # anchors, the colors' entries and the styles' paint colors.
  defp tag_colors(node) do
    Map.new(node, fn
      {"series", series} when is_list(series) -> {"series", Enum.map(series, &tag/1)}
      {key, value} when key in @furniture_keys -> {key, tag(value)}
      {"ramps", ramps} when is_map(ramps) -> {"ramps", Map.new(ramps, &tag_anchors/1)}
      {"colors", colors} when is_map(colors) -> {"colors", Map.new(colors, &tag_entry/1)}
      {"styles", styles} when is_map(styles) -> {"styles", Map.new(styles, &tag_style/1)}
      other -> other
    end)
  end

  defp tag_anchors({name, anchors}) when is_list(anchors), do: {name, Enum.map(anchors, &tag/1)}
  defp tag_anchors(other), do: other

  defp tag_entry({name, value}), do: {name, tag(value)}

  defp tag_style({name, entry}), do: {name, paints(entry)}

  # A style entry's node, or each node of a list; a name in a list is no color.
  defp paints(entries) when is_list(entries), do: Enum.map(entries, &paints/1)

  defp paints(node) when is_map(node) do
    Map.new(node, fn
      {part, %{"color" => c} = paint} when part in ["fill", "stroke"] ->
        {part, %{paint | "color" => tag(c)}}

      other ->
        other
    end)
  end

  defp paints(other), do: other

  # A color's version 1 form at version 2: text a literal's `$rgb`, and a tag's operands
  # and pinned steps each tagged in turn.
  defp tag(text) when is_binary(text) do
    case Color.parse(text) do
      %Color{} = literal ->
        {:ok, form} = ColorForm.encode_value(literal)
        form

      nil ->
        text
    end
  end

  defp tag(%{"$steps" => pairs}) when is_list(pairs),
    do: %{"$steps" => Enum.map(pairs, &tag_step/1)}

  defp tag(%{"$blend" => list}) when is_list(list), do: %{"$blend" => Enum.map(list, &tag/1)}
  defp tag(%{"$contrast" => "under"} = under), do: under
  defp tag(%{"$contrast" => c}), do: %{"$contrast" => tag(c)}

  defp tag(%{} = form) when map_size(form) == 1 do
    case Map.to_list(form) do
      [{op, [c, t]}] when op in @op_keys -> %{op => [tag(c), t]}
      _other -> form
    end
  end

  defp tag(other), do: other

  defp tag_step([n, c]), do: [n, tag(c)]
  defp tag_step(other), do: other

  @doc false
  # The envelope, as a value: a theme, as a node or a name, and nothing else. The node is
  # judged when the theme is built.
  @impl Document
  def validate(value) when is_map(value) and not is_struct(value) do
    unknown = Document.unknown_keys(value, [:theme])
    theme = if Map.has_key?(value, :theme), do: [], else: [{[:theme], :required}]

    case unknown ++ theme do
      [] -> :ok
      faults -> {:error, Fault.sort(faults)}
    end
  end

  @impl Form
  def tags, do: Macaw.Layers.Theme.Tags
  @impl Form
  def keys, do: Words.keys()
  @impl Form
  def atoms, do: Words.atoms()

  @impl Form
  def encode_value(%Var{} = var), do: Fragment.encode_value(__MODULE__, var)
  def encode_value(term), do: ColorForm.encode_value(term)

  @impl Form
  def decode_value("$var", payload), do: Fragment.decode_value(__MODULE__, "$var", payload)
  def decode_value(tag, payload), do: ColorForm.decode_value(tag, payload)

  @impl Form
  def name_map?(path), do: Fragment.name_map?(__MODULE__, path)

  @impl Fragment
  def root, do: :theme_document

  @impl Fragment
  def key(:theme_document, :theme), do: %{merge: :override, node: :theme}
  def key(:theme_document, :version), do: %{merge: :override}
  def key(:theme, key) when key in @unions, do: %{merge: :union}
  def key(:theme, key), do: if(key in Words.fields(), do: %{merge: :override})
  def key(_kind, _key), do: nil

  @impl Fragment
  def kinds, do: [:theme]

  @impl Fragment
  def wrapper(:theme), do: :theme
  def wrapper(_key), do: nil

  @impl Fragment
  def place(:theme, contribution, _key), do: {:ok, contribution}
end
