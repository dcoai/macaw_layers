defmodule Macaw.Layers.Theme.Extension do
  @moduledoc """
  What an adopter registers beyond the library's vocabulary (spec/04 §3.4), so one theme
  styles it: palette names in a group of the palette, and names of the color table, each
  with its default.

      defmodule MyApp.Marks do
        @behaviour Macaw.Layers.Theme.Extension
        def name, do: "marks"
        def styles, do: %{lane: {:furniture, %{stroke: %{type: :solid, color: {:color, :lane}}}}}
        def colors, do: %{lane: "#8a8f99"}
      end

      Macaw.Layers.Theme.new(extensions: [MyApp.Marks])

  A theme carries its extensions in `extensions`, given explicitly and **default closed**:
  a palette or color name that neither the library nor an extension has is a fault naming
  it. The names an extension adds are held to the contracts of their group, its default
  entries included. Two extensions adding one name, or an extension adding a library name,
  raise `ArgumentError` naming both.
  """

  @typedoc "A group of the palette an extension's style joins."
  @type group :: :state | :furniture | :modifier

  @doc "The extension's name, for faults."
  @callback name() :: String.t()
  @doc "The palette names it adds, each in a group with its default entry."
  @callback styles() :: %{atom() => {group(), map() | list()}}
  @doc "The names it adds to the color table, each with its default value."
  @callback colors() :: %{atom() => term()}

  @groups [:state, :furniture, :modifier]

  @doc false
  # The extensions, checked: each a module of this behavior whose names are its own. Raises
  # `ArgumentError` naming the two that add one name, or the library's name an extension adds.
  @spec check!([module()], [atom()], [atom()]) :: [module()]
  def check!(extensions, library_styles, library_colors) when is_list(extensions) do
    Enum.each(extensions, &Code.ensure_loaded!/1)

    for ext <- extensions, {name, {group, _entry}} <- ext.styles(), group not in @groups do
      raise ArgumentError,
            "extension #{inspect(ext.name())}: style #{inspect(name)} names the group " <>
              "#{inspect(group)}; an extension's style is a #{Enum.map_join(@groups, ", ", &inspect/1)}"
    end

    owners(extensions, :styles, library_styles)
    owners(extensions, :colors, library_colors)
    extensions
  end

  defp owners(extensions, kind, library) do
    Enum.reduce(extensions, %{}, fn ext, seen ->
      ext
      |> apply(kind, [])
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
  # Every style the extensions add, `name => {group, entry}`.
  @spec styles([module()]) :: %{atom() => {group(), map() | list()}}
  def styles(extensions), do: Enum.reduce(extensions, %{}, &Map.merge(&2, &1.styles()))

  @doc false
  # Every color the extensions add, `name => value`.
  @spec colors([module()]) :: %{atom() => term()}
  def colors(extensions), do: Enum.reduce(extensions, %{}, &Map.merge(&2, &1.colors()))
end
