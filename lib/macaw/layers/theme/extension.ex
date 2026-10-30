defmodule Macaw.Layers.Theme.Extension do
  @moduledoc """
  What an adopter registers beyond the library's vocabulary (spec/04 §3.4), so one theme
  styles it: palette names in a group of the palette, and names of the color table, each
  with its default, and the words its styles and defaults use, for the theme's JSON reader.

      defmodule MyApp.Marks do
        @behaviour Macaw.Layers.Theme.Extension
        def name, do: "marks"
        def styles, do: %{lane: {:furniture, %{stroke: %{type: :solid, color: {:color, :lane}}}}}
        def colors, do: %{lane: Macaw.Layers.Color.parse!("#8a8f99")}
        def words, do: %{keys: [:curve_kind], atoms: [:monotone_x]}
      end

      Macaw.Layers.Theme.new(extensions: [MyApp.Marks])

  A name is a string inside a theme, an extension's as the library's (spec/04 §2.1): the
  names `styles/0` and `colors/0` give, and the names in their entries' typed colors, are
  read as their strings, so `:lane` and `"lane"` are one name; giving one both ways in one
  map raises `ArgumentError` naming the extension.

  `words/0`, optional, is the vocabulary its styles and defaults use beyond the library's:
  the keys and the atom values a theme document's JSON form may spell (spec/01 §5). A theme
  built in Elixir keeps every word as given; the JSON reader makes an atom of a word only
  from the library's tables and the registered extensions' `words/0`
  (`Macaw.Layers.Theme.Document.from_json/2`'s `extensions:`), so no atom is made from a
  document.

  `style_type/0`, optional, is the adopter's style type: a fragment type of a style node
  (`Macaw.Layers.Fragment`, as `Macaw.Layers.Theme.Style` is) with its own hooks,
  `normalize/4` and `under/3` (spec/02 §3.3), with which the theme stacks its palette
  entries in place of `Macaw.Layers.Theme.Style`, in `style/2`, its list entries and its
  contracts alike. At most one of a theme's extensions gives one; two raise
  `ArgumentError` naming both.

  A theme carries its extensions in `extensions`, given explicitly and **default closed**:
  a palette or color name that neither the library nor an extension has is a fault naming
  it. The names an extension adds are held to the contracts of their group, its default
  entries included. Two extensions adding one name, or an extension adding a library name,
  raise `ArgumentError` naming both. A color an extension adds is a color value, a literal
  `%Macaw.Layers.Color{}` or a typed color; text raises `ArgumentError` naming the
  extension, since a string is never a color.
  """

  @typedoc "A group of the palette an extension's style joins."
  @type group :: :state | :furniture | :modifier

  @doc "The extension's name, for faults."
  @callback name() :: String.t()
  @doc "The palette names it adds, each in a group with its default entry."
  @callback styles() :: %{(atom() | String.t()) => {group(), map() | list()}}
  @doc "The names it adds to the color table, each with its default value: a color value."
  @callback colors() :: %{(atom() | String.t()) => Macaw.Layers.Color.value() | map()}
  @doc """
  The words its styles and defaults use beyond the library's: the keys, and the atom
  values, a theme document's JSON form may spell.
  """
  @callback words() :: %{optional(:keys) => [atom()], optional(:atoms) => [atom()]}
  @doc """
  The style type the theme stacks its palette entries with: a fragment type of a style
  node with the adopter's own hooks (spec/02 §3.3).
  """
  @callback style_type() :: module()
  @optional_callbacks words: 0, style_type: 0

  alias Macaw.Layers.Callback
  alias Macaw.Layers.Theme.Names

  @groups [:state, :furniture, :modifier]

  @doc false
  # The extensions, checked: each a module of this behavior whose names are its own. Raises
  # `ArgumentError` naming the two that add one name, or the library's name an extension adds.
  @spec check!([module()], [String.t()], [String.t()]) :: [module()]
  def check!(extensions, library_styles, library_colors) when is_list(extensions) do
    Enum.each(extensions, &Code.ensure_loaded!/1)

    for ext <- extensions, {name, {group, _entry}} <- names(ext, :styles), group not in @groups do
      raise ArgumentError,
            "extension #{inspect(ext.name())}: style #{inspect(name)} names the group " <>
              "#{inspect(group)}; an extension's style is a #{Enum.map_join(@groups, ", ", &inspect/1)}"
    end

    for ext <- extensions, {name, value} <- names(ext, :colors), not color?(value) do
      raise ArgumentError,
            "extension #{inspect(ext.name())}: color #{inspect(name)} " <>
              if(is_binary(value),
                do: Macaw.Layers.Color.Typed.text_hint(value),
                else: "is not a color value, got #{inspect(value)}"
              )
    end

    for ext <- extensions, not words?(own_words(ext)) do
      raise ArgumentError,
            "extension #{inspect(ext.name())}: words/0 is %{keys: [atom], atoms: [atom]}, " <>
              "got #{inspect(own_words(ext))}"
    end

    owners(extensions, :styles, library_styles)
    owners(extensions, :colors, library_colors)
    style_type!(extensions)
    extensions
  end

  # At most one extension gives the style type, and it is a fragment type.
  defp style_type!(extensions) do
    case Enum.filter(extensions, &Callback.exported?(&1, :style_type, 0)) do
      [] ->
        :ok

      [ext] ->
        type = ext.style_type()

        if not (is_atom(type) and Callback.exported?(type, :root, 0) and
                  Callback.exported?(type, :key, 2)) do
          raise ArgumentError,
                "extension #{inspect(ext.name())}: style_type/0 is a fragment type " <>
                  "(Macaw.Layers.Fragment), got #{inspect(type)}"
        end

      [a, b | _] ->
        raise ArgumentError,
              "extensions #{inspect(a.name())} and #{inspect(b.name())} both give a " <>
                "style type; a theme stacks its palette with one"
    end
  end

  defp words?(%{} = words) when not is_struct(words) do
    Enum.all?(words, fn {k, v} ->
      k in [:keys, :atoms] and is_list(v) and
        Enum.all?(v, &(is_atom(&1) and &1 not in [nil, true, false]))
    end)
  end

  defp words?(_other), do: false

  # A default is a color value, or a literal's pinned steps (spec/04 §2.2).
  defp color?(%{} = steps) when not is_struct(steps),
    do: Enum.all?(steps, fn {n, c} -> is_integer(n) and Macaw.Layers.Color.literal?(c) end)

  defp color?(value), do: Macaw.Layers.Color.value?(value)

  defp owners(extensions, kind, library) do
    Enum.reduce(extensions, %{}, fn ext, seen ->
      ext
      |> names(kind)
      |> Map.keys()
      |> Enum.reduce(seen, fn name, seen ->
        cond do
          name in library ->
            raise ArgumentError,
                  "extension #{inspect(ext.name())} adds the #{singular(kind)} #{inspect(name)}, " <>
                    "which the library already names"

          Map.has_key?(seen, name) ->
            raise ArgumentError,
                  "extensions #{inspect(seen[name].name())} and #{inspect(ext.name())} both add " <>
                    "the #{singular(kind)} #{inspect(name)}"

          true ->
            Map.put(seen, name, ext)
        end
      end)
    end)
  end

  defp singular(:styles), do: "style"
  defp singular(:colors), do: "color"

  @doc false
  # Every style the extensions add, `name => {group, entry}`, each name a string and each
  # entry's names too.
  @spec styles([module()]) :: %{String.t() => {group(), map() | list()}}
  def styles(extensions), do: Enum.reduce(extensions, %{}, &Map.merge(&2, names(&1, :styles)))

  @doc false
  # Every color the extensions add, `name => value`, each name a string and each value's
  # names too.
  @spec colors([module()]) :: %{String.t() => term()}
  def colors(extensions), do: Enum.reduce(extensions, %{}, &Map.merge(&2, names(&1, :colors)))

  @doc """
  The words the extensions' styles and defaults use, as the JSON reader's vocabulary
  (`Macaw.Layers.Form.read/3`'s `vocabulary:`): what a host gives a bundle holding
  themes, `Macaw.Layers.Bundle.from_json(json, types, vocabularies: %{Theme.Document =>
  words(extensions)})`, as `Macaw.Layers.Theme.Document.from_json/2` does from
  `extensions:`.
  """
  @spec words([module()]) :: %{keys: [atom()], atoms: [atom()]}
  def words(extensions) do
    Enum.reduce(extensions, %{keys: [], atoms: []}, fn ext, acc ->
      words = own_words(ext)

      %{
        keys: Enum.uniq(acc.keys ++ Map.get(words, :keys, [])),
        atoms: Enum.uniq(acc.atoms ++ Map.get(words, :atoms, []))
      }
    end)
  end

  @doc false
  # The style type the palette stacks with: the one an extension gives, else the library's.
  @spec style_type([module()]) :: module()
  def style_type(extensions) do
    case Enum.find(extensions, &Callback.exported?(&1, :style_type, 0)) do
      nil -> Macaw.Layers.Theme.Style
      ext -> ext.style_type()
    end
  end

  defp own_words(ext),
    do: if(Callback.exported?(ext, :words, 0), do: ext.words(), else: %{})

  defp style_entry({group, entry}), do: {group, Names.entry(:styles, entry)}
  defp style_entry(other), do: other

  # An extension's names, read as a theme holds them, by the theme's one normalization; a
  # name given both ways in one map raises naming the extension.
  defp names(ext, kind) do
    entry =
      case kind do
        :styles -> &style_entry/1
        :colors -> &Names.entry(:colors, &1)
      end

    case Names.name_map(apply(ext, kind, []), entry) do
      {:ok, names} ->
        names

      {:duplicate, name} ->
        raise ArgumentError,
              "extension #{inspect(ext.name())}: #{kind} gives #{inspect(name)} both as an " <>
                "atom and as a string; a theme's names are strings, so the two are one name"
    end
  end
end
