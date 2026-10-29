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
    refute function_exported?(Design, :normalize, 4) or function_exported?(Design, :under, 2)
    lower = %{theme: %{name: "a", mode: :light}}
    higher = %{theme: %{name: "b"}}
    assert Fragment.stack(Design, lower, higher) == %{theme: %{name: "b", mode: :light}}
  end

  defp paint do
    one_of([
      member_of(["red", "blue", "green"]),
      fixed_map(%{width: integer(1..3)}),
      fixed_map(%{type: constant(:solid), color: member_of(["red", "blue"])}),
      fixed_map(%{
        type: constant(:dashed),
        dash: list_of(integer(1..4), max_length: 2),
        width: integer(1..3)
      }),
      fixed_map(%{type: constant(:gradient), from: constant("red"), to: constant("blue")})
    ])
  end

  defp layer do
    gen all(
          stroke <- paint(),
          fill <- paint(),
          keys <- list_of(member_of([:stroke, :fill]), max_length: 2)
        ) do
      style(Map.take(%{stroke: stroke, fill: fill}, keys))
    end
  end

  @tag verifies: "fragments-hooks-under"
  property "with the hooks, stack/2 stays associative" do
    check all(a <- layer(), b <- layer(), c <- layer()) do
      left = Fragment.stack(Sheet, Fragment.stack(Sheet, a, b), c)
      right = Fragment.stack(Sheet, a, Fragment.stack(Sheet, b, c))
      assert left == right
    end
  end
end
