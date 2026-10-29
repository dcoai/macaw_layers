defmodule Macaw.Layers.Theme.Style do
  @moduledoc """
  A style node as a fragment type (spec/04 §2.4, spec/02 §1): how the palette stacks one
  style over another. The root is `:style`, and every key of it is a part,
  `%{merge: :override, node: :part}`, so a part both nodes give as a map merges key by
  key, the higher's word at each key, and anything else is the higher's. A part's own keys
  are unknown to the type, each taken whole.

  A list entry of the palette is `Macaw.Layers.Fragment.stack/2` of its layers, a left
  fold. This type has no hooks; an adopter whose style grammar has its own rules gives a
  style type with its own `normalize/4` and `under/3` through
  `Macaw.Layers.Theme.Extension.style_type/0` (spec/04 §3.4), and the palette stacks with
  it in `Macaw.Layers.Theme.style/2`, its list entries and its contracts alike.

      iex> Macaw.Layers.Fragment.stack(Macaw.Layers.Theme.Style, [
      ...>   %{stroke: %{type: :solid, width: 1.5}, opacity: 0.5},
      ...>   %{stroke: %{width: 3}}
      ...> ])
      %{stroke: %{type: :solid, width: 3}, opacity: 0.5}
  """

  @behaviour Macaw.Layers.Fragment

  alias Macaw.Layers.Fragment

  @impl Fragment
  def root, do: :style

  @impl Fragment
  def key(:style, _part), do: %{merge: :override, node: :part}
  def key(_kind, _key), do: nil

  @impl Fragment
  def kinds, do: [:style, :part]

  @impl Fragment
  def wrapper(_key), do: nil

  @impl Fragment
  def place(_kind, contribution, _key), do: {:ok, contribution}
end
