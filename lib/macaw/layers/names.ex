defmodule Macaw.Layers.Names do
  @moduledoc """
  Names a document declares (spec/01 §1): a source, a field, a variable, a frame, a style,
  a fragment's key.

  A name is a string. Elixir input may spell one as an atom, which is read as the string
  of the same spelling with `Atom.to_string/1`, which makes no atom; and a category value is
  matched by spelling, so `:ok` and `"ok"` are one value. Nothing here makes an atom from
  a document's data.

  Ported from visualize's `Visualize.Chart.Names`.
  """

  @not_names [nil, true, false]

  @doc "A name in a guard: a string, or an atom other than `nil`, `true` and `false`."
  defguard is_name(v) when is_binary(v) or (is_atom(v) and v not in [nil, true, false])

  @doc """
  A name as a document holds it: an atom's spelling, a string as it is, and anything else
  (a library id `{kind, n}`, a malformed value a validator names) untouched.

      iex> Macaw.Layers.Names.name(:sales)
      "sales"
      iex> Macaw.Layers.Names.name({:id, 1})
      {:id, 1}
  """
  @spec name(term()) :: term()
  def name(name) when is_atom(name) and name not in @not_names, do: Atom.to_string(name)
  def name(name), do: name

  @doc "Whether a value is a name: a non-empty string, or an atom `name/1` reads as one."
  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name), do: name != ""
  def name?(name) when is_atom(name), do: name not in @not_names
  def name?(_name), do: false

  @doc """
  A category value as it is compared: an atom other than `nil`, `true` and `false` by its
  spelling, anything else as it is.
  """
  @spec category(term()) :: term()
  def category(value) when is_atom(value) and value not in @not_names, do: Atom.to_string(value)
  def category(value), do: value

  @doc "Whether two category values are one: equal, or the same spelling."
  @spec same?(term(), term()) :: boolean()
  def same?(a, a), do: true
  def same?(a, b), do: category(a) == category(b)

  @doc "A plain map's keys as names, values untouched; a struct or a non-map as it is."
  @spec keys(term()) :: term()
  def keys(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {name(k), v} end)

  def keys(other), do: other

  @doc """
  The key of `map` that spells `name`: the name itself, or the key of the other spelling.

  How a document's name finds a host's entry, keyed as the host keyed it (a source in a
  pool, a variable's value), without an atom made.
  """
  @spec key(map(), term()) :: {:ok, term()} | :error
  def key(map, name) when is_map_key(map, name), do: {:ok, name}

  def key(map, name) when is_binary(name) or is_atom(name) do
    spelled = category(name)

    case Enum.find(Map.keys(map), &((is_atom(&1) and category(&1) == spelled) or &1 == spelled)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  def key(_map, _name), do: :error

  @doc "`Map.fetch/2` by spelling, through `key/2`."
  @spec fetch(map(), term()) :: {:ok, term()} | :error
  def fetch(map, name) do
    case key(map, name) do
      {:ok, found} -> Map.fetch(map, found)
      :error -> :error
    end
  end
end
