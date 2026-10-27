defmodule Macaw.Layers.ColorTest do
  # Color: parsing, conversions and OKLab (spec/04 §1.1, §1.2), and color-vision
  # simulation (§1.5).
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.Color
  alias Macaw.Layers.Color.Vision

  doctest Color
  doctest Vision

  defp rgb(text), do: text |> Color.parse() |> Color.to_rgb()

  describe "parse (spec/04 §1.1)" do
    @tag verifies: "color-parse-forms"
    test "every hex length, short digits doubled and an alpha byte the opacity" do
      assert Color.parse("#abc") == %Color{r: 170, g: 187, b: 204, opacity: 1.0}
      assert Color.parse("#abcd") == %Color{r: 170, g: 187, b: 204, opacity: 221 / 255}
      assert Color.parse("#aabbcc") == %Color{r: 170, g: 187, b: 204, opacity: 1.0}
      assert Color.parse("#aabbcc80") == %Color{r: 170, g: 187, b: 204, opacity: 128 / 255}
      assert Color.parse("  #AABBCC\n") == Color.parse("#aabbcc")

      for bad <- ~w(# #a #ab #abcde #abcdefa #abcdef123 #ggg #12345z #aabbcx80),
          do: assert(Color.parse(bad) == nil, bad)
    end

    @tag verifies: "color-parse-forms"
    test "rgb and rgba with integer channels and any whitespace, hsl and hsla with % optional" do
      assert rgb("rgb(255, 102, 0)") == {255, 102, 0}
      assert rgb("RGB( 1 ,2 , 3 )") == {1, 2, 3}
      assert Color.parse("rgba(1, 2, 3, 0.5)") == %Color{r: 1, g: 2, b: 3, opacity: 0.5}
      assert rgb("rgb(300, 0, 0)") == {255, 0, 0}

      assert rgb("hsl(24, 100%, 50%)") == {255, 102, 0}
      assert rgb("hsl(24, 100, 50)") == {255, 102, 0}
      assert Color.parse("hsla(120, 100%, 50%, 0.5)") == %Color{r: 0, g: 255, b: 0, opacity: 0.5}

      for bad <- [
            "rgb(10%, 0, 0)",
            "rgb(1, 2)",
            "rgb(1, 2, 3) red",
            "xrgb(1,2,3)",
            "hsl(1, 2)",
            "hsl(a, b, c)"
          ],
          do: assert(Color.parse(bad) == nil, bad)
    end

    @tag verifies: "color-parse-forms"
    test "the 148 keywords, case-insensitively and trimmed; named gives a keyword's hex" do
      names = Color.named_colors()
      assert length(names) == 148 and names == Enum.sort(names)
      assert Enum.all?(["rebeccapurple", "gray", "grey", "steelblue"], &(&1 in names))

      for name <- names do
        assert %Color{} = color = Color.parse(name)
        assert Color.parse(" " <> String.upcase(name) <> " ") == color
        assert Color.to_hex(color) == Color.named(name)
      end

      assert Color.named("SteelBlue") == "#4682b4"
      assert Color.named("rebeccapurple") == "#663399"
      assert Color.named("nope") == nil
    end

    @tag verifies: "color-parse-forms"
    test "any other text and anything not a binary is nil" do
      for bad <- ["", "  ", "notacolor", "red blue", "#", "transparent"],
          do: assert(Color.parse(bad) == nil, bad)

      for bad <- [nil, :red, 1, ~c"#fff", %{}], do: assert(Color.parse(bad) == nil)
    end
  end

  describe "constructors and conversions (spec/04 §1.2)" do
    @tag verifies: "color-conversions-exact"
    test "constructors clamp; rgb keeps fractions, hsl wraps its hue and rounds" do
      assert Color.rgb(-5, 300, 12.5, 2) == %Color{r: 0, g: 255, b: 12.5, opacity: 1}
      assert Color.rgb(1, 2, 3, -1).opacity == 0
      assert Color.hsl(384, 100, 50) == Color.hsl(24, 100, 50)
      assert Color.hsl(-336, 100, 50) == Color.hsl(24, 100, 50)
      assert Color.to_rgb(Color.hsl(24, 150, 50)) == {255, 102, 0}
      assert Color.to_rgb(Color.hsl(0, 0, 50)) == {128, 128, 128}
    end

    @tag verifies: "color-conversions-exact"
    property "lab of to_lab is the color, and a gray has a and b zero" do
      check all(r <- integer(0..255), g <- integer(0..255), b <- integer(0..255)) do
        color = Color.rgb(r, g, b)
        %{l: l, a: a, b: bb, opacity: o} = Color.to_lab(color)
        assert Color.to_rgb(Color.lab(l, a, bb, o)) == {r, g, b}

        gray = Color.to_lab(Color.rgb(r, r, r))
        assert gray.a == 0.0 and gray.b == 0.0
      end
    end

    @tag verifies: "color-conversions-exact"
    test "Lab against D50 gives the CIE values of the sRGB primaries, and hcl is its polar form" do
      for {hex, {l, a, b}} <- [
            {"#ff0000", {54.2917, 80.8125, 69.8851}},
            {"#0000ff", {29.5676, 68.2986, -112.0294}}
          ] do
        lab = Color.to_lab(Color.parse(hex))
        assert_in_delta lab.l, l, 0.01
        assert_in_delta lab.a, a, 0.01
        assert_in_delta lab.b, b, 0.01

        hcl = Color.to_hcl(Color.parse(hex))
        assert_in_delta hcl.c, :math.sqrt(a * a + b * b), 0.01
        assert Color.to_hex(Color.hcl(hcl.h, hcl.c, hcl.l)) == hex
      end

      white = Color.to_lab(Color.parse("#fff"))
      assert_in_delta white.l, 100.0, 1.0e-4
    end

    @tag verifies: "color-conversions-exact"
    test "to_hsl, to_hex and to_string" do
      assert Color.to_hsl(Color.parse("#ff6600")) == %{h: 24.0, s: 100.0, l: 50.0, opacity: 1.0}
      assert Color.to_hsl(Color.parse("#808080")).s == 0.0
      assert Color.to_rgba(Color.rgb(1.4, 2.6, 3, 0.5)) == {1, 3, 3, 0.5}
      assert Color.to_hex(Color.rgb(255, 102, 0)) == "#ff6600"
      assert Color.to_hex(Color.rgb(255, 102, 0, 0.5)) == "#ff660080"
      assert Color.to_string(Color.rgb(255, 102, 0)) == "rgb(255, 102, 0)"
      assert Color.to_string(Color.rgb(255, 102, 0, 0.5)) == "rgba(255, 102, 0, 0.5)"
    end

    @tag verifies: "color-conversions-exact"
    test "luminance and contrast follow WCAG 2" do
      assert Color.luminance(Color.parse("#fff")) == 1.0
      assert Color.luminance(Color.parse("#000")) == 0.0
      assert Color.contrast(Color.parse("#fff"), Color.parse("#000")) == 21.0
      assert Color.contrast(Color.parse("#000"), Color.parse("#fff")) == 21.0
      assert Color.contrast(Color.parse("#777"), Color.parse("#777")) == 1.0
      # #767676 is the lightest gray that reaches 4.5 on white.
      assert Color.contrast(Color.parse("#767676"), Color.parse("#fff")) >= 4.5
      assert Color.contrast(Color.parse("#777777"), Color.parse("#fff")) < 4.5
    end

    @tag verifies: "color-conversions-exact"
    test "each manipulation follows its formula" do
      c = Color.parse("steelblue")
      lab = Color.to_lab(c)

      assert Color.brighter(c) == Color.lab(lab.l + 18, lab.a, lab.b)
      assert Color.darker(c, 2) == Color.lab(lab.l - 36, lab.a, lab.b)
      assert_in_delta Color.to_lab(Color.brighter(c)).l, lab.l + 18, 0.5
      assert Color.brighter(c, 0) == Color.lab(lab.l, lab.a, lab.b)

      hsl = Color.to_hsl(c)
      assert Color.saturate(c) == Color.hsl(hsl.h, hsl.s * 1.2, hsl.l)
      assert Color.desaturate(c) == Color.hsl(hsl.h, hsl.s * 0.8, hsl.l)
      assert Color.rotate(c, 180) == Color.hsl(hsl.h + 180, hsl.s, hsl.l)

      assert Color.grayscale(Color.rgb(255, 0, 0)) == Color.rgb(76, 76, 76)
      assert Color.invert(Color.rgb(255, 102, 0, 0.5)) == Color.rgb(0, 153, 255, 0.5)
      assert Color.with_opacity(c, 3).opacity == 1 and Color.with_opacity(c, 0.25).opacity == 0.25
      assert Color.mix(Color.rgb(0, 0, 0), Color.rgb(255, 100, 1)) == Color.rgb(127.5, 50.0, 0.5)
    end

    @tag verifies: "color-conversions-exact"
    test "each interpolation follows its space, hues the shorter way, t unclamped" do
      a = Color.rgb(0, 0, 0, 0)
      b = Color.rgb(200, 100, 50, 1)
      assert Color.interpolate_rgb(a, b, 0.25) == %Color{r: 50.0, g: 25.0, b: 12.5, opacity: 0.25}
      assert Color.interpolate_rgb(a, b, 2).r == 400

      red_ish = Color.hsl(350, 100, 50)
      orange_ish = Color.hsl(10, 100, 50)
      assert Color.to_hsl(Color.interpolate_hsl(red_ish, orange_ish, 0.5)).h == 0.0

      x = Color.parse("#3b6fa8")
      y = Color.parse("#d9730d")
      lx = Color.to_lab(x)
      ly = Color.to_lab(y)

      assert Color.interpolate_lab(x, y, 0.5) ==
               Color.lab((lx.l + ly.l) / 2, (lx.a + ly.a) / 2, (lx.b + ly.b) / 2)

      hx = Color.to_hcl(Color.hcl(350, 40, 50))
      hy = Color.to_hcl(Color.hcl(20, 40, 50))

      assert_in_delta Color.to_hcl(
                        Color.interpolate_hcl(Color.hcl(350, 40, 50), Color.hcl(20, 40, 50), 0.5)
                      ).h,
                      rem(round((hx.h + hy.h + 360) / 2), 360),
                      2.0
    end
  end

  describe "OKLab and OKLCH (spec/04 §1.2)" do
    # CSS Color 4 §9: sRGB to XYZ (D65) to LMS to OKLab, the specification's own matrices.
    @rgb_xyz [
      [0.41239079926595934, 0.357584339383878, 0.1804807884018343],
      [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
      [0.01933081871559182, 0.11919477979462598, 0.9505321522496607]
    ]
    @xyz_lms [
      [0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
      [0.0329836539323885, 0.9292868615863434, 0.0361446663506424],
      [0.0481771893596242, 0.2642395317527308, 0.6335478284694309]
    ]
    @lms_oklab [
      [0.2104542683093140, 0.7936177747023054, -0.0040720430116193],
      [1.9779985324311684, -2.4285922420485799, 0.4505937096174110],
      [0.0259040424655478, 0.7827717124575296, -0.8086757549230774]
    ]

    defp mul(m, v),
      do:
        Enum.map(m, fn row ->
          row |> Enum.zip(v) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
        end)

    defp lin(c) when c <= 0.04045, do: c / 12.92
    defp lin(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

    defp ref_oklab(hex) do
      %Color{r: r, g: g, b: b} = Color.parse(hex)

      [r, g, b]
      |> Enum.map(&lin(&1 / 255))
      |> then(&mul(@rgb_xyz, &1))
      |> then(&mul(@xyz_lms, &1))
      |> Enum.map(&:math.pow(&1, 1 / 3))
      |> then(&mul(@lms_oklab, &1))
    end

    @tag verifies: "color-conversions-exact"
    test "the primaries convert to their published values, white is L 1 and a gray has no chroma" do
      for {hex, {l, a, b}, {c, h}} <- [
            {"#ff0000", {0.62796, 0.22486, 0.12585}, {0.25768, 29.2339}},
            {"#00ff00", {0.86644, -0.23389, 0.1795}, {0.29483, 142.4953}},
            {"#0000ff", {0.45201, -0.03246, -0.31153}, {0.31321, 264.052}}
          ] do
        lab = Color.to_oklab(Color.parse(hex))
        lch = Color.to_oklch(Color.parse(hex))
        assert_in_delta lab.l, l, 1.0e-4
        assert_in_delta lab.a, a, 1.0e-4
        assert_in_delta lab.b, b, 1.0e-4
        assert_in_delta lch.c, c, 1.0e-4
        assert_in_delta lch.h, h, 1.0e-2
      end

      assert_in_delta Color.to_oklab(Color.parse("#ffffff")).l, 1.0, 1.0e-6

      assert_in_delta Color.to_oklch(Color.parse("#808080")).c, 0.0, 1.0e-6
    end

    @tag verifies: "color-conversions-exact"
    test "the library's matrices agree with CSS Color 4's XYZ route, and oklab and oklch invert them" do
      for hex <- ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #e9f2fc #1b1e24 #bd7407) do
        %{l: l, a: a, b: b} = Color.to_oklab(Color.parse(hex))
        [rl, ra, rb] = ref_oklab(hex)
        assert_in_delta l, rl, 1.0e-6
        assert_in_delta a, ra, 1.0e-6
        assert_in_delta b, rb, 1.0e-6
        assert Color.to_hex(Color.oklab(l, a, b)) == hex

        %{l: l, c: c, h: h} = Color.to_oklch(Color.parse(hex))
        assert Color.to_hex(Color.oklch(l, c, h)) == hex
      end
    end

    @tag verifies: "color-conversions-exact"
    test "an out-of-gamut OKLCH is chroma-reduced at its lightness and hue to within 0.02; past either end is white or black" do
      for {l, c, h} <- [{0.7, 0.4, 150}, {0.5, 0.35, 30}, {0.9, 0.3, 260}] do
        mapped = Color.oklch(l, c, h)
        %{r: r, g: g, b: b} = mapped
        assert Enum.all?([r, g, b], &(&1 >= 0 and &1 <= 255))
        assert Color.to_oklch(mapped).c < c

        # Some chroma below c, at the same lightness and hue, is within the just-noticeable
        # difference of the color it was clipped to.
        %{l: ml, a: ma, b: mb} = Color.to_oklab(mapped)
        rad = h * :math.pi() / 180

        assert Enum.any?(0..400, fn i ->
                 chroma = c * i / 400

                 :math.sqrt(
                   (ml - l) ** 2 + (ma - chroma * :math.cos(rad)) ** 2 +
                     (mb - chroma * :math.sin(rad)) ** 2
                 ) < 0.02
               end)
      end

      assert Color.to_hex(Color.oklch(1.2, 0.2, 40)) == "#ffffff"
      assert Color.to_hex(Color.oklab(0, 0.1, 0.1)) == "#000000"

      assert_in_delta Color.delta_eok(Color.parse("#ff0000"), Color.parse("#ff0000")),
                      0.0,
                      1.0e-12
    end
  end

  describe "color-vision simulation (spec/04 §1.5)" do
    defp hex(string, deficiency),
      do: string |> Color.parse() |> Vision.simulate(deficiency) |> Color.to_hex()

    @tag verifies: "color-vision-machado"
    test "the matrices are the paper's severity 1.0 matrices, and every row sums to one" do
      assert Vision.deficiencies() == [:protanopia, :deuteranopia, :tritanopia]

      assert Vision.matrix(:protanopia) == [
               [0.152286, 1.052583, -0.204868],
               [0.114503, 0.786281, 0.099216],
               [-0.003882, -0.048116, 1.051998]
             ]

      assert Vision.matrix(:deuteranopia) == [
               [0.367322, 0.860646, -0.227968],
               [0.280085, 0.672501, 0.047413],
               [-0.011820, 0.042940, 0.968881]
             ]

      assert Vision.matrix(:tritanopia) == [
               [1.255528, -0.076749, -0.178779],
               [-0.078411, 0.930809, 0.147602],
               [0.004733, 0.691367, 0.303900]
             ]

      for deficiency <- Vision.deficiencies(),
          row <- Vision.matrix(deficiency),
          do: assert_in_delta(Enum.sum(row), 1.0, 1.0e-5)
    end

    @tag verifies: "color-vision-machado"
    property "a gray is its own simulation under every deficiency" do
      check all(v <- integer(0..255), deficiency <- member_of(Vision.deficiencies())) do
        assert Color.to_rgb(Vision.simulate(Color.rgb(v, v, v), deficiency)) == {v, v, v}
      end
    end

    @tag verifies: "color-vision-machado"
    test "the primaries, worked by hand through the linear-light model, and red and green collapse for red-green" do
      assert hex("#ff0000", :protanopia) == "#6d5f00"
      assert hex("#ff0000", :deuteranopia) == "#a39000"
      assert hex("#00ff00", :protanopia) == "#ffe500"
      assert hex("#0000ff", :tritanopia) == "#006b96"

      hue = fn color -> color |> Color.parse() |> Color.to_hcl() |> Map.fetch!(:h) end
      arc = fn a, b -> min(abs(a - b), 360 - abs(a - b)) end

      for deficiency <- [:protanopia, :deuteranopia],
          do:
            assert(arc.(hue.(hex("#4ca34b", deficiency)), hue.(hex("#c23238", deficiency))) < 30)

      assert arc.(hue.(hex("#4ca34b", :tritanopia)), hue.(hex("#c23238", :tritanopia))) > 90
    end

    @tag verifies: "color-vision-machado"
    test "none is the color, the opacity is kept, an unknown deficiency is refused, and recolor spares url references" do
      color = Color.rgb(12, 200, 99, 0.5)
      assert Vision.simulate(color, :none) == color
      assert Vision.simulate(color, :deuteranopia).opacity == 0.5

      assert_raise ArgumentError, ~r/:achromatopsia is not a deficiency/, fn ->
        Vision.simulate(color, :achromatopsia)
      end

      assert_raise ArgumentError, fn -> Vision.matrix(:none) end

      svg =
        ~s|<g fill="#ff0000" style="stroke: #f00"><rect fill="url(#bad)" id="abc"/><text>#ff0000</text></g>|

      assert Vision.recolor(svg, :protanopia) ==
               ~s|<g fill="#6d5f00" style="stroke: #6d5f00"><rect fill="url(#bad)" id="abc"/><text>#ff0000</text></g>|

      assert Vision.recolor(svg, :none) == svg
      assert_raise ArgumentError, fn -> Vision.recolor(svg, :mono) end
    end
  end
end
