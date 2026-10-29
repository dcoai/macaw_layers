defmodule Macaw.Layers.Theme.CssTest do
  @moduledoc """
  A transform in `:css` mode (spec/04 §1.3, §1.4): the CSS it writes, and that CSS
  evaluated by CSS Color 4 and 5 — by `Macaw.Layers.Test.CssColor`, written from the
  specifications alone — agreeing with the literal `:literal` mode computes. The same chart
  in both modes is the same picture.
  """
  use ExUnit.Case, async: true

  import Macaw.Layers.Color,
    only: [
      color: 1,
      intensity: 2,
      blend: 1,
      alpha: 2,
      lighten: 2,
      darken: 2,
      saturate: 2,
      sigil_RGB: 2
    ]

  alias Macaw.Layers.{Color, Theme}
  alias Macaw.Layers.Test.CssColor

  @values [
    intensity(color(:red), 0.65),
    blend([color(:blue), color(:red)]),
    blend([intensity(color(:blue), 0.65), intensity(color(:red), 0.3)]),
    [intensity(color(:blue), 0.65), intensity(color(:red), 0.3)] |> blend() |> alpha(0.65),
    blend([color(:blue), intensity(color(:red), 0.5), intensity(color(:green), 0.5)]),
    blend([
      intensity(color(:blue), 0.2),
      intensity(color(:amber), 0.3),
      intensity(~RGB"#2f8f86", 0.1)
    ]),
    blend([color(:text), color(:background), color(:series_4)]),
    alpha(color(:series_2), 0.4),
    lighten(color(:blue), 0.3),
    darken(color(:blue), 0.25),
    saturate(color(:gray), 0.1),
    color(:series_1) |> lighten(0.2) |> alpha(0.8),
    intensity(blend([color(:green), ~RGB"#808080"]), 0.5)
  ]

  defp channels(%Color{r: r, g: g, b: b, opacity: a}), do: {r, g, b, a}

  @tag verifies: "color-css-agrees"
  test "the CSS of each transform evaluates to the literal :literal mode computes" do
    for theme <- [Theme.default(), Theme.dark()], value <- @values do
      css = Color.resolve(value, theme, :css)
      {r, g, b, a} = CssColor.eval(css)

      # Only a color inside sRGB is compared channel by channel: outside, a browser
      # gamut-maps, which the literal does too, and the evaluator does not.
      assert Enum.all?([r, g, b], &(&1 > -0.5 and &1 < 255.5)),
             "#{css} leaves sRGB: #{inspect({r, g, b})}; choose another value"

      {lr, lg, lb, la} = channels(Color.resolve(value, theme, :literal))

      for {got, want} <- [{lr, r}, {lg, g}, {lb, b}] do
        assert abs(got - want) <= 1, "#{inspect(value)}: #{css} is #{inspect({r, g, b})}"
      end

      assert abs(la - a) <= 1 / 255 + 1.0e-9, "#{inspect(value)}: alpha #{la}, CSS #{a}"
    end
  end

  @tag verifies: "color-css-agrees"
  test "each transform is written as color-mix or a relative color over its operands' own CSS" do
    theme = Theme.default()

    assert Color.resolve(intensity(color(:red), 0.65), theme, :css) ==
             "color-mix(in oklab, var(--mw-red, #c23238) 65%, transparent)"

    assert Color.resolve(blend([color(:red), color(:blue), color(:green)]), theme, :css) ==
             "color-mix(in oklab, color-mix(in oklab, var(--mw-red, #c23238) 50%, " <>
               "var(--mw-blue, #3b6fa8) 50%) 66.6667%, var(--mw-green, #4ca34b) 33.3333%)"

    assert Color.resolve(alpha(color(:red), 0.5), theme, :css) ==
             "oklch(from var(--mw-red, #c23238) l c h / 0.5)"

    assert Color.resolve(lighten(color(:red), 0.3), theme, :css) ==
             "oklch(from var(--mw-red, #c23238) calc(l + (1 - l) * 0.3) c h / alpha)"

    assert Color.resolve(darken(~RGB"#3b6fa8", 0.25), theme, :css) ==
             "oklch(from #3b6fa8 calc(l * 0.75) c h / alpha)"

    assert Color.resolve(saturate(color(:red), 0.1), theme, :css) ==
             "oklch(from var(--mw-red, #c23238) l calc(c + (0.4 - c) * 0.1) h / alpha)"
  end

  @tag verifies: "color-css-agrees"
  test "a blend's edges: weight 0 left out, nothing transparent, one color itself" do
    theme = Theme.default()
    assert Color.resolve(blend([intensity(color(:red), 0)]), theme, :css) == "transparent"
    assert Color.resolve(blend([color(:red)]), theme, :css) == "var(--mw-red, #c23238)"

    assert Color.resolve(blend([color(:red), intensity(color(:blue), 0)]), theme, :css) ==
             "var(--mw-red, #c23238)"
  end

  @tag verifies: "color-css-agrees"
  test "a stylesheet's theme switch carries through: the CSS names the theme's properties" do
    css = Color.resolve(blend([color(:text), intensity(color(:bad), 0.3)]), Theme.default(), :css)
    assert css =~ "var(--mw-text, #333333)" and css =~ "var(--mw-bad, #c23238)"
  end

  @tag verifies: "color-css-agrees"
  test "the contrast ink is a literal in :css too" do
    assert Color.resolve({:contrast, color(:text)}, Theme.default(), :css) == "#ffffff"
  end
end
