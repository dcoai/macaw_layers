defmodule Macaw.Layers.Fragment.CompositeHooksTest do
  # The composite's hooks (spec/02 §8.1, §8.2) over `Board`, the test type with them:
  # `scope/3` carries the composite node's own keys to its sites, and `place_whole/2`
  # places a keyed site's contribution of no kind.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Composite, Use}
  alias Macaw.Layers.Test.{Board, Design}

  @library %{
    {:mark, 1} => %{mark: %{id: "needle", type: :line}},
    {:mark, 2} => %{mark: %{id: "own", type: :area, defaults: %{opacity: 1}}},
    {:frame, 3} => %{frames: %{"main" => %{kind: :polar}}, marks: [%{id: "arc", type: :area}]}
  }

  defp fetch(id), do: Map.fetch(@library, id)

  @tag verifies: "fragments-composite-scope"
  test "a composite's own keys reach the sites it places through scope/3" do
    composite = %{
      composite: %{
        uses: [%Use{id: {:use, 1}, ref: {:mark, 1}}, %Use{id: {:use, 2}, ref: {:mark, 2}}],
        defaults: %{opacity: 0.5}
      }
    }

    assert {:ok, %{marks: [needle, own]}, %{missing: [], keyless: []}} =
             Composite.flatten(Board, composite, &fetch/1)

    assert needle.defaults == %{opacity: 0.5}
    # A site that says its own keeps them.
    assert own.defaults == %{opacity: 1}

    # A type without scope/3 leaves the sites as they are.
    assert {:ok, %{marks: [plain, _]}, _} = Composite.flatten(Design, composite, &fetch/1)
    refute Map.has_key?(plain, :defaults)
  end

  @tag verifies: "fragments-place-whole"
  test "a keyed site's contribution of no kind is placed by place_whole/2, else is its own layer" do
    composite = %{composite: %{uses: [%Use{id: {:use, 1}, ref: {:frame, 3}, key: "gauge"}]}}

    assert {:ok, flat, _} = Composite.flatten(Board, composite, &fetch/1)
    assert flat.frames == %{"gauge" => %{kind: :polar}}
    assert flat.marks == [%{id: "arc", type: :area}]

    assert Composite.place(Board, @library[{:frame, 3}], nil) == {:ok, @library[{:frame, 3}]}
    assert Composite.place(Design, @library[{:frame, 3}], "gauge") == {:ok, @library[{:frame, 3}]}
  end
end
