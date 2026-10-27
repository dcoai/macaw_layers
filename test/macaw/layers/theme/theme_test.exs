defmodule Macaw.Layers.Theme.ThemeTest do
  @moduledoc "`Macaw.Layers.Theme` (spec/04 §2.1, §3.1, §3.2): slots, both modes, both themes' contrast."
  use ExUnit.Case, async: true

  alias Macaw.Layers.Theme

  doctest Theme

  @fixed ~w(axis grid text background surface good warning bad info neutral font_family font_size
             label_size title_size)a

  describe "slots" do
    @tag verifies: "themes-slots-order"
    test "series first, then the fixed slots, for both themes" do
      series = Enum.map(1..10, &:"series_#{&1}")
      assert Theme.slots(Theme.default()) == series ++ @fixed
      assert Theme.slots(Theme.dark()) == series ++ @fixed
      assert Theme.slots(Theme.new(series: ["#000"])) == [:series_1 | @fixed]
    end

    @tag verifies: "themes-slots-order"
    test "{:series, i} cycles over the palette" do
      theme = Theme.new(series: ~w(#111 #222 #333))
      assert Theme.series_slot(theme, 1) == :series_1
      assert Theme.series_slot(theme, 3) == :series_3
      assert Theme.series_slot(theme, 4) == :series_1
      assert Theme.resolve(theme, {:series, 5}, :literal) == "#222"
      assert Theme.resolve(theme, {:series, 5}, :css) == "var(--mw-series-2, #222)"
      assert_raise ArgumentError, fn -> Theme.series_slot(theme, 0) end
    end

    @tag verifies: "themes-slots-order"
    test "an unknown slot, or a series slot beyond the palette, is an ArgumentError" do
      theme = Theme.new(series: ~w(#111 #222))
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :series_3, :literal) end
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :series_0, :css) end
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :accent, :css) end
      # css_name/1 maps any name of lower-case words (spec/04 §2.2, §3.1), a host's own
      # names included, so it refuses only a name that is not one.
      assert_raise ArgumentError, fn -> Theme.css_name("Accent") end
    end
  end

  describe "resolve/3" do
    @tag verifies: "themes-resolve-modes"
    test ":literal is the stored value, a number for a size" do
      theme = Theme.default()
      assert Theme.resolve(theme, :series_1, :literal) == "#3b6fa8"
      assert Theme.resolve(theme, :axis, :literal) == "#666666"
      assert Theme.resolve(theme, :font_family, :literal) == "sans-serif"
      assert Theme.resolve(theme, :font_size, :literal) == 10
      assert Theme.resolve(theme, :label_size, :literal) == 12
      assert Theme.resolve(theme, :title_size, :literal) == 16
    end

    @tag verifies: "themes-resolve-modes"
    test ":css is a var() reference carrying the literal, sizes in px" do
      theme = Theme.dark()
      assert Theme.resolve(theme, :series_10, :css) == "var(--mw-series-10, #b7bcc6)"
      assert Theme.resolve(theme, :background, :css) == "var(--mw-background, #1b1e24)"
      assert Theme.resolve(theme, :font_family, :css) == "var(--mw-font-family, sans-serif)"
      assert Theme.resolve(theme, :font_size, :css) == "var(--mw-font-size, 10px)"
    end

    @tag verifies: "themes-resolve-modes"
    test "css_name hyphenates the slot" do
      assert Theme.css_name(:series_1) == "--mw-series-1"
      assert Theme.css_name(:font_family) == "--mw-font-family"
    end
  end

  describe ":surface" do
    @builtin [Theme.default(), Theme.dark()]

    @tag verifies: "themes-builtins-values"
    test "every built-in theme answers it, and lists it among its slots and color slots" do
      for theme <- @builtin do
        assert is_binary(Theme.resolve(theme, :surface, :literal))
        assert :surface in Theme.slots(theme)
        assert :surface in Theme.color_slots(theme)
      end

      assert Theme.default().surface == "#eef2f6"
      assert Theme.dark().surface == "#23272f"
    end

    @tag verifies: "themes-floors-builtins"
    test "differs from :grid in both palettes, so the grid drawn over it stays visible" do
      for theme <- @builtin do
        refute String.downcase(theme.surface) == String.downcase(theme.grid),
               "#{theme.name}: :surface swallows the :grid drawn over it"
      end
    end

    @tag verifies: "themes-builtins-values"
    test "a host theme from new/1 that names none takes the light one, as any field" do
      assert Theme.new(background: "#000000").surface == Theme.default().surface
      assert Theme.new(surface: "#101010").surface == "#101010"
    end
  end

  describe "new/1 and merge/2" do
    @tag verifies: "themes-builtins-values"
    test "replace fields over the default or any theme" do
      theme = Theme.new(font_family: "Inter, sans-serif", axis: "#123456")
      assert theme.name == :default
      assert theme.font_family == "Inter, sans-serif"
      assert theme.series == Theme.default().series
      assert Theme.merge(Theme.dark(), name: :night).name == "night"
      assert Theme.merge(Theme.dark(), name: :night).background == "#1b1e24"
    end

    @tag verifies: "themes-builtins-values"
    test "an unknown field is a KeyError and an empty series an ArgumentError" do
      assert_raise KeyError, fn -> Theme.new(accent: "#fff") end
      assert_raise ArgumentError, fn -> Theme.new(series: []) end
    end
  end

  describe "ink/2: the contrast ink (spec/04 §3.2)" do
    alias Macaw.Layers.Color

    defp ratio(a, b), do: Color.contrast(Color.parse(a), Color.parse(b))

    @tag verifies: "themes-ink-aa"
    test "dark ink on a light fill and light ink on a dark fill, on both themes" do
      for theme <- [Theme.default(), Theme.dark()] do
        {dark, light} =
          if theme.name == :dark,
            do: {theme.background, theme.text},
            else: {theme.text, theme.background}

        assert Theme.ink(theme, "#fff2b0") == dark
        assert Theme.ink(theme, "#1a2a5a") == light
      end
    end

    @tag verifies: "themes-ink-aa"
    test "nothing under the text is the theme's background, whose ink is its text" do
      assert Theme.ink(Theme.default(), nil) == "#333333"
      assert Theme.ink(Theme.dark(), nil) == "#e6e6e6"
      assert Theme.ink(Theme.default(), "not a color") == "#333333"
      assert Theme.ink(Theme.default(), Color.parse("#000000")) == "#ffffff"
    end

    @tag verifies: "themes-ink-aa"
    test "black or white when neither slot reaches 4.5:1, and the ink always does" do
      # A mid gray fails both #333333 and white; black holds 4.6:1 against it.
      assert Theme.ink(Theme.default(), "#777777") == "#000000"

      for r <- 0..255//15, g <- 0..255//15, b <- 0..255//15 do
        under = Color.to_hex(Color.rgb(r, g, b))

        for theme <- [Theme.default(), Theme.dark()] do
          ink = Theme.ink(theme, under)
          assert ratio(ink, under) >= 4.5, "#{ink} on #{under}: #{ratio(ink, under)}"
        end
      end
    end

    @tag verifies: "themes-ink-aa"
    test "text wins a tie, and a slot that does not parse is skipped" do
      same = Theme.new(text: "#ffffff", background: "#ffffff")
      assert Theme.ink(same, "#000000") == "#ffffff"

      odd = Theme.new(text: "currentColor")
      assert Theme.ink(odd, "#1a2a5a") == "#ffffff"
    end
  end
end
