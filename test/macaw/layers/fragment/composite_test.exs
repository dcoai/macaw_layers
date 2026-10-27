defmodule Macaw.Layers.Fragment.CompositeTest do
  # Composites: flattening, placing and decomposing (spec/02 §8), over the test type.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Composite, Use, Var}
  alias Macaw.Layers.Test.Design

  @library %{
    {:style, 1} => %{style: %{stroke: "#111", fill: Var.new(:c)}},
    {:theme, 2} => %{theme: :dark},
    {:mark, 3} => %{mark: %{id: "m", type: :line}},
    {:composite, 4} => %{
      composite: %{uses: [%Use{id: {:use, 1}, ref: {:style, 1}, key: "inner"}]}
    },
    {:composite, 5} => %{
      composite: %{
        uses: [
          %Use{id: {:use, 1}, ref: {:style, 1}},
          %Use{id: {:use, 2}, local: %{style: %{stroke: "#222"}}}
        ]
      }
    },
    {:composite, 6} => %{composite: %{uses: [%Use{id: {:use, 1}, ref: {:composite, 7}}]}},
    {:composite, 7} => %{composite: %{uses: [%Use{id: {:use, 1}, ref: {:composite, 6}}]}},
    {:composite, 8} => %{composite: %{uses: [%Use{id: {:use, 1}, ref: {:composite, 8}}]}},
    {:composite, 9} => %{
      composite: %{uses: [%Use{id: {:use, 1}, ref: {:style, 99}, key: "gone"}]}
    }
  }

  @none %{missing: [], keyless: []}

  defp fetch(id), do: Map.fetch(@library, id)
  defp flatten(fragment), do: Composite.flatten(Design, fragment, &fetch/1)
  defp composite(uses, vars \\ %{}), do: %{composite: %{uses: uses, vars: vars}}

  describe "flatten/3 (spec/02 §8.1)" do
    @tag verifies: "fragments-flatten-nested"
    test "every site resolves in order, is placed by its kind under its key, and the layers stack" do
      fragment =
        composite(
          [
            %Use{id: {:use, 1}, ref: {:theme, 2}},
            %Use{
              id: {:use, 2},
              ref: {:style, 1},
              key: "series",
              vars: %{"c" => Var.new(:color_1)},
              local: %{style: %{opacity: 0.8}}
            },
            %Use{id: {:use, 3}, ref: {:mark, 3}},
            %Use{id: {:use, 4}, local: %{mark: %{id: "n", type: :area}}},
            %Use{id: {:use, 5}, local: %{theme: :default}, mask: :all}
          ],
          %{"color_1" => %{default: "blue"}}
        )

      assert flatten(fragment) ==
               {:ok,
                %{
                  vars: %{"color_1" => %{default: "blue"}},
                  theme: :dark,
                  styles: %{"series" => %{stroke: "#111", fill: Var.new(:color_1), opacity: 0.8}},
                  marks: [%{id: "m", type: :line}, %{id: "n", type: :area}]
                }, @none}
    end

    @tag verifies: "fragments-composite-shape"
    test "a fragment that is not a composite flattens to itself, and a composite of nothing to the empty map" do
      assert Composite.composite?(composite([])) and
               not Composite.composite?(%{composite: %{uses: []}, theme: :dark})

      refute Composite.composite?(%{theme: :dark})

      assert flatten(%{theme: :dark}) == {:ok, %{theme: :dark}, @none}
      assert flatten(composite([])) == {:ok, %{}, @none}
    end

    @tag verifies: "fragments-flatten-nested"
    test "composites nest: an inner composite is flattened first, then placed, and bound again by its site" do
      outer =
        composite([
          %Use{id: {:use, 1}, ref: {:composite, 4}, vars: %{c: "red"}},
          %Use{id: {:use, 2}, ref: {:theme, 2}}
        ])

      assert flatten(outer) ==
               {:ok, %{styles: %{"inner" => %{stroke: "#111", fill: "red"}}, theme: :dark}, @none}

      # A composer of one name-keyed kind stacks its bodies, and its site places the result.
      keyed = composite([%Use{id: {:use, 1}, ref: {:composite, 5}, key: "series"}])

      assert flatten(keyed) ==
               {:ok, %{styles: %{"series" => %{stroke: "#222", fill: Var.new(:c)}}}, @none}

      inline =
        composite([
          %Use{
            id: {:use, 1},
            local:
              composite([
                %Use{id: {:use, 2}, ref: {:theme, 2}},
                %Use{id: {:use, 3}, ref: {:mark, 3}}
              ]),
            mask: [:theme]
          }
        ])

      assert flatten(inline) == {:ok, %{marks: [%{id: "m", type: :line}]}, @none}
    end

    @tag verifies: "fragments-flatten-nested"
    test "a missing reference shows through and is reported by its site, nested or inside the document" do
      fragment =
        composite([
          %Use{id: {:use, 1}, ref: {:style, 98}, key: "s", local: %{style: %{opacity: 1}}},
          %Use{id: {:use, 2}, ref: {:composite, 9}},
          %Use{id: {:use, 3}, local: %{mark: %{id: "m", style: {:style, 1}}}},
          %Use{id: {:use, 4}, local: %{mark: %{id: "n", style: {:style, 97}}}}
        ])

      assert flatten(fragment) ==
               {:ok,
                %{
                  styles: %{"s" => %{opacity: 1}},
                  marks: [%{id: "m", style: %{stroke: "#111", fill: Var.new(:c)}}, %{id: "n"}]
                },
                %{
                  missing: [
                    {{:style, 98}, {:use, 1}},
                    {{:style, 99}, {:use, 1}},
                    {{:style, 97}, [:marks, 1, :style]}
                  ],
                  keyless: []
                }}
    end

    @tag verifies: "fragments-flatten-nested"
    test "a name-keyed site with no key is reported and left out; a cycle is refused where it closes" do
      fragment =
        composite([%Use{id: {:use, 1}, ref: {:style, 1}}, %Use{id: {:use, 2}, ref: {:theme, 2}}])

      assert flatten(fragment) == {:ok, %{theme: :dark}, %{missing: [], keyless: [{:use, 1}]}}

      assert flatten(composite([%Use{id: {:use, 1}, ref: {:composite, 6}}])) ==
               {:error, {:cycle, [{:composite, 6}, {:composite, 7}, {:composite, 6}]}}

      assert flatten(@library[{:composite, 8}]) ==
               {:error, {:cycle, [{:composite, 8}, {:composite, 8}]}}
    end
  end

  describe "place and decompose (spec/02 §8.2)" do
    @tag verifies: "fragments-place-kind"
    test "a contribution is placed by its kind through the type, and one of no kind is its own layer" do
      assert Composite.place(Design, %{style: %{a: 1}}, "k") ==
               {:ok, %{styles: %{"k" => %{a: 1}}}}

      assert Composite.place(Design, %{style: %{a: 1}}, nil) == :keyless

      assert Composite.place(Design, %{mark: %{id: "m"}}, "ignored") ==
               {:ok, %{marks: [%{id: "m"}]}}

      assert Composite.place(Design, %{theme: :dark, version: 1}, nil) ==
               {:ok, %{theme: :dark, version: 1}}

      assert Composite.place(Design, %{}, nil) == {:ok, %{}}
    end

    @tag verifies: "fragments-decompose-inverse"
    test "decompose gives one inline site per kind, keyed as the document keyed it, and flattening is the document" do
      document = %{
        theme: :dark,
        styles: %{"series" => %{stroke: "#111"}, "grid" => %{stroke: "#eee"}},
        sources: %{"rows" => %{fields: [:a]}},
        marks: [%{id: "m", type: :line}, %{id: "n", type: :area}]
      }

      %{composite: %{uses: uses}} = sites = Composite.decompose(Design, document)

      assert Enum.map(uses, & &1.id) == Enum.map(1..6, &{:use, &1})
      assert Enum.all?(uses, &(&1.ref == nil and map_size(&1.local) == 1))

      assert uses |> Enum.map(&{&1.local |> Map.keys() |> hd(), &1.key}) |> Enum.sort() ==
               Enum.sort(
                 theme: nil,
                 style: "series",
                 style: "grid",
                 source: "rows",
                 mark: nil,
                 mark: nil
               )

      assert flatten(sites) == {:ok, document, @none}

      assert flatten(Composite.decompose(Design, %{marks: document.marks})) ==
               {:ok, %{marks: document.marks}, @none}
    end
  end
end
