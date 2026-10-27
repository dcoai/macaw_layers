defmodule Macaw.Layers.Fragment.UseTest do
  # Masks and use sites (spec/02 §4, §7), over the test type.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Fragment, Use, Var}
  alias Macaw.Layers.Test.Design

  doctest Macaw.Layers.Use

  @library %{
    {:style, 1} => %{style: %{stroke: "#111", fill: %{color: Var.new(:c)}}},
    {:theme, 2} => %{theme: :dark}
  }

  defp fetch(id), do: Map.fetch(@library, id)

  describe "mask/2 (spec/02 §4)" do
    @tag verifies: "fragments-mask-paths"
    test "a mask removes each path, a bare name or keys from the root, read by spelling" do
      assert Use.mask(%{stroke: "#111", stroke_width: 5}, [:stroke]) == %{stroke_width: 5}
      assert Use.mask(%{stroke: "#111", stroke_width: 5}, ["stroke"]) == %{stroke_width: 5}

      frame = %{frames: %{"main" => %{legend: %{}, margin: %{top: 1}}}}

      assert Use.mask(frame, [[:frames, "main", :margin]]) == %{
               frames: %{"main" => %{legend: %{}}}
             }

      assert Use.mask(frame, [["frames", "main", "legend"], [:frames, "main", :margin]]) == %{
               frames: %{"main" => %{}}
             }

      marks = %{marks: [%{id: "m", style: "s"}, %{id: "n", style: "t"}]}

      assert Use.mask(marks, [[:marks, 1, :style]]) == %{
               marks: [%{id: "m", style: "s"}, %{id: "n"}]
             }
    end

    @tag verifies: "fragments-mask-paths"
    test "an emptied node is kept as an empty map, a path naming nothing is ignored, all removes everything" do
      assert Use.mask(%{frames: %{"main" => %{margin: %{top: 1}}}}, [
               [:frames, "main", :margin, :top]
             ]) ==
               %{frames: %{"main" => %{margin: %{}}}}

      fragment = %{theme: :dark, marks: [%{id: "m"}]}

      assert Use.mask(fragment, [:version, [:theme, :deeper], [:marks, 4, :id], [:marks, -1]]) ==
               fragment

      assert Use.mask(fragment, []) == fragment
      assert Use.mask(fragment, :all) == %{}
    end

    @tag verifies: "fragments-mask-paths"
    test "a masked key shows the lower layer's value through the cascade, and explain names that layer" do
      lower = %{theme: :dark, version: 1}
      higher = Use.mask(%{theme: :default, version: 2}, [:theme])

      assert Fragment.stack(Design, lower, higher) == %{theme: :dark, version: 2}

      assert %{layer: "lower", overrode: []} =
               Design
               |> Fragment.explain([{"lower", lower}, {"higher", higher}])
               |> Enum.find(&(&1.path == [:theme]))
    end
  end

  describe "a use site (spec/02 §7)" do
    @tag verifies: "fragments-use-order"
    test "a site resolves ref, then local, then mask, then bind" do
      use = %Use{
        id: {:use, 1},
        ref: {:style, 1},
        local: %{style: %{stroke: "#222", stroke_width: 2}},
        mask: [[:style, :stroke_width]],
        vars: %{"c" => "blue"}
      }

      assert Use.resolve(Design, use, &fetch/1) ==
               {:ok, %{style: %{stroke: "#222", fill: %{color: "blue"}}}}

      assert Use.over(Design, use, @library[{:style, 1}]) == %{
               style: %{stroke: "#222", fill: %{color: "blue"}}
             }
    end

    @tag verifies: "fragments-use-order"
    test "mask and bind reach the local too, and a mask of all removes the site, its local included" do
      masked = %Use{
        id: {:use, 1},
        local: %{style: %{opacity: 0.5, stroke: "#111"}},
        mask: [[:style, :opacity]]
      }

      assert Use.resolve(Design, masked, &fetch/1) == {:ok, %{style: %{stroke: "#111"}}}

      assert Use.bind(%{stroke: Var.new(:c)}, %{c: "red"}) ==
               Var.bind(%{stroke: Var.new(:c)}, %{c: "red"})

      bound = %Use{id: {:use, 2}, local: %{style: %{stroke: Var.new(:c)}}, vars: %{c: "red"}}
      assert Use.resolve(Design, bound, &fetch/1) == {:ok, %{style: %{stroke: "red"}}}

      # A path the mask removes is gone before binding: its variable binds nothing.
      both = %Use{bound | mask: [[:style, :stroke]]}
      assert Use.resolve(Design, both, &fetch/1) == {:ok, %{style: %{}}}

      all = %Use{id: {:use, 3}, ref: {:style, 1}, local: %{style: %{opacity: 1}}, mask: :all}
      assert Use.resolve(Design, all, &fetch/1) == {:ok, %{}}
    end

    @tag verifies: "fragments-use-order"
    test "a missing ref is the site's local alone, masked and bound, and the id is reported" do
      use = %Use{
        id: {:use, 1},
        ref: {:style, 9},
        local: %{style: %{opacity: 1, stroke: Var.new(:c)}},
        vars: %{c: "red"}
      }

      assert Use.resolve(Design, use, &fetch/1) ==
               {:missing, {:style, 9}, %{style: %{opacity: 1, stroke: "red"}}}

      assert Use.resolve(Design, %Use{id: {:use, 2}, ref: {:style, 9}}, &fetch/1) ==
               {:missing, {:style, 9}, %{}}
    end

    @tag verifies: "fragments-use-order"
    test "new issues the next id among its siblings, an inline composite's sites counted" do
      assert Use.new({:style, 1}) == %Use{id: {:use, 1}, ref: {:style, 1}}
      assert Use.new({:theme, 2}, [Use.new({:style, 1})]).id == {:use, 2}

      group = %Use{id: {:use, 5}, local: %{composite: %{uses: [%Use{id: {:use, 9}}]}}}
      assert Use.new(nil, [Use.new(:a), group]) == %Use{id: {:use, 10}, ref: nil}

      assert Use.new(nil, [
               %Use{
                 id: {:use, 3},
                 ref: {:composite, 1},
                 local: %{composite: %{uses: [%Use{id: {:use, 9}}]}}
               }
             ]).id ==
               {:use, 4}
    end
  end
end
