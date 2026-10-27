defmodule Macaw.Layers.Theme.Words do
  @moduledoc false
  # The library's vocabulary in a theme (spec/04 §2, §5): the atoms a theme's keys and
  # values may be. A theme document reads these by spelling and makes no other atom; a name
  # outside them, a host's or an extension's, is held by its string and matched by spelling.

  alias Macaw.Layers.{Theme, Vocabulary}
  alias Macaw.Layers.Theme.Palette

  @fields [:name, :series, :axis, :grid, :text, :background, :surface, :ramps, :colors, :styles] ++
            [:defaults, :font_family, :font_size, :label_size, :title_size, :dark, :light]
  @parts [:fill, :stroke, :font, :text, :effect, :marker, :curve, :opacity, :blend, :class]
  @part_keys [:type, :color, :width, :dash, :cap, :join, :placement, :opacity, :shape, :size] ++
               [:family, :weight, :style, :pattern, :angle, :spacing, :radius, :offset, :blur]

  # Every atom a built-in palette entry holds, read off the entries so the two cannot drift.
  @palette_atoms for palette <- [Palette.builtin(), Palette.print()],
                     {_name, entry} <- palette,
                     {_part, node} <- entry,
                     is_map(node),
                     {_key, value} <- node,
                     is_atom(value) and value not in [nil, true, false],
                     uniq: true,
                     do: value
  @values [:solid, :none, :hatch, :normal, :butt, :square, :miter, :bevel, :inside, :outside] ++
            [:center, :medium, :bold, :italic, :round, :lines, :crosshatch, :dots, :cue]

  @keys Enum.uniq(
          [:theme, :extends] ++
            @fields ++
            @parts ++
            @part_keys ++
            Theme.ramp_names() ++
            Theme.library_color_names() ++
            Palette.fixed_names() ++ Palette.series(Palette.builtin())
        )
  @atoms Enum.uniq(
           @palette_atoms ++
             @values ++
             Theme.builtins() ++
             Theme.size_slots() ++
             [:font_family] ++ Palette.fixed_names() ++ Palette.series(Palette.builtin())
         )

  @key_table Vocabulary.table(@keys)
  @atom_table Vocabulary.table(@atoms)
  @key_set Map.new(@keys, &{&1, true})
  @atom_set Map.new(@atoms, &{&1, true})

  @doc false
  @spec fields() :: [atom(), ...]
  def fields, do: @fields

  @doc false
  @spec keys() :: Vocabulary.table()
  def keys, do: @key_table

  @doc false
  @spec atoms() :: Vocabulary.table()
  def atoms, do: @atom_table

  @doc false
  @spec key?(atom()) :: boolean()
  def key?(atom), do: Map.has_key?(@key_set, atom)

  @doc false
  @spec atom?(atom()) :: boolean()
  def atom?(atom), do: Map.has_key?(@atom_set, atom)
end
