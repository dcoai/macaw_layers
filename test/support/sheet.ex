defmodule Macaw.Layers.Test.Sheet do
  @moduledoc false
  # A fragment type with the cascade's hooks (spec/02 §3.3), standing in for visualize's
  # style parts: a style's `stroke` and `fill` are paints, written either as a shorthand
  # color or as a part `%{type, color, width, …}`. The shorthand normalizes to a solid part
  # when the other layer gives a part, and a paint whose type changes keeps of the lower
  # only `width`, which no type decides, and the keys its own type takes.
  @behaviour Macaw.Layers.Fragment

  @keys %{
    sheet: %{style: %{merge: :override, node: :style}, styles: %{merge: :deep, element: :style}},
    style: %{
      stroke: %{merge: :override, node: :paint},
      fill: %{merge: :override, node: :paint},
      opacity: %{merge: :override}
    }
  }

  # The keys each paint type takes; `width` is decided by none.
  @takes %{solid: [:color], dashed: [:color, :dash], gradient: [:from, :to, :angle]}

  def root, do: :sheet
  def key(kind, key), do: @keys |> Map.get(kind, %{}) |> Map.get(key)
  def kinds, do: [:sheet, :style, :paint]
  def wrapper(_key), do: nil
  def place(_kind, contribution, _key), do: {:ok, contribution}

  def normalize(:style, k, lower, higher) when k in [:stroke, :fill] do
    if is_map(lower) == is_map(higher), do: {lower, higher}, else: {part(lower), part(higher)}
  end

  def normalize(_kind, _key, lower, higher), do: {lower, higher}

  def under(:paint, %{type: type}), do: [:type, :width | Map.get(@takes, type, [])]
  def under(_kind, _higher), do: :all

  defp part(color) when is_binary(color), do: %{type: :solid, color: color}
  defp part(part), do: part
end
