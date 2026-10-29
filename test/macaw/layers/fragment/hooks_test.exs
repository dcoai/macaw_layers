defmodule Macaw.Layers.Fragment.HooksTest do
  # The cascade's hooks (spec/02 §3.3) over a type modeling visualize's style parts:
  # `normalize/4` expands a shorthand against a part, `under/2` trims a node whose type
  # changes, and both hold in stack/2, compose/3 and explain/2 alike.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.Fragment
  alias Macaw.Layers.Test.{Design, Sheet}

  defp style(s), do: %{style: s}

  @tag verifies: "fragments-hooks-normalize"
  test "a shorthand against a part merges as the part, key by key, in stack and compose alike" do
    lower = style(%{stroke: "red", opacity: 0.5})
    higher = style(%{stroke: %{width: 2}})

    assert Fragment.stack(Sheet, lower, higher) ==
             style(%{stroke: %{type: :solid, color: "red", width: 2}, opacity: 0.5})

    assert Fragment.compose(Sheet, lower, higher) == {:ok, Fragment.stack(Sheet, lower, higher)}

    # The other way round, and two shorthands: the higher layer's word, unexpanded.
    assert Fragment.stack(Sheet, style(%{stroke: %{width: 2}}), style(%{stroke: "blue"})).style.stroke ==
             %{type: :solid, color: "blue", width: 2}

    assert Fragment.stack(Sheet, style(%{stroke: "red"}), style(%{stroke: "blue"})).style.stroke ==
             "blue"
  end

  @tag verifies: "fragments-hooks-normalize"
  test "provenance follows the normalized parts, one leaf per part" do
    layers = [{"house", style(%{stroke: "red"})}, {"cell", style(%{stroke: %{width: 2}})}]

    assert Enum.map(Fragment.explain(Sheet, layers), &{&1.path, &1.layer}) == [
             {[:style, :stroke, :color], "house"},
             {[:style, :stroke, :type], "house"},
             {[:style, :stroke, :width], "cell"}
           ]
  end

  @tag verifies: "fragments-hooks-under"
  test "a node whose type changes keeps of the lower only what the higher's type takes" do
    lower = style(%{fill: %{type: :dashed, color: "red", dash: [2, 2], width: 1}})
    higher = style(%{fill: %{type: :gradient, from: "red", to: "blue"}})

    assert Fragment.stack(Sheet, lower, higher).style.fill ==
             %{type: :gradient, from: "red", to: "blue", width: 1}

    # The same type keeps everything the higher doesn't say; a node with no type keeps all.
    same = style(%{fill: %{type: :dashed, dash: [4, 1]}})

    assert Fragment.stack(Sheet, lower, same).style.fill == %{
             type: :dashed,
             color: "red",
             dash: [4, 1],
             width: 1
           }

    untyped = style(%{fill: %{width: 3}})

    assert Fragment.stack(Sheet, lower, untyped).style.fill == %{
             type: :dashed,
             color: "red",
             dash: [2, 2],
             width: 3
           }

    # A deep entry both declare is trimmed the same way.
    assert Fragment.stack(Sheet, %{styles: %{"a" => lower.style}}, %{
             styles: %{"a" => higher.style}
           }).styles["a"].fill ==
             %{type: :gradient, from: "red", to: "blue", width: 1}

    assert {:ok, %{style: %{fill: %{type: :gradient, width: 1}}}} =
             Fragment.compose(Sheet, lower, higher)
  end

  @tag verifies: "fragments-hooks-without"
  test "a type without the hooks merges as before" do
    refute function_exported?(Design, :normalize, 4) or function_exported?(Design, :under, 3)
    lower = %{theme: %{name: "a", mode: :light}}
    higher = %{theme: %{name: "b"}}
    assert Fragment.stack(Design, lower, higher) == %{theme: %{name: "b", mode: :light}}
  end

  @tag verifies: "fragments-hooks-under"
  test "a lower node with no type keeps everything under a typed one, as visualize's rule does" do
    lower = style(%{fill: %{color: "red", width: 2}})
    higher = style(%{fill: %{type: :dashed}})

    assert Fragment.stack(Sheet, lower, higher).style.fill == %{
             type: :dashed,
             color: "red",
             width: 2
           }
  end

  @tag verifies: "fragments-hooks-left-fold"
  test "a type change is a replacement, so a stack where one trims is its left fold" do
    a = style(%{stroke: %{type: :dashed}})
    b = style(%{stroke: %{color: "red"}})
    c = style(%{stroke: %{type: :gradient}})

    left = Fragment.stack(Sheet, Fragment.stack(Sheet, a, b), c)
    assert Fragment.stack(Sheet, [a, b, c]) == left
    assert left.style.stroke == %{type: :gradient}

    # Grouped the other way, red meets the gradient before the dashed type does.
    assert Fragment.stack(Sheet, a, Fragment.stack(Sheet, b, c)).style.stroke ==
             %{type: :gradient, color: "red"}
  end

  # Paints of one type, written as parts or (for :solid) as a shorthand, or with no type:
  # layers that never change a paint's type, so no trim happens.
  defp paint(:solid) do
    one_of([
      member_of(["red", "blue"]),
      fixed_map(%{type: constant(:solid), color: member_of(["red", "blue"])}),
      untyped()
    ])
  end

  defp paint(:dashed) do
    one_of([
      fixed_map(%{
        type: constant(:dashed),
        dash: list_of(integer(1..4), max_length: 2),
        width: integer(1..3)
      }),
      untyped()
    ])
  end

  defp untyped, do: fixed_map(%{width: integer(1..3)})

  defp layer(type) do
    gen all(
          stroke <- paint(type),
          fill <- paint(type),
          keys <- list_of(member_of([:stroke, :fill]), max_length: 2)
        ) do
      style(Map.take(%{stroke: stroke, fill: fill}, keys))
    end
  end

  @tag verifies: "fragments-hooks-left-fold"
  property "where no layer changes a node's type, stack/2 with the hooks is associative" do
    check all(
            type <- member_of([:solid, :dashed]),
            a <- layer(type),
            b <- layer(type),
            c <- layer(type)
          ) do
      left = Fragment.stack(Sheet, Fragment.stack(Sheet, a, b), c)
      assert left == Fragment.stack(Sheet, a, Fragment.stack(Sheet, b, c))
    end
  end
end
