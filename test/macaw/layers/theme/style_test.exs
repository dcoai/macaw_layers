defmodule Macaw.Layers.Theme.StyleTest do
  # The palette's style type (spec/04 §2.4): a style node as a fragment type, which stacks
  # a list entry as the palette's old two-level merge did, and an extension's style type
  # (§3.4), whose hooks the palette stacks with in style/2, compose and the contracts alike.
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Fragment, Theme, Var}
  alias Macaw.Layers.Theme.{Palette, Style}

  doctest Style

  # A style type with the adopter's rule (visualize D-172): a gradient laid over a solid
  # paint drops the solid's color, which a gradient does not take.
  defmodule Gradients do
    @moduledoc false
    @behaviour Macaw.Layers.Fragment

    defdelegate root, to: Style
    defdelegate key(kind, key), to: Style
    defdelegate kinds, to: Style
    defdelegate wrapper(key), to: Style
    defdelegate place(kind, contribution, key), to: Style

    def under(:part, %{type: :solid} = lower, %{type: :gradient}), do: Map.delete(lower, :color)
    def under(_kind, lower, _higher), do: lower
  end

  defmodule Paints do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "paints"
    def styles, do: %{}
    def colors, do: %{}
    def style_type, do: Gradients
  end

  defmodule Brushes do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "brushes"
    def styles, do: %{}
    def colors, do: %{}
    def style_type, do: Style
  end

  defmodule Plain do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "plain"
    def styles, do: %{flash: {:state, %{opacity: 0.6}}}
    def colors, do: %{}
  end

  defmodule Untyped do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "untyped"
    def styles, do: %{}
    def colors, do: %{}
    def style_type, do: Macaw.Layers.Theme.Words
  end

  # The palette's merge before #14, kept as the oracle: a part both give merges key by key,
  # the higher's word at each key; anything else is the higher's.
  defp merge(lower, higher) do
    Map.merge(lower, higher, fn
      _part, a, b when is_map(a) and is_map(b) and not is_struct(a) and not is_struct(b) ->
        Map.merge(a, b)

      _part, _a, b ->
        b
    end)
  end

  # Words as given: atoms and strings both, a few shared so layers collide.
  defp word, do: member_of([:fill, :stroke, :font, :opacity, "curve", "fill"])
  defp leaf_key, do: member_of([:type, :color, :width, :dash, "size", :angle])

  defp leaf do
    one_of([
      member_of([:solid, :gradient, :none, :bold, nil, true]),
      integer(0..4),
      float(min: 0.0, max: 3.0),
      member_of(["3 3", "8 3", "text"]),
      member_of([{:color, "text"}, {:series, 2}, {:ramp, "status", 0.5}]),
      constant(~RGB"#3b6fa8"),
      constant(Var.new(:v)),
      list_of(integer(1..4), max_length: 2)
    ])
  end

  # A part's value: a map of leaves (some themselves maps, taken whole), a struct, or a
  # scalar.
  defp part do
    one_of([
      small_map(leaf_key(), one_of([leaf(), small_map(leaf_key(), leaf(), 2)]), 4),
      leaf()
    ])
  end

  defp style_node, do: small_map(word(), part(), 4)

  # A map from a few keys of a small pool, a repeated key keeping its last value.
  defp small_map(key, value, n), do: map(list_of(tuple({key, value}), max_length: n), &Map.new/1)

  @tag verifies: "themes-palette-style-type"
  property "a hookless Theme.Style stack is the old palette merge, two layers and a list alike" do
    check all(
            a <- style_node(),
            b <- style_node(),
            layers <- list_of(style_node(), max_length: 5),
            max_runs: 300
          ) do
      assert Fragment.stack(Style, a, b) == merge(a, b)
      assert Fragment.stack(Style, layers) == Enum.reduce(layers, %{}, &merge(&2, &1))
    end
  end

  @tag verifies: "themes-palette-style-type"
  test "the style type's corners: a struct, a map against a scalar, nested maps taken whole" do
    var = Var.new(:paint)

    for {a, b} <- [
          {%{fill: %{type: :solid, color: {:color, "text"}}}, %{fill: var}},
          {%{fill: var}, %{fill: %{width: 2}}},
          {%{stroke: 2}, %{stroke: %{width: 3}}},
          {%{stroke: %{width: 3}}, %{stroke: :none}},
          {%{font: %{size: %{a: 1, b: 2}}}, %{font: %{size: %{a: 3}}}},
          {%{"fill" => %{type: :solid}}, %{fill: %{width: 1}}},
          {%{fill: %{color: ~RGB"#3b6fa8"}}, %{fill: %{color: ~RGB"#ffffff", width: 1}}}
        ] do
      assert Fragment.stack(Style, a, b) == merge(a, b)
    end

    assert Fragment.stack(Style, %{font: %{size: %{a: 1, b: 2}}}, %{font: %{size: %{a: 3}}}) ==
             %{font: %{size: %{a: 3}}}
  end

  @tag verifies: "themes-palette-style-type"
  test "a theme without a style type of an extension stacks with Theme.Style" do
    assert Theme.style_type(Theme.default()) == Style

    theme = Theme.new(styles: %{"hover" => ["active", %{stroke: %{type: :gradient, angle: 90}}]})

    assert Theme.style(theme, :hover) == %{
             stroke: %{type: :gradient, color: {:color, "text"}, width: 3, angle: 90}
           }
  end

  describe "an extension's style type (spec/04 §3.4)" do
    @gradient %{stroke: %{type: :gradient, angle: 90}}

    @tag verifies: "themes-extensions-style-type"
    test "its under/3 drops a solid's color under a gradient in style/2 and compose" do
      theme = Theme.new(extensions: [Paints], styles: %{"hover" => ["active", @gradient]})
      assert Theme.style_type(theme) == Gradients

      expected = %{stroke: %{type: :gradient, width: 3, angle: 90}}
      assert Theme.style(theme, :hover) == expected

      assert Palette.compose(theme.styles, "hover", Theme.extra_styles(theme), Gradients) ==
               {:ok, expected}

      # The same entry by Theme.Style keeps the color, so the hook is what drops it.
      assert {:ok, %{stroke: %{color: {:color, "text"}}}} =
               Palette.compose(theme.styles, "hover", %{}, Style)
    end

    @tag verifies: "themes-extensions-style-type"
    test "its under/3 decides the contracts: a grid whose stroke loses its color is refused" do
      styles = %{"grid" => ["hover", @gradient]}
      plain = Theme.new(styles: styles)
      assert Theme.check(plain) == :ok

      assert [{{:style, "grid"}, message}] = Theme.violations(%{plain | extensions: [Paints]})
      assert message =~ "the grid must resolve a stroke"

      assert_raise ArgumentError,
                   ~r/style "grid" breaks its contract: the grid must resolve/,
                   fn ->
                     Theme.new(extensions: [Paints], styles: styles)
                   end
    end

    @tag verifies: "themes-extensions-style-type"
    test "two extensions giving a style type raise naming both; a style type is a fragment type" do
      assert_raise ArgumentError,
                   ~s(extensions "paints" and "brushes" both give a style type; a theme ) <>
                     "stacks its palette with one",
                   fn -> Theme.new(extensions: [Paints, Brushes]) end

      assert_raise ArgumentError, ~r/extension "untyped": style_type\/0 is a fragment type/, fn ->
        Theme.new(extensions: [Untyped])
      end

      # One extension's style type alongside extensions that give none is the one.
      assert Theme.style_type(Theme.new(extensions: [Plain, Paints])) == Gradients
      assert Theme.style_type(Theme.new(extensions: [Plain])) == Style
    end
  end
end
