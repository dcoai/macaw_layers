defmodule Macaw.Layers.Fragment.KindTest do
  # The fragment-type behavior, kinds and ids (spec/02 §1, §6.1, §6.2), over the test type.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Fragment, Use, Var}
  alias Macaw.Layers.Test.Design

  describe "the type (spec/02 §1)" do
    @tag verifies: "fragments-type-callbacks"
    test "a type declares its root, keys, identities, kinds, wrappers and placement" do
      for {f, a} <- [root: 0, key: 2, identity: 2, kinds: 0, wrapper: 1, place: 3, merge: 3],
          do: assert(Fragment.callback?(Design, f, a))

      assert Design.root() == :design
      assert Design.key(:design, :marks) == %{merge: :concat, element: :mark}
      assert Design.key(:design, :unknown) == nil
      assert Design.identity(:axis, %{scale: "x", side: :bottom}) == {"x", :bottom}
      assert Design.wrapper(:style) == :style
      assert Design.place(:style, %{style: %{}}, nil) == :keyless
    end

    @tag verifies: "fragments-type-callbacks"
    test "an unknown key is override with no node, and a struct is a leaf of the walks" do
      assert Fragment.stack(Design, %{odd: %{a: 1}}, %{odd: %{b: 2}}) == %{odd: %{b: 2}}
      assert {:ok, %{odd: %{b: 2}}} = Fragment.compose(Design, %{odd: %{a: 1}}, %{odd: %{b: 2}})

      site = %Use{id: {:use, 1}, local: %{a: 1}}
      assert Fragment.stack(Design, %{theme: %{local: %{b: 2}}}, %{theme: site}) == %{theme: site}

      time = ~U[2026-10-27 00:00:00Z]
      assert Fragment.stack(Design, %{theme: %{at: time}}, %{theme: time}) == %{theme: time}

      assert Fragment.explain(Design, [%{theme: Var.new(:t)}]) == [
               %{path: [:theme], value: Var.new(:t), layer: 0, overrode: []}
             ]
    end
  end

  describe "kind/2 (spec/02 §6.1)" do
    @tag verifies: "fragments-kind-derived"
    test "kind walks single keys down to the last kind reached" do
      assert Fragment.kind(Design, %{style: %{stroke_width: 5}}) == :style
      assert Fragment.kind(Design, %{styles: %{"series" => %{stroke_width: 5}}}) == :style

      assert Fragment.kind(Design, %{frames: %{"main" => %{kind: :polar, margin: %{top: 1}}}}) ==
               :frame

      assert Fragment.kind(Design, %{frames: %{"main" => %{scales: %{"x" => %{kind: :time}}}}}) ==
               :scale

      assert Fragment.kind(Design, %{marks: [%{type: :line}, %{type: :area}]}) == :mark
      assert Fragment.kind(Design, %{composite: %{uses: []}}) == :composite
      assert Fragment.kind(Design, %{theme: %{axis: "#666"}}) == :theme
    end

    @tag verifies: "fragments-kind-derived"
    test "a fragment that branches at the top, or stops at the root, has no kind" do
      assert Fragment.kind(Design, %{styles: %{}, frames: %{}}) == nil
      assert Fragment.kind(Design, %{version: 2}) == nil
      assert Fragment.kind(Design, %{}) == nil
      assert Fragment.kind(Design, %{unknown: 1}) == nil
    end
  end

  describe "ids (spec/02 §6.2)" do
    @use %Use{
      id: {:use, 1},
      ref: {:style, 11},
      origin: {:style, 4},
      local: %{fill: {:scale, 2}},
      vars: %{"c" => {:style, 9}}
    }

    @tag verifies: "fragments-refs-relocate"
    test "refs lists every id once, sorted, a use site's parts included; other tuples are not ids" do
      fragment = %{
        composite: %{uses: [@use, %Use{id: {:use, 2}, ref: {:style, 11}}]},
        axis: {:axis, :y},
        n: {:style, 0},
        other: {:nope, 3}
      }

      assert Fragment.refs(Design, fragment) == [
               {:scale, 2},
               {:style, 4},
               {:style, 9},
               {:style, 11}
             ]

      assert Fragment.refs(Design, %{a: [{:style, 1}, {:style, 1}]}) == [{:style, 1}]
    end

    @tag verifies: "fragments-refs-relocate"
    test "relocate rewrites every id through the table, use sites in place, and answers the ids it missed" do
      table = %{
        {:style, 11} => {:style, 1},
        {:style, 4} => {:style, 2},
        {:scale, 2} => {:scale, 7}
      }

      assert {%{composite: %{uses: [use]}, s: [{:style, 1}, {:style, 9}]}, [{:style, 9}]} =
               Fragment.relocate(
                 Design,
                 %{composite: %{uses: [@use]}, s: [{:style, 11}, {:style, 9}]},
                 table
               )

      assert %Use{
               ref: {:style, 1},
               origin: {:style, 2},
               local: %{fill: {:scale, 7}},
               vars: %{"c" => {:style, 9}}
             } = use

      assert Fragment.relocate(Design, %{t: {:x, {:axis, :y}}}, table) ==
               {%{t: {:x, {:axis, :y}}}, []}
    end
  end
end
