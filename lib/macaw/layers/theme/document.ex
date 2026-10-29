defmodule Macaw.Layers.Theme.Tags do
  @moduledoc false
  # The tag table of a theme document (spec/01 §6): the color tags and `$var`, read so a
  # variable is refused by name rather than as an unknown tag.
  use Macaw.Layers.Tags,
    live:
      ~w($var $color $series $ramp $blend $contrast $steps) ++
        ~w($intensity $alpha $lighten $darken $saturate $shade)
end

defmodule Macaw.Layers.Theme.Document do
  @moduledoc """
  A theme as a document (spec/04 §5): stored and shipped as a value, and judged as one.

    * the value is `%{version: v, theme: node}` (`to_map/1`), and a store's fragment
      `%{theme: node}` (`fragment/1`), a library entry of kind `:theme`, reads as the same
      document;
    * the JSON form is `{"$version": v, "theme": {…}}` (`to_json/1`), each color value a tag
      (`$color`, `$series`, `$ramp`, the transforms by name, `$blend`, `$contrast`) and
      pinned steps `$steps`, written and read by the JSON adapter (`Macaw.Layers.Form`).

  `from_map/2` judges the value as terms, after the version check, with no form written
  or read; `from_json/2` reads the JSON form through the adapter's gates (spec/01 §5: the
  limits, the version, the migration) to the same value. Then: a node that is a **name**
  reads as the built-in theme of that name, any other name is `{:unknown_theme, name}`; a
  variable anywhere is `{:unresolved, :var, name}`, since nothing applies a theme; a key
  the theme does not have is `:unknown_key`; and every contract a ramp, color or palette
  entry breaks is `{:contract, message}` at `[:theme, :ramps | :colors | :styles, name]`.

  As a fragment type (spec/02 §1), `ramps`, `colors`, `styles` and `defaults` are `:union`
  name maps and every other key `:override`, so a theme document stacks over a built-in as
  `Macaw.Layers.Theme.new/1` merges.

      iex> theme = Macaw.Layers.Theme.new(name: :house, axis: "#555555")
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

  alias Macaw.Layers.{Document, Fault, Form, Fragment, Theme, Var, Version}
  alias Macaw.Layers.Color.Form, as: ColorForm
  alias Macaw.Layers.Theme.{Palette, Words}

  @unions [:ramps, :colors, :styles, :defaults]
  @furniture [:axis, :grid, :text, :background, :surface]
  # A style series name a document spells beyond the built-in ten: a bounded set.
  @style_series Macaw.Layers.Theme.Slots.max()

  # -- the document ------------------------------------------------------------------------

  @doc """
  The theme as its node: every field but `extensions`, an unset counterpart and empty
  defaults left out, and a palette name outside the library's vocabulary (an extension's)
  spelled as its string, which a reader given the extension reads back as its name.
  """
  @spec node(Theme.t()) :: map()
  def node(%Theme{} = theme) do
    theme
    |> Map.take(Words.fields())
    |> Map.reject(fn {k, v} ->
      (k in [:dark, :light] and v == nil) or (k == :defaults and v == %{})
    end)
    |> Map.update!(:styles, &Map.new(&1, fn {name, entry} -> {spelled(name), entry} end))
  end

  defp spelled(name) when is_atom(name),
    do: if(Words.key?(name), do: name, else: Atom.to_string(name))

  defp spelled(name), do: name

  @doc "`%{theme: node}`: a store's fragment of kind `:theme`."
  @spec fragment(Theme.t()) :: %{theme: map()}
  def fragment(%Theme{} = theme), do: %{theme: node(theme)}

  @doc "`%{version: current, theme: node}`."
  @spec to_map(Theme.t()) :: %{version: pos_integer(), theme: map()}
  def to_map(%Theme{} = theme), do: %{version: current(), theme: node(theme)}

  @doc "The JSON document, `{:ok, json}`, stamped `\"$version\"`."
  @spec to_json(Theme.t()) :: {:ok, String.t()} | {:error, [Fault.t(), ...]}
  def to_json(%Theme{} = theme), do: Form.to_json(fragment(theme), __MODULE__)

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
  `Macaw.Layers.Form.gates/3` takes them, and `extensions:` as `from_map/2`.
  """
  @spec from_json(String.t(), keyword()) :: {:ok, Theme.t()} | {:error, [Fault.t(), ...]}
  def from_json(json, opts \\ []) when is_binary(json) do
    with {:ok, %{theme: node}} <- Form.read(json, __MODULE__, Keyword.take(opts, [:limits])),
         do: build(node, Keyword.get(opts, :extensions, []))
  end

  # -- the theme ---------------------------------------------------------------------------

  defp build(name, _extensions) when is_atom(name) or is_binary(name) do
    case Theme.builtin(name) do
      nil -> {:error, [{[:theme], {:unknown_theme, to_string(name)}}]}
      theme -> {:ok, theme}
    end
  end

  defp build(node, extensions) when is_map(node) do
    node = palette_names(node, extensions)

    with :ok <- faults(variables(node, [:theme])),
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

  # A style name a document spells, read as the palette's: a style series by its index, an
  # extension's name by its spelling.
  defp palette_names(%{styles: styles} = node, extensions) when is_map(styles) do
    extra = Theme.extra_styles(%Theme{extensions: extensions}) |> Map.keys()

    styles =
      Map.new(styles, fn
        {name, entry} when is_binary(name) -> {palette_name(name, extra), entry}
        other -> other
      end)

    %{node | styles: styles}
  end

  defp palette_names(node, _extensions), do: node

  defp palette_name(name, extra) do
    with "style_" <> digits <- name,
         {k, ""} when k >= 1 and k <= @style_series <- Integer.parse(digits) do
      Palette.series_name(k)
    else
      _ -> Enum.find(extra, name, &(Atom.to_string(&1) == name))
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

  defp field(:series, series) when is_list(series) and length(series) > @style_series,
    do: [{[:theme, :series], {:limit, :series, @style_series, length(series)}}]

  defp field(:series, [_ | _] = series) do
    for {c, i} <- Enum.with_index(series),
        not is_binary(c),
        do: {[:theme, :series, i], {:type, :string}}
  end

  defp field(:series, _other), do: [{[:theme, :series], {:type, :colors}}]
  defp field(key, value) when key in @furniture and is_binary(value), do: []
  defp field(key, _value) when key in @furniture, do: [{[:theme, key], {:type, :string}}]
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
  def current, do: 1

  # The line is at its first version, so no step exists yet.
  @impl Version
  def step(document, _from), do: {:ok, document}

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
