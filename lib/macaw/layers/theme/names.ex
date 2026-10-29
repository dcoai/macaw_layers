defmodule Macaw.Layers.Theme.Names do
  @moduledoc false
  # A theme's names, normalized once (spec/04 §2.1, §2.2): every name inside a theme is a
  # string, the library's, an extension's and a host's alike, so `:info` and `"info"` are
  # one name, the later given winning. `normalize/1` is the one place an atom name becomes
  # its string: the theme's own name and its `dark` and `light`; the keys of the name maps
  # `ramps`, `colors` (and the old `roles`), `styles` and `defaults`; the name in every
  # typed color, `{:color, name}` and `{:ramp, name, t}`, wherever it stands, ramp anchors,
  # color entries, pinned steps, style nodes and defaults alike; a palette name in a list entry; and a bare atom in a paint's color, which is the
  # typed color it names. Words, the keys and atom values of a style node or a default's
  # node, are kept as given. A name given in both spellings in one map is `{:duplicate,
  # path}`. `Atom.to_string/1` makes no atom.
  #
  # Ported from visualize's `Visualize.Theme.Names`.

  alias Macaw.Layers.Color.Typed

  @ops [:intensity, :alpha, :lighten, :darken, :saturate, :shade]
  @name_maps [:ramps, :roles, :colors, :styles, :defaults]

  @doc false
  # The fields given to `Macaw.Layers.Theme.new/1` or `merge/2`, or a theme document's
  # node, with every name a string: `{:ok, fields}`, or `{:duplicate, [field, name]}` for
  # the first name given both as its atom and as its string in one name map.
  @spec normalize(map()) :: {:ok, map()} | {:duplicate, [term(), ...]}
  def normalize(fields) when is_map(fields) do
    @name_maps
    |> Enum.filter(&Map.has_key?(fields, &1))
    |> Enum.reduce_while({:ok, fields}, fn key, {:ok, fields} ->
      case name_map(Map.fetch!(fields, key), &entry(key, &1)) do
        {:ok, names} -> {:cont, {:ok, %{fields | key => names}}}
        {:duplicate, name} -> {:halt, {:duplicate, [key, name]}}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, theme_names(fields)}
      duplicate -> duplicate
    end
  end

  @doc false
  # `normalize/1`, raising `ArgumentError` for a name given in both spellings, naming the
  # theme: the one the fields name, else `name`.
  @spec normalize!(map(), atom() | String.t()) :: map()
  def normalize!(fields, name) do
    case normalize(fields) do
      {:ok, fields} ->
        fields

      {:duplicate, [key, both]} ->
        theme = name(Map.get(fields, :name, name))

        raise ArgumentError,
              "theme #{inspect(theme)}: #{key} gives #{inspect(both)} both as an atom and as " <>
                "a string; a theme's names are strings, so the two are one name: give it once"
    end
  end

  @doc false
  # A map of names to entries, each name its string and each entry read by `entry`:
  # `{:ok, map}`, or `{:duplicate, name}`, the least name given in both spellings. A
  # keyword list is read as its map; anything else is left for its check to refuse.
  @spec name_map(term(), (term() -> term())) :: {:ok, term()} | {:duplicate, String.t()}
  def name_map(names, entry) when is_list(names) do
    if Keyword.keyword?(names), do: name_map(Map.new(names), entry), else: {:ok, names}
  end

  def name_map(names, entry) when is_map(names) and not is_struct(names) do
    case Enum.filter(Map.keys(names), &(name(&1) != &1 and Map.has_key?(names, name(&1)))) do
      [] -> {:ok, Map.new(names, fn {name, value} -> {name(name), entry.(value)} end)}
      both -> {:duplicate, both |> Enum.map(&name/1) |> Enum.min()}
    end
  end

  def name_map(other, _entry), do: {:ok, other}

  @doc false
  # A name as its string: an atom's spelling, a string as it is, anything else untouched,
  # for its check to refuse.
  @spec name(term()) :: term()
  def name(name) when is_atom(name) and name not in [nil, true, false], do: Atom.to_string(name)
  def name(name), do: name

  @doc false
  # A color value with every name in it a string: `{:color, name}`, `{:ramp, name, t}`, and
  # each operand of a transform, a blend and a contrast in turn.
  @spec value(term()) :: term()
  def value({:color, name}), do: {:color, name(name)}
  def value({:ramp, name, t}), do: {:ramp, name(name), t}
  def value({op, c, t}) when op in @ops, do: {op, value(c), t}
  def value({:blend, list}) when is_list(list), do: {:blend, Enum.map(list, &value/1)}
  def value({:contrast, :under} = ink), do: ink
  def value({:contrast, c}), do: {:contrast, value(c)}
  def value(other), do: other

  # A theme's own name and its counterparts, strings as its other names are, a built-in's
  # and a host's alike.
  defp theme_names(fields) do
    Enum.reduce([:name, :dark, :light], fields, fn key, fields ->
      case fields do
        %{^key => name} -> %{fields | key => name(name)}
        %{} -> fields
      end
    end)
  end

  @doc false
  # An entry of the name map `key` with its names as strings: a ramp's anchors, a palette
  # entry, or a color value or its pinned steps.
  @spec entry(atom(), term()) :: term()
  def entry(:ramps, anchors) when is_list(anchors), do: Enum.map(anchors, &value/1)
  def entry(:styles, entry), do: style(entry)
  def entry(:defaults, node), do: words(node)

  def entry(_colors, %{} = steps) when not is_struct(steps),
    do: Map.new(steps, fn {n, c} -> {n, value(c)} end)

  def entry(_key, value), do: value(value)

  # A palette entry: a list's names as strings and its nodes read in turn, a name as its
  # string, a node with its typed colors' names as strings and a bare atom paint color the
  # typed color it names (spec/04 §2.4); `:none` and `:cue` are no color.
  defp style(entries) when is_list(entries), do: Enum.map(entries, &style/1)
  defp style(%_{} = struct), do: struct

  defp style(node) when is_map(node) do
    Map.new(node, fn
      {part, %{color: color} = paint}
      when part in [:fill, :stroke] and is_atom(color) and
             color not in [nil, true, false, :none, :cue] ->
        {part, words(%{paint | color: {:color, name(color)}})}

      {key, value} ->
        {key, words(value)}
    end)
  end

  defp style(name), do: name(name)

  @doc false
  # A node of words, kept as given but for the names in its typed colors.
  @spec words(term()) :: term()
  def words(%_{} = struct), do: struct
  def words(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, words(v)} end)
  def words(list) when is_list(list), do: Enum.map(list, &words/1)

  def words(tuple) when is_tuple(tuple),
    do: if(Typed.value?(tuple), do: value(tuple), else: tuple)

  def words(leaf), do: leaf
end
