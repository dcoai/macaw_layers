defmodule Macaw.Layers.Theme.ColorsTest do
  @moduledoc """
  The theme's color table (spec/04 §2.2): the CSS named colors under the default theme's
  names under a theme's own, the furniture and series as names, and the role colors folded
  into it as names by use.
  """
  use ExUnit.Case, async: true

  import Macaw.Layers.Color, only: [color: 1, sigil_RGB: 2]

  alias Macaw.Layers.{Color, Theme}

  @tag verifies: "themes-color-table-lookup"
  test "a hue resolves through the theme's table, as a slot does" do
    assert Color.resolve(color(:red), Theme.default(), :css) == "var(--mw-red, #c23238)"
    assert Color.resolve(color(:red), Theme.dark(), :css) == "var(--mw-red, #ff8f8a)"
    assert Color.resolve(color(:red), Theme.dark(), :literal) === ~RGB"#ff8f8a"
  end

  @tag verifies: "themes-color-table-lookup"
  test "a name the theme does not hold is the CSS named color's" do
    assert Color.resolve(color(:steelblue), Theme.default(), :css) ==
             "var(--mw-steelblue, #4682b4)"

    assert Theme.css_name(:steelblue) == "--mw-steelblue"
  end

  @tag verifies: "themes-color-table-lookup"
  test "a theme changes a value and adds names; a name in no part of the table raises" do
    theme = Theme.new(name: :house, colors: %{red: ~RGB"#e00000", brand: ~RGB"#123456"})
    assert Color.resolve(color(:red), theme, :literal) === ~RGB"#e00000"
    assert Color.resolve(color(:brand), theme, :css) == "var(--mw-brand, #123456)"
    assert "brand" in Theme.color_names(theme)

    assert_raise ArgumentError, ~r/unknown theme slot "brand"/, fn ->
      Color.resolve(color(:brand), Theme.default(), :css)
    end
  end

  # The membership test builds no list, and so may not drift from the list it stands for:
  # every name of every built-in theme's table, a theme's own name, and the words beside
  # the table — a series past the theme's count, a palette name. A name is found by either
  # spelling (spec/04 §2.2), so "red" is one.
  @tag verifies: "themes-color-table-lookup"
  test "color_name?/2 answers exactly color_names/1's membership" do
    house = Theme.new(name: :house, colors: %{brand: ~RGB"#123456"})

    for theme <- [house | Enum.map([:default, :dark, :color_safe, :print], &Theme.builtin/1)] do
      names = Theme.color_names(theme)
      assert Enum.all?(names, &Theme.color_name?(theme, &1))

      beside = [:"series_#{length(theme.series) + 1}", :series_0, :series_01, :thick, :nope]
      refute Enum.any?(beside, &Theme.color_name?(theme, &1))
      assert Theme.color_name?(theme, "red")
    end

    assert Theme.color_name?(house, :brand)
    refute Theme.color_name?(Theme.default(), :brand)
  end

  @tag verifies: "themes-color-table-lookup"
  test "an entry may be a color value that resolves through the same table" do
    theme = Theme.new(colors: %{accent: color(:red), wash: {:intensity, color(:red), 0.5}})
    assert Color.resolve(color(:accent), theme, :css) == "var(--mw-accent, #c23238)"
    assert Color.resolve(color(:wash), theme, :literal) === ~RGB"#c2323880"
  end

  @tag verifies: "themes-color-table-lookup"
  test "the furniture and the series are names of the table" do
    theme = Theme.default()
    assert Color.resolve(color(:text), theme, :css) == Theme.resolve(theme, :text, :css)
    assert Color.resolve(color(:series_3), theme, :css) == "var(--mw-series-3, #c8373b)"
  end

  describe "the role colors are names by use" do
    @tag verifies: "themes-builtins-values"
    test "every built-in theme resolves each role exactly as before" do
      expected = %{
        default: [~RGB"#4ca34b", ~RGB"#bd7407", ~RGB"#c23238", ~RGB"#3b6fa8", ~RGB"#6f7480"],
        dark: [~RGB"#4f924c", ~RGB"#db8e1c", ~RGB"#ff8f8a", ~RGB"#7fb3e6", ~RGB"#b7bcc6"],
        color_safe: [~RGB"#5996d6", ~RGB"#cd6012", ~RGB"#b92931", ~RGB"#3b6fa8", ~RGB"#6f7480"],
        print: [~RGB"#5996d6", ~RGB"#cd6012", ~RGB"#b92931", ~RGB"#3b6fa8", ~RGB"#6f7480"]
      }

      for {name, literals} <- expected,
          {role, literal} <- Enum.zip(Theme.role_names(), literals) do
        theme = Theme.builtin(name)
        assert Theme.resolve(theme, role, :literal) === literal
        assert Theme.resolve(theme, role, :css) == "var(--mw-#{role}, #{Color.to_css(literal)})"
      end
    end

    @tag verifies: "themes-resolve-modes"
    test "the status roles are their ramp positions, and follow the ramp" do
      theme = Theme.new(ramps: %{status: [~RGB"#5996d6", ~RGB"#cd6012", ~RGB"#b92931"]})
      assert Theme.resolve(theme, :bad, :literal) === ~RGB"#b92931"
      assert Theme.resolve(theme, {:ramp, :status, 1}, :css) == "var(--mw-bad, #b92931)"
    end

    @tag verifies: "themes-resolve-modes"
    test "a theme may set a role's color, which then stands apart from the ramp" do
      theme = Theme.new(colors: %{bad: ~RGB"#d55e00"})
      assert Theme.resolve(theme, :bad, :css) == "var(--mw-bad, #d55e00)"
      assert Theme.resolve(theme, {:ramp, :status, 1}, :css) == "#c23238"
    end

    @tag verifies: "themes-color-table-lookup"
    test "roles: is read as colors" do
      assert Theme.new(roles: %{info: ~RGB"#2255aa"}).colors["info"] === ~RGB"#2255aa"

      assert Theme.new(roles: %{info: ~RGB"#2255aa"}, colors: %{info: ~RGB"#2266bb"}).colors[
               "info"
             ] ==
               ~RGB"#2266bb"
    end
  end
end
