defmodule Macaw.Layers.Fragment.VarTest do
  # Variables: binding and the variables still open (spec/02 §5), over the test type.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Fragment, Use, Var}
  alias Macaw.Layers.Test.Design

  doctest Macaw.Layers.Var

  describe "a variable (spec/02 §5)" do
    @tag verifies: "fragments-var-name"
    test "new reads an atom as its string, and a variable is one value wherever it stands" do
      assert Var.new(:color) == %Var{name: "color"} and Var.new("color") == Var.new(:color)

      # A scalar, an element and a whole node: the higher layer's variable is the value.
      assert Fragment.stack(Design, %{theme: :dark}, %{theme: Var.new(:t)}) == %{
               theme: Var.new(:t)
             }

      assert Fragment.stack(Design, %{marks: [%{id: "m"}]}, %{marks: [Var.new(:m)]}) == %{
               marks: [%{id: "m"}, Var.new(:m)]
             }

      assert Fragment.stack(Design, %{styles: %{"s" => %{a: 1}}}, %{styles: Var.new(:s)}) == %{
               styles: Var.new(:s)
             }

      assert Fragment.stack(Design, %{styles: Var.new(:s)}, %{styles: %{"s" => %{a: 1}}}) == %{
               styles: %{"s" => %{a: 1}}
             }
    end
  end

  describe "bind (spec/02 §5.1)" do
    @tag verifies: "fragments-bind-substitution"
    test "a literal sets a variable, another variable renames it, and an unnamed one stays" do
      fragment = %{styles: %{"s" => %{fill: Var.new(:color), stroke: Var.new(:edge)}}}

      assert Var.bind(fragment, %{"color" => "blue"}) == %{
               styles: %{"s" => %{fill: "blue", stroke: Var.new(:edge)}}
             }

      assert Var.bind(fragment, %{color: Var.new(:color_1)}) ==
               %{styles: %{"s" => %{fill: %Var{name: "color_1"}, stroke: %Var{name: "edge"}}}}

      assert Var.bind(fragment, %{}) == fragment
      assert Var.bind(fragment, %{other: 1}) == fragment
    end

    @tag verifies: "fragments-bind-substitution"
    test "names are read by either spelling, and a bound value is not searched again" do
      assert Var.bind([Var.new(:x), Var.new("y")], %{"x" => 1, y: 2}) == [1, 2]
      assert Var.bind(%{a: Var.new(:x)}, %{x: Var.new(:y), y: 3}) == %{a: Var.new(:y)}
      assert Var.bind(%{a: Var.new(:x)}, %{x: [Var.new(:x)]}) == %{a: [Var.new(:x)]}
    end

    @tag verifies: "fragments-bind-substitution"
    test "binding descends maps, lists and tuples, and stops at any other struct" do
      assert Var.bind({Var.new(:x), [%{k: Var.new(:x)}]}, %{x: 2}) == {2, [%{k: 2}]}

      site = %Use{id: {:use, 1}, local: %{a: Var.new(:x)}}
      assert Var.bind(%{theme: site}, %{x: 2}) == %{theme: site}
    end

    @tag verifies: "fragments-bind-substitution"
    test "bind/3 reaches a type's holes at their key, and leaves the rest to bind/2" do
      fragment = %{labels: [%{text: "{{unit}} per {{n}} in {{other}}", anchor: Var.new(:unit)}]}

      assert Var.bind(Design, fragment, %{"unit" => "km", n: Var.new(:count)}) ==
               %{labels: [%{text: "km per {{count}} in {{other}}", anchor: "km"}]}

      assert Var.bind(Design, fragment, %{}) == fragment
      # Without the type, a text is a leaf like any other.
      assert Var.bind(fragment, %{"unit" => "km"}) == %{
               labels: [%{text: "{{unit}} per {{n}} in {{other}}", anchor: "km"}]
             }
    end
  end

  describe "free (spec/02 §5.2)" do
    @tag verifies: "fragments-free-uses"
    test "a fragment is a one-layer stack: each variable by name, every use by path, at layer 0" do
      fragment = %{
        theme: Var.new(:t),
        styles: %{"s" => %{stroke: Var.new(:c), fill: Var.new(:c)}}
      }

      assert Var.free(Design, fragment) == [
               %{
                 name: "c",
                 uses: [
                   %{path: [:styles, "s", :fill], layer: 0},
                   %{path: [:styles, "s", :stroke], layer: 0}
                 ]
               },
               %{name: "t", uses: [%{path: [:theme], layer: 0}]}
             ]

      assert Var.free(Design, %{}) == []
      assert Var.free(Design, []) == []
    end

    @tag verifies: "fragments-free-uses"
    test "a literal over a variable removes a use, and a variable over a literal adds one at its layer" do
      lower = %{theme: Var.new(:t), version: Var.new(:v)}

      assert Var.free(Design, [lower, %{theme: :dark}]) == [
               %{name: "v", uses: [%{path: [:version], layer: 0}]}
             ]

      assert Var.free(Design, [{"base", %{theme: :dark}}, {"house", %{theme: Var.new(:t)}}]) ==
               [%{name: "t", uses: [%{path: [:theme], layer: "house"}]}]
    end

    @tag verifies: "fragments-free-uses"
    test "holes are reported at their text's key once, and nothing inside another struct is reached" do
      fragment = %{
        labels: [%{text: "{{u}} and {{u}} of {{w}}"}],
        theme: %Use{id: {:use, 1}, local: %{x: Var.new(:hidden)}}
      }

      assert Var.free(Design, fragment) == [
               %{name: "u", uses: [%{path: [:labels, 0, :text], layer: 0}]},
               %{name: "w", uses: [%{path: [:labels, 0, :text], layer: 0}]}
             ]
    end
  end
end
