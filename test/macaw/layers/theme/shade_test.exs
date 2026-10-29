defmodule Macaw.Layers.Theme.ShadeTest do
  @moduledoc """
  `shade(c, n)` (spec/04 §1.3, §2.2): one OKLCH curve for both modes, steps a theme pins,
  and the codec and contracts that carry them.
  """
  use ExUnit.Case, async: true

  import Macaw.Layers.Color, only: [sigil_RGB: 2, color: 1, shade: 2, alpha: 2]

  alias Macaw.Layers.{Color, Theme}
  alias Macaw.Layers.Theme.Document
  alias Macaw.Layers.Test.CssColor

  @brand Theme.new(name: :brand, colors: %{red: %{500 => ~RGB"#d62728", 100 => ~RGB"#fde8e8"}})

  defp oklch(%Color{} = color), do: Color.to_oklch(color)

  describe "the curve" do
    @tag verifies: "color-typed-transforms"
    test "500 is the color, and the curve's numbers are the spec's" do
      assert Color.resolve(shade(~RGB"#3b6fa8", 500), Theme.default(), :literal) === ~RGB"#3b6fa8"
      assert {0.97, 0.8, k} = Macaw.Layers.Color.Typed.curve(100)
      assert_in_delta k, 0.36, 1.0e-9
      assert Macaw.Layers.Color.Typed.curve(1000) == {0.2, 1.0, 0.0}
    end

    @tag verifies: "color-typed-transforms"
    test "a step toward white or black moves lightness by u and eases chroma by 1 − u²" do
      base = oklch(~RGB"#3b6fa8")

      for {n, toward, u} <- [{100, 0.97, 0.8}, {300, 0.97, 0.4}, {700, 0.2, 0.4}, {900, 0.2, 0.8}] do
        got = oklch(Color.resolve(shade(~RGB"#3b6fa8", n), Theme.default(), :literal))
        assert_in_delta got.l, base.l + (toward - base.l) * u, 0.005
        assert_in_delta got.c, base.c * (1 - u * u), 0.005
        if got.c > 0.02, do: assert_in_delta(got.h, base.h, 2)
      end
    end

    @tag verifies: "color-typed-transforms"
    test "the ends are near white and near black, without chroma" do
      white = oklch(Color.resolve(shade(color(:red), 0), Theme.default(), :literal))
      black = oklch(Color.resolve(shade(color(:red), 1000), Theme.default(), :literal))
      assert_in_delta white.l, 0.97, 0.005
      assert_in_delta black.l, 0.2, 0.005
      assert white.c < 0.005 and black.c < 0.005
    end

    @tag verifies: "color-typed-transforms"
    test "it pipes like every transform, and refuses a step outside 0..1000" do
      assert color(:red) |> shade(700) |> alpha(0.8) ==
               {:alpha, {:shade, {:color, "red"}, 700}, 0.8}

      assert_raise ArgumentError, ~r/a step in 0\.\.1000/, fn -> shade(color(:red), 1200) end
      assert_raise ArgumentError, ~r/write color\(:red\)/, fn -> shade(:red, 100) end
    end
  end

  describe "the two modes agree" do
    @tag verifies: "color-css-agrees"
    test "an unpinned step's CSS evaluates to its literal" do
      for theme <- [Theme.default(), Theme.dark(), @brand],
          value <- [
            shade(color(:blue), 100),
            shade(color(:blue), 300),
            shade(color(:blue), 700),
            shade(~RGB"#2f8f86", 900)
          ] do
        css = Color.resolve(value, theme, :css)
        {r, g, b, _a} = CssColor.eval(css)
        %Color{r: lr, g: lg, b: lb} = Color.resolve(value, theme, :literal)

        for {got, want} <- [{lr, r}, {lg, g}, {lb, b}],
            do: assert(abs(got - want) <= 1, "#{css}: #{inspect({r, g, b})}")
      end
    end

    @tag verifies: "color-css-agrees"
    test "the CSS is a relative color on the curve's numbers, or the color at 500" do
      assert Color.resolve(shade(color(:blue), 100), Theme.default(), :css) ==
               "oklch(from var(--mw-blue, #3b6fa8) calc(l + (0.97 - l) * 0.8) calc(c * 0.36) h / alpha)"

      assert Color.resolve(shade(color(:blue), 700), Theme.default(), :css) ==
               "oklch(from var(--mw-blue, #3b6fa8) calc(l - (l - 0.2) * 0.4) calc(c * 0.84) h / alpha)"

      assert Color.resolve(shade(color(:blue), 500), Theme.default(), :css) ==
               "var(--mw-blue, #3b6fa8)"
    end
  end

  describe "a theme pins steps" do
    @tag verifies: "themes-color-table-lookup"
    test "its step 500 is the name's color, a pinned step its own property" do
      assert Color.resolve(color(:red), @brand, :css) == "var(--mw-red, #d62728)"
      assert Color.resolve(shade(color(:red), 100), @brand, :literal) === ~RGB"#fde8e8"
      assert Color.resolve(shade(color(:red), 100), @brand, :css) == "var(--mw-red-100, #fde8e8)"
      assert Color.resolve(shade(color(:red), 500), @brand, :css) == "var(--mw-red, #d62728)"
    end

    @tag verifies: "themes-color-table-lookup"
    test "an unpinned step is computed from step 500" do
      computed = Color.resolve(shade(color(:red), 300), @brand, :literal)
      assert computed == Color.resolve(shade(~RGB"#d62728", 300), @brand, :literal)
    end

    @tag verifies: "themes-color-table-lookup"
    test "pinned steps hold their contract" do
      assert_raise ArgumentError,
                   ~r/color "brand" breaks its contract: pinned steps must include 500/,
                   fn ->
                     Theme.new(colors: %{brand: %{100 => ~RGB"#fde8e8"}})
                   end

      assert_raise ArgumentError, ~r/a pinned step is an integer in 0\.\.1000, got 1100/, fn ->
        Theme.new(colors: %{brand: %{500 => ~RGB"#d62728", 1100 => ~RGB"#000000"}})
      end

      assert_raise ArgumentError, ~r/a pinned step is a literal color, got :pale/, fn ->
        Theme.new(colors: %{brand: %{500 => ~RGB"#d62728", 100 => :pale}})
      end

      assert_raise ArgumentError,
                   ~r/a pinned step is a literal color: "#fde8e8" is text, and a string is never a color/,
                   fn ->
                     Theme.new(colors: %{brand: %{500 => ~RGB"#d62728", 100 => "#fde8e8"}})
                   end
    end
  end

  describe "the codec" do
    @tag verifies: "themes-document-forms"
    test "a shade round-trips through JSON as $shade" do
      theme = Theme.new(name: :pale, colors: %{wash: shade(color(:red), 100)})
      {:ok, json} = Document.to_json(theme)
      assert json =~ ~s({"$shade":[{"$color":"red"},100]})
      assert {:ok, back} = Document.from_json(json)
      assert back.colors["wash"] == shade(color(:red), 100)
    end

    @tag verifies: "themes-document-forms"
    test "a theme document carries its pinned steps as $steps" do
      {:ok, json} = Document.to_json(@brand)

      assert json =~
               ~s("red":{"$steps":[[100,{"$rgb":"#fde8e8"}],[500,{"$rgb":"#d62728"}]]})

      assert Document.from_json(json) == {:ok, @brand}
    end
  end
end
