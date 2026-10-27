defmodule Macaw.Layers.Test.Design do
  @moduledoc false
  # A fragment type standing in for visualize's design schema (spec/02 §1), so the
  # machinery is tested against the rules it was written for: marks, labels and axes
  # concatenate with identity, sources, styles and vars unite, frames deepen, and a
  # style's `fill` merges by the type's own rule.
  @behaviour Macaw.Layers.Fragment

  @keys %{
    design: %{
      version: %{merge: :override},
      theme: %{merge: :override, node: :theme},
      meta: %{merge: :override, node: :meta},
      sources: %{merge: :union, element: :source},
      styles: %{merge: :union, element: :style},
      vars: %{merge: :union, element: :var},
      frames: %{merge: :deep, element: :frame},
      marks: %{merge: :concat, element: :mark},
      labels: %{merge: :concat, element: :label}
    },
    frame: %{
      kind: %{merge: :override},
      size: %{merge: :override, node: :size},
      margin: %{merge: :override, node: :margin},
      scales: %{merge: :union, element: :scale},
      axes: %{merge: :concat, element: :axis}
    },
    mark: %{
      data: %{merge: :override, node: :data},
      channels: %{merge: :override, node: :channels}
    },
    data: %{transforms: %{merge: :concat, element: :transform}},
    style: %{fill: %{merge: {:type, :parts}}}
  }

  @impl true
  def root, do: :design

  @impl true
  def key(kind, key), do: @keys |> Map.get(kind, %{}) |> Map.get(key)

  @impl true
  def identity(kind, element) when kind in [:mark, :label], do: Map.get(element, :id)
  def identity(:axis, %{scale: scale, side: side}), do: {scale, side}
  def identity(_kind, _element), do: nil

  @impl true
  def kinds, do: [:axis, :composite, :frame, :label, :mark, :scale, :source, :style, :theme, :var]

  @impl true
  def wrapper(key) when key in [:style, :scale, :theme, :mark], do: key
  def wrapper(_key), do: nil

  @impl true
  def place(_kind, _body, _key), do: :keyless

  # A style's fill: the two parts merged key by key when both are maps, else the higher's.
  @impl true
  def merge(:parts, lower, higher) when is_map(lower) and is_map(higher),
    do: Map.merge(lower, higher)

  def merge(:parts, _lower, higher), do: higher
end
