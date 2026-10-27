defmodule Macaw.Layers.Theme.Names do
  @moduledoc false
  # A theme's names as a document reads them (spec/04 §2.1, §2.2): its own name and its
  # counterparts are a built-in theme's atom or the string of the host's, and a color it adds
  # is the string of its name, the library's own names staying atoms, so a theme built in
  # Elixir and the theme its document reads are one value. `Atom.to_string/1` makes no atom.
  #
  # Ported from visualize's `Visualize.Theme.Names`.

  alias Macaw.Layers.Theme
  alias Macaw.Layers.Theme.Words

  @library_names Map.new(Theme.library_color_names(), &{&1, true})
  @ops [:intensity, :alpha, :lighten, :darken, :saturate, :shade]

  @doc false
  # The fields given to `Macaw.Layers.Theme.new/1` or `merge/2` with their theme names read.
  @spec fields(map()) :: map()
  def fields(fields) do
    Enum.reduce([:name, :dark, :light], fields, fn key, fields ->
      case fields do
        %{^key => name} -> %{fields | key => theme_name(name)}
        %{} -> fields
      end
    end)
  end

  @doc false
  # The colors a theme adds, keyed by their names as a document reads them, each value a
  # color whose names are read the same way.
  @spec colors(term()) :: term()
  def colors(colors) when is_map(colors) or is_list(colors) do
    Map.new(colors, fn {name, value} -> {own_name(name), value(value)} end)
  end

  def colors(other), do: other

  @doc false
  # A color value with every name in it read as a document reads it.
  @spec value(term()) :: term()
  def value({:color, name}), do: {:color, own_name(name)}
  def value({op, c, t}) when op in @ops, do: {op, value(c), t}
  def value({:blend, list}) when is_list(list), do: {:blend, Enum.map(list, &value/1)}
  def value({:contrast, :under} = ink), do: ink
  def value({:contrast, c}), do: {:contrast, value(c)}
  def value(other), do: other

  @doc false
  # A theme's palette entries with every key and atom outside the library's vocabulary
  # (`Macaw.Layers.Theme.Words`) held by its string, `palette` the names a list entry may
  # still name by atom: the library's and the extensions'.
  @spec styles(map(), [atom()]) :: map()
  def styles(styles, palette) when is_map(styles),
    do: Map.new(styles, fn {name, entry} -> {name, node(entry, palette)} end)

  @doc false
  # A theme's root defaults read the same way.
  @spec defaults(map()) :: map()
  def defaults(defaults) when is_map(defaults), do: node(defaults, [])

  defp node(%_{} = struct, _keep), do: struct

  defp node(map, keep) when is_map(map) do
    Map.new(map, fn {k, v} -> {word(k, &Words.key?/1, keep), node(v, keep)} end)
  end

  defp node(list, keep) when is_list(list), do: Enum.map(list, &node(&1, keep))
  defp node(tuple, _keep) when is_tuple(tuple), do: value(tuple)
  defp node(atom, keep) when is_atom(atom), do: word(atom, &Words.atom?/1, keep)
  defp node(leaf, _keep), do: leaf

  defp word(atom, known?, keep) when is_atom(atom) and atom not in [nil, true, false] do
    if known?.(atom) or atom in keep, do: atom, else: Atom.to_string(atom)
  end

  defp word(other, _known?, _keep), do: other

  defp theme_name(name) when is_atom(name) and name not in [nil, true, false],
    do: if(name in Theme.builtins(), do: name, else: Atom.to_string(name))

  defp theme_name(name), do: name

  defp own_name(name) when is_atom(name) and name not in [nil, true, false],
    do: if(Map.has_key?(@library_names, name), do: name, else: Atom.to_string(name))

  defp own_name(name), do: name
end
