defmodule Macaw.Layers.ColorTermsTest do
  # The literal color as a term (spec/04 §1.1) and its adapters (§1.6): text in by parse!/1
  # and ~RGB, CSS out by to_css/1, and JSON by Color.Form's `$rgb`.
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Color, Document, Form}
  alias Macaw.Layers.Color.Form, as: ColorForm
  alias Macaw.Layers.Theme.Document, as: ThemeDocument

  doctest ColorForm

  # A literal a hex writes exactly: whole channels, an opacity in 255ths.
  defp exact do
    gen all(
          r <- integer(0..255),
          g <- integer(0..255),
          b <- integer(0..255),
          k <- integer(0..255)
        ) do
      Color.rgb(r, g, b, k / 255)
    end
  end

  # Any literal, its fields floats anywhere in their ranges.
  defp literal do
    gen all(
          r <- float(min: 0.0, max: 255.0),
          g <- float(min: 0.0, max: 255.0),
          b <- float(min: 0.0, max: 255.0),
          a <- float(min: 0.0, max: 1.0)
        ) do
      Color.rgb(r, g, b, a)
    end
  end

  defp fields(%Color{r: r, g: g, b: b, opacity: a}), do: [r, g, b, a]

  describe "the literal color (spec/04 §1.1)" do
    @tag verifies: "color-literal-canonical"
    property "every constructor builds the canonical struct" do
      check all(
              r <- integer(-10..270),
              g <- float(min: -10.0, max: 270.0),
              b <- integer(0..255),
              a <- float(min: -0.5, max: 1.5),
              h <- integer(-400..400),
              t <- float(min: -1.0, max: 2.0)
            ) do
        base = Color.rgb(r, g, b, a)

        built = [
          base,
          Color.hsl(h, abs(g), b / 2.55, a),
          Color.lab(b / 2.55, g - 128, r - 128, a),
          Color.hcl(h, abs(r) / 2, b / 2.55, a),
          Color.oklab(b / 255, 0.1, -0.1, a),
          Color.oklch(b / 255, 0.2, h, a),
          Color.parse(Color.to_hex(base)),
          Color.brighter(base),
          Color.darker(base),
          Color.saturate(base),
          Color.rotate(base, h),
          Color.grayscale(base),
          Color.invert(base),
          Color.with_opacity(base, t),
          Color.interpolate_rgb(base, Color.rgb(255, 0, 0), t),
          Color.interpolate_hsl(base, Color.rgb(0, 0, 255), t),
          Color.interpolate_lab(base, Color.rgb(0, 255, 0), t),
          Color.interpolate_hcl(base, Color.rgb(9, 9, 9), t),
          Color.mix(base, Color.rgb(1, 2, 3))
        ]

        for color <- built, do: assert(Color.literal?(color), inspect(color))
      end
    end

    @tag verifies: "color-literal-canonical"
    test "literal? refuses a struct written by hand with integer fields, out of range or with a negative zero" do
      assert Color.literal?(%Color{})
      refute Color.literal?(%Color{r: 59, g: 111, b: 168, opacity: 1})
      refute Color.literal?(%Color{r: 59.0, g: 111.0, b: 168.0, opacity: 1})
      refute Color.literal?(%Color{r: 300.0, g: 0.0, b: 0.0, opacity: 1.0})
      refute Color.literal?(%Color{r: 0.0, g: 0.0, b: 0.0, opacity: 1.5})
      refute Color.literal?(%Color{r: -0.0, g: 0.0, b: 0.0, opacity: 1.0})
      refute Color.literal?(Map.put(%Color{}, :extra, 1))
      refute Color.literal?("#3b6fa8")
      refute Color.literal?(%{r: 0.0, g: 0.0, b: 0.0, opacity: 1.0})

      # A negative zero in is the zero out, so two blacks are one term.
      assert Color.rgb(-0.0, 0, 0) === Color.rgb(0, 0, 0)
      assert Color.literal?(Color.rgb(-0.0, -0.0, -0.0, -0.0))
    end

    @tag verifies: "color-literal-canonical"
    test "white parsed and white built are one term, of one digest" do
      assert Color.parse!("white") === Color.rgb(255, 255, 255)
      assert Document.digest(Color.parse!("white")) == Document.digest(Color.rgb(255, 255, 255))
      assert Document.digest(~RGB"#fff") == Document.digest(Color.rgb(255.0, 255.0, 255.0, 1))
    end

    @tag verifies: "color-literal-canonical"
    property "equal colors built by different constructors are one term, of one digest" do
      check all(
              r <- integer(0..255),
              g <- integer(0..255),
              b <- integer(0..255),
              k <- integer(0..255)
            ) do
        hex =
          "#" <>
            Enum.map_join(
              [r, g, b, k],
              &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0"))
            )

        by_integers = Color.rgb(r, g, b, k / 255)
        by_floats = Color.rgb(r * 1.0, g * 1.0, b * 1.0, k / 255)
        parsed = Color.parse!(hex)
        {:ok, read} = ColorForm.decode_value("$rgb", fields(by_integers))
        %{h: h, s: s, l: l} = Color.to_hsl(by_integers)
        through_hsl = Color.hsl(h, s, l, k / 255)

        for other <- [by_floats, parsed, read] do
          assert other === by_integers
          assert Document.digest(other) == Document.digest(by_integers)
        end

        # hsl rounds its channels, so it builds the color whenever they round back to it.
        if through_hsl == by_integers,
          do: assert(Document.digest(through_hsl) == Document.digest(by_integers))
      end
    end

    @tag verifies: "color-literal-canonical"
    test "name? holds of lower-case words, the grammar a theme's names meet" do
      for name <- [:info, :series_3, "info", "a", "z9_x"],
          do: assert(Color.name?(name), inspect(name))

      for name <- ["Info", "3d", "_x", "a-b", "a b", "", "é", nil, true, false, 3, {:color, :red}],
          do: refute(Color.name?(name), inspect(name))
    end
  end

  describe "text in, CSS out (spec/04 §1.6)" do
    @tag verifies: "color-adapters-edges"
    property "parse! of to_css is the color for every 8-bit-exact literal, written as hex" do
      check all(color <- exact()) do
        css = Color.to_css(color)
        assert css =~ ~r/\A#[0-9a-f]{6}(?:[0-9a-f]{2})?\z/
        assert byte_size(css) == if(color.opacity < 1, do: 9, else: 7)
        assert Color.parse!(css) === color
      end
    end

    @tag verifies: "color-adapters-edges"
    property "parse! of to_css is the color for a literal that is not 8-bit exact, written as rgb()" do
      check all(color <- literal()) do
        css = Color.to_css(color)
        if not Color.exact?(color), do: assert(css =~ ~r/\Argb\([^,]+ \/ [^,]+\)\z/)
        assert Color.parse!(css) === color
      end
    end

    @tag verifies: "color-adapters-edges"
    test "to_css writes hex where exact and rgb() otherwise" do
      assert Color.to_css(Color.rgb(59, 111, 168)) == "#3b6fa8"
      assert Color.to_css(Color.rgb(59, 111, 168, 128 / 255)) == "#3b6fa880"
      assert Color.to_css(Color.rgb(59, 111, 168, 0.5)) == "rgb(59.0 111.0 168.0 / 0.5)"
      assert Color.to_css(Color.rgb(59.25, 111, 168)) == "rgb(59.25 111.0 168.0 / 1.0)"
      assert Color.parse("rgb(1 2 3)") === Color.rgb(1, 2, 3)
      assert Color.parse("rgb( 1.5 2e1 3.0e-1 / 0.25 )") === Color.rgb(1.5, 20, 0.3, 0.25)
      assert Color.parse("rgb(1 2 3 /)") == nil
      assert Color.parse("rgb(1 2)") == nil
    end

    @tag verifies: "color-adapters-edges"
    test "parse! raises naming the text it does not read" do
      assert Color.parse!(" SteelBlue ") === Color.parse("steelblue")
      assert_raise ArgumentError, ~r/"nope"/, fn -> Color.parse!("nope") end
    end

    @tag verifies: "color-adapters-edges"
    test "the sigil compiles a literal in, and text it does not read is a compile error" do
      assert ~RGB"#3b6fa8" === Color.rgb(59, 111, 168)
      assert ~RGB[steelblue] === Color.parse!("steelblue")
      assert Color.literal?(~RGB"#3b6fa880")

      source = ~S'''
      import Macaw.Layers.Color, only: [sigil_RGB: 2]
      ~RGB"nope"
      '''

      assert_raise CompileError, ~r/~RGB: not a color: "nope"/, fn ->
        Code.compile_string(source, "nope.exs")
      end

      modified = ~S'''
      import Macaw.Layers.Color, only: [sigil_RGB: 2]
      ~RGB"#fff"x
      '''

      assert_raise CompileError, ~r/takes no modifiers/, fn ->
        Code.compile_string(modified, "modified.exs")
      end
    end
  end

  describe "JSON, by Color.Form (spec/04 §1.6)" do
    @tag verifies: "color-adapters-json"
    property "the $rgb payload of any literal decodes to that literal, as hex where exact" do
      check all(color <- one_of([exact(), literal()])) do
        assert {:ok, %{"$rgb" => payload}} = ColorForm.encode_value(color)

        if Color.exact?(color),
          do: assert(payload == Color.to_hex(color)),
          else: assert(payload == fields(color))

        assert ColorForm.decode_value("$rgb", payload) == {:ok, color}
        # Through JSON's text too: a float's shortest form reads back as that float.
        assert ColorForm.decode_value("$rgb", payload |> JSON.encode!() |> JSON.decode!()) ==
                 {:ok, color}
      end
    end

    @tag verifies: "color-adapters-json"
    test "a payload that is no color is :default, and a struct that is not a literal has no form" do
      for bad <- [
            "steelblue",
            "#fff",
            "#3b6fa",
            "#3b6fa8f",
            "#3b6fa8zz",
            [1, 2, 3],
            [1, 2, 3, 4],
            [256, 0, 0, 1],
            [-1, 0, 0, 1],
            ["1", 0, 0, 1],
            %{"r" => 1},
            nil
          ],
          do: assert(ColorForm.decode_value("$rgb", bad) == :default, inspect(bad))

      assert ColorForm.decode_value("$rgb", "#3B6FA8") == {:ok, Color.rgb(59, 111, 168)}
      assert ColorForm.decode_value("$rgb", [59, 111, 168, 1]) == {:ok, Color.rgb(59, 111, 168)}
      assert ColorForm.encode_value(%Color{r: 59, g: 111, b: 168, opacity: 1}) == :default
      assert "$rgb" in ColorForm.tags()
    end

    @tag verifies: "color-adapters-json"
    property "a theme document's map form carries a literal through $rgb, and refuses a malformed one at its path" do
      check all(color <- one_of([exact(), literal()])) do
        value = %{theme: %{axis: color}}
        assert {:ok, map} = Form.to_map(value, ThemeDocument)
        assert %{"theme" => %{"axis" => %{"$rgb" => _}}} = map
        assert Form.from_map(map, ThemeDocument) == {:ok, value}

        assert Form.from_map(map |> JSON.encode!() |> JSON.decode!(), ThemeDocument) ==
                 {:ok, value}
      end

      bad = %{"theme" => %{"axis" => %{"$rgb" => "steelblue"}}}

      assert {:error, [{[:theme, :axis], {:unknown_tag, "$rgb"}}]} =
               Form.from_map(bad, ThemeDocument)
    end
  end
end
