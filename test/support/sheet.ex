defmodule Macaw.Layers.Test.Sheet do
  @moduledoc false
  # A fragment type with the cascade's hooks (spec/02 §3.3), standing in for visualize's
  # style parts: a style's `stroke` and `fill` are paints, written either as a shorthand
  # color or as a part `%{type, color, width, …}`. The shorthand normalizes to a solid part
  # when the other layer gives a part, and a paint whose type changes keeps of the lower
  # only `width`, which no type decides (visualize's `Parts.under/3`).
  @behaviour Macaw.Layers.Fragment

  @keys %{
    sheet: %{style: %{merge: :override, node: :style}, styles: %{merge: :deep, element: :style}},
    style: %{
      stroke: %{merge: :override, node: :paint},
      fill: %{merge: :override, node: :paint},
      opacity: %{merge: :override}
    }
  }

  def root, do: :sheet
  def key(kind, key), do: @keys |> Map.get(kind, %{}) |> Map.get(key)
  def kinds, do: [:sheet, :style, :paint]
  def wrapper(_key), do: nil
  def place(_kind, contribution, _key), do: {:ok, contribution}

  def normalize(:style, k, lower, higher) when k in [:stroke, :fill] do
    if is_map(lower) == is_map(higher), do: {lower, higher}, else: {part(lower), part(higher)}
  end

  def normalize(_kind, _key, lower, higher), do: {lower, higher}

  def under(:paint, %{type: t1} = lower, %{type: t2}) when t1 != t2, do: Map.take(lower, [:width])
  def under(_kind, lower, _higher), do: lower

  defp part(color) when is_binary(color), do: %{type: :solid, color: color}
  defp part(part), do: part
end
