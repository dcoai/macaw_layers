defmodule Macaw.Layers.Theme.Words do
  @moduledoc false
  # The library's vocabulary in a theme document (spec/04 §5, spec/01 §5): the keys and the
  # atom values its JSON form may spell, the fields, the style parts and their keys, the
  # built-in palette's values. The JSON reader makes no other atom; a registered extension
  # adds its own words (`Extension.words/0`). Words are
  # not names: a theme's names are strings, and read as the strings they are.

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

  @keys Enum.uniq([:theme, :extends] ++ @fields ++ @parts ++ @part_keys)
  @atoms Enum.uniq(@palette_atoms ++ @values ++ Theme.size_slots() ++ [:font_family])

  @key_table Vocabulary.table(@keys)
  @atom_table Vocabulary.table(@atoms)

  @doc false
  @spec fields() :: [atom(), ...]
  def fields, do: @fields

  @doc false
  @spec keys() :: Vocabulary.table()
  def keys, do: @key_table

  @doc false
  @spec atoms() :: Vocabulary.table()
  def atoms, do: @atom_table
end
