defmodule Macaw.Layers.Theme.TermsTest do
  @moduledoc """
  A theme's colors are terms (spec/04 §1.3, §2.1, §5): a typed color's leaves are literal
  `%Macaw.Layers.Color{}` and never strings; every built-in resolves, compiles and checks
  exactly as v0.2.4 did; and a v0.2.4 theme document, version 1, reads to the same theme.

  The fixtures under `test/fixtures/themes_v0_2_4/` were written by v0.2.4 itself, from a
  checkout of the tag: each built-in and the host theme `house/0` below, resolved
  (`resolved.json`, every slot and name in both modes, less the `:css` reference of each
  CSS keyword the table takes from CSS, which the test derives), compiled to a stylesheet
  (`stylesheet.css`), and written as theme documents (`documents.json`) and as one bundle
  per theme (`bundles.json`).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Bundle, Color, Form, Theme}
  alias Macaw.Layers.Theme.{Document, Sheet}

  @fixtures Path.expand("../../../fixtures/themes_v0_2_4", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
  defp fixture_json(name), do: name |> fixture() |> JSON.decode!()

  # The host theme the fixtures hold, as v0.2.4 built it from text, here from terms: pinned
  # steps, a literal operand in each transform, a name as an anchor and literal paints. The
  # anchor names the host's color by its string: new/1 reads the names of `colors` that way
  # but not yet a ramp's (#13), and a document reads both so.
  defp house do
    Theme.new(
      name: :house,
      series: [~RGB"#2f5d8a", ~RGB"#b5651d", ~RGB"#a23b3b"],
      background: ~RGB"#fbfaf6",
      font_family: "Georgia, serif",
      ramps: %{
        status: [~RGB"#4ca34b", ~RGB"#bd7407", ~RGB"#c23238"],
        sequential: [~RGB"#e9f2fc", {:color, "brand"}, ~RGB"#004580"]
      },
      colors: %{
        red: %{500 => ~RGB"#d62728", 100 => ~RGB"#fde8e8", 900 => ~RGB"#5c0f10"},
        brand: ~RGB"#2f5d8a",
        accent: {:lighten, {:color, :brand}, 0.2},
        wash: {:alpha, ~RGB"#2f5d8a", 0.5},
        mix: {:blend, [{:intensity, ~RGB"#b5651d", 0.6}, {:color, :brand}]},
        ink: {:contrast, ~RGB"#2f5d8a"},
        deep: {:shade, {:color, :red}, 900}
      },
      styles: %{
        grid: %{stroke: %{type: :solid, color: ~RGB"#d0d0d0"}},
        hover: %{stroke: %{type: :solid, color: {:darken, ~RGB"#333333", 0.1}, width: 2}}
      }
    )
  end

  defp themes, do: [Theme.default(), Theme.dark(), Theme.color_safe(), Theme.print(), house()]

  # -- typed trees --------------------------------------------------------------------

  # A typed color of depth at most `depth`, its leaves literals, names of the default
  # table, series and ramp positions.
  defp leaf do
    one_of([
      literal(),
      member_of([:red, :blue, :amber, :text, :series_2, :bad, :steelblue]) |> map(&{:color, &1}),
      integer(1..12) |> map(&{:series, &1}),
      bind(member_of(Theme.ramp_names()), fn r -> map(unit(), &{:ramp, r, &1}) end),
      constant({:contrast, :under})
    ])
  end

  defp tree(0), do: leaf()

  defp tree(depth) do
    sub = tree(depth - 1)

    frequency([
      {2, leaf()},
      {3,
       bind(member_of(Color.Typed.unary()), fn op ->
         map({sub, unit()}, fn {c, t} -> {op, c, t} end)
       end)},
      {1, map({sub, integer(0..1000)}, fn {c, n} -> {:shade, c, n} end)},
      {2, map(list_of(sub, min_length: 1, max_length: 3), &{:blend, &1})},
      {1, map(sub, &{:contrast, &1})}
    ])
  end

  defp unit, do: map(integer(0..1000), &(&1 / 1000))

  defp literal do
    one_of([
      map({integer(0..255), integer(0..255), integer(0..255), integer(0..255)}, fn {r, g, b, a} ->
        Color.rgb(r, g, b, a / 255)
      end),
      map({float(min: 0.0, max: 255.0), float(min: 0.0, max: 1.0)}, fn {v, a} ->
        Color.rgb(v, 255 - v, v / 2, a)
      end)
    ])
  end

  # Every leaf of a tree, in order, and the tree with its `n`-th leaf replaced.
  defp leaves({op, c, t}) when op != :ramp and is_number(t), do: leaves(c)
  defp leaves({:blend, list}), do: Enum.flat_map(list, &leaves/1)
  defp leaves({:contrast, c}) when c != :under, do: leaves(c)
  defp leaves(leaf), do: [leaf]

  defp replace(tree, n, with), do: tree |> replace_at(n, with) |> elem(0)

  defp replace_at({op, c, t}, n, with) when op != :ramp and is_number(t) do
    {c, n} = replace_at(c, n, with)
    {{op, c, t}, n}
  end

  defp replace_at({:blend, list}, n, with) do
    {list, n} = Enum.map_reduce(list, n, &replace_at(&1, &2, with))
    {{:blend, list}, n}
  end

  defp replace_at({:contrast, c}, n, with) when c != :under do
    {c, n} = replace_at(c, n, with)
    {{:contrast, c}, n}
  end

  defp replace_at(_leaf, 0, with), do: {with, -1}
  defp replace_at(leaf, n, _with), do: {leaf, n - 1}

  describe "a typed color's leaves are terms (spec/04 §1.3)" do
    @tag verifies: "color-typed-transforms"
    test "value?/1 refuses text, a word or a hex alike" do
      refute Color.value?("good")
      refute Color.value?("#fff")
      assert Color.value?(~RGB"#fff")
    end

    @tag verifies: "color-typed-transforms"
    property "a tree with %Color{} leaves is a color value, and resolves to a literal and to CSS" do
      check all(tree <- tree(4)) do
        assert Color.value?(tree), inspect(tree)

        for theme <- [Theme.default(), Theme.dark()] do
          assert Color.literal?(Color.resolve(tree, theme, :literal)), inspect(tree)
          assert is_binary(Color.resolve(tree, theme, :css))
        end
      end
    end

    @tag verifies: "color-typed-transforms"
    property "a tree with any one leaf a string is no color value" do
      check all(
              tree <- tree(4),
              text <-
                one_of([member_of(["#fff", "#3b6fa8", "red", "good", ""]), string(:printable)]),
              i <- integer(0..100)
            ) do
        n = rem(i, length(leaves(tree)))
        poisoned = replace(tree, n, text)
        assert text in leaves(poisoned)
        refute Color.value?(poisoned), inspect(poisoned)
      end
    end
  end

  # -- the built-ins, as v0.2.4 had them ----------------------------------------------

  describe "every built-in is v0.2.4's, now as terms (spec/04 §2.5, §3.1, §6)" do
    @tag verifies: "themes-colors-goldens"
    test "every slot and name resolves to parse! of its v0.2.4 hex, and its CSS to v0.2.4's" do
      resolved = fixture_json("resolved.json")

      for theme <- themes() do
        golden = Map.fetch!(resolved, to_string(theme.name))
        colors = MapSet.new(Theme.color_names(theme) ++ Theme.color_slots(theme), &to_string/1)

        for {name, value} <- golden["literal"] do
          got = Theme.resolve(theme, name, :literal)

          if name in colors,
            do: assert(got === Color.parse!(value), "#{theme.name} #{name}"),
            else: assert(got == value, "#{theme.name} #{name}")
        end

        # The CSS of a keyword the table takes from CSS itself is left out of the fixture,
        # each the same reference: its property and its literal.
        for {name, hex} <- golden["literal"], name in colors do
          css = Map.get(golden["css"], name, "var(#{Theme.css_name(name)}, #{hex})")
          assert Theme.resolve(theme, name, :css) == css, "#{theme.name} #{name}"
        end

        for {ramp, hexes} <- golden["ramps"], {hex, i} <- Enum.with_index(hexes) do
          position = {:ramp, String.to_existing_atom(ramp), i / 20}
          assert Theme.resolve(theme, position, :literal) === Color.parse!(hex)
        end

        for {hex, i} <- Enum.with_index(golden["series"], 1),
            do: assert(Theme.resolve(theme, {:series, i}, :literal) === Color.parse!(hex))
      end
    end

    @tag verifies: "themes-colors-goldens"
    test "check/1, violations/1 and floors/1 answer as they did on v0.2.4" do
      resolved = fixture_json("resolved.json")

      for theme <- themes() do
        golden = Map.fetch!(resolved, to_string(theme.name))
        assert inspect(Theme.check(theme)) == golden["check"]
        assert inspect(Theme.violations(theme)) == golden["violations"]
        assert inspect(Theme.floors(theme)) == golden["floors"]
      end
    end

    @tag verifies: "themes-colors-goldens"
    test "the stylesheet of the built-ins and the host theme is v0.2.4's, byte for byte" do
      assert Sheet.stylesheet(themes(), auto: {Theme.default(), Theme.dark()}) ==
               fixture("stylesheet.css")
    end
  end

  # -- version 1 documents --------------------------------------------------------------

  describe "a version 1 theme document reads to the same theme (spec/04 §5)" do
    @tag verifies: "themes-document-v1-step"
    test "every v0.2.4 document, the built-ins and the host theme, reads to its theme" do
      documents = fixture_json("documents.json")

      for theme <- themes() do
        document = Map.fetch!(documents, to_string(theme.name))
        assert document["$version"] == 1
        assert Document.from_json(JSON.encode!(document)) == {:ok, theme}
        assert Form.read(document, Document) |> elem(0) == :ok
      end
    end

    @tag verifies: "themes-document-v1-step"
    test "inside a bundle, each entry migrates by its type and reads to its theme" do
      for {bundle, theme} <- Enum.zip(fixture_json("bundles.json"), themes()) do
        assert {:ok, %Bundle{entries: [%{fragment: fragment}]}} =
                 Bundle.from_json(JSON.encode!(bundle), [Document])

        assert Document.from_map(fragment) == {:ok, theme}
      end
    end

    @tag verifies: "themes-document-v1-step"
    test "the step tags each color position, and leaves text it does not read for the reader" do
      house = Map.fetch!(fixture_json("documents.json"), "house")
      assert {:ok, %{"theme" => node} = migrated} = Form.gates(house, Document)
      assert migrated["$version"] == 2

      assert node["series"] == Enum.map(~w(#2f5d8a #b5651d #a23b3b), &%{"$rgb" => &1})
      assert node["background"] == %{"$rgb" => "#fbfaf6"}
      assert node["ramps"]["sequential"] |> Enum.at(1) == %{"$color" => "brand"}
      assert node["colors"]["brand"] == %{"$rgb" => "#2f5d8a"}
      assert node["colors"]["wash"] == %{"$alpha" => [%{"$rgb" => "#2f5d8a"}, 0.5]}
      assert node["colors"]["ink"] == %{"$contrast" => %{"$rgb" => "#2f5d8a"}}

      assert node["colors"]["mix"] ==
               %{
                 "$blend" => [
                   %{"$intensity" => [%{"$rgb" => "#b5651d"}, 0.6]},
                   %{"$color" => "brand"}
                 ]
               }

      assert node["colors"]["red"]["$steps"] |> hd() == [100, %{"$rgb" => "#fde8e8"}]
      assert node["styles"]["grid"]["stroke"]["color"] == %{"$rgb" => "#d0d0d0"}

      assert node["styles"]["hover"]["stroke"]["color"] ==
               %{"$darken" => [%{"$rgb" => "#333333"}, 0.1]}

      # Any CSS text parse/1 reads is tagged as the literal it is; other text stays text,
      # and is refused at its path.
      v1 = fn theme -> JSON.encode!(%{"$version" => 1, "theme" => theme}) end

      assert Document.from_json(v1.(%{"axis" => "steelblue", "grid" => "rgba(0, 0, 0, 0.5)"})) ==
               {:ok, Theme.new(axis: Color.parse!("steelblue"), grid: Color.rgb(0, 0, 0, 0.5))}

      assert Document.from_json(v1.(%{"axis" => "currentColor", "series" => ["#fff", "nope"]})) ==
               {:error,
                [{[:theme, :axis], {:type, :color}}, {[:theme, :series, 1], {:type, :color}}]}
    end

    @tag verifies: "themes-document-v1-step"
    test "a version 2 document holds no text where a color belongs" do
      json = JSON.encode!(%{"$version" => 2, "theme" => %{"axis" => "#555555"}})
      assert Document.from_json(json) == {:error, [{[:theme, :axis], {:type, :color}}]}
      assert Document.from_map(%{theme: %{axis: "#555555"}}) == Document.from_json(json)
    end
  end

  # -- round trips over generated themes ---------------------------------------------

  # A theme new/1 builds: literals anywhere a theme holds a color, exact and not, pinned
  # steps and transforms with literal operands, over a light background its roles read on.
  defp theme do
    gen all(
          name <- member_of([:house, :brand, "night_sky"]),
          series <- list_of(literal(), min_length: 1, max_length: 12),
          [axis, grid, text, surface] <- list_of(literal(), length: 4),
          background <- member_of([~RGB"#ffffff", ~RGB"#fbfaf6", ~RGB"#fdfdfd"]),
          entries <- list_of(entry(), max_length: 5),
          paint <- one_of([literal(), constant({:color, :text})])
        ) do
      Theme.new(
        name: name,
        series: series,
        axis: axis,
        grid: grid,
        text: text,
        surface: surface,
        background: background,
        colors: ~w(c1 c2 c3 c4 c5) |> Enum.zip(entries) |> Map.new(),
        styles: %{hover: %{stroke: %{type: :solid, color: paint, width: 2}}}
      )
    end
  end

  defp entry do
    one_of([
      literal(),
      map({literal(), literal(), integer(0..1000)}, fn {base, other, n} ->
        if n == 500, do: %{500 => base}, else: %{500 => base, n => other}
      end),
      map({literal(), unit()}, fn {c, t} -> {:alpha, c, t} end),
      map({literal(), unit()}, fn {c, t} -> {:blend, [{:intensity, c, t}, {:color, :blue}]} end),
      map(literal(), &{:contrast, &1}),
      map(integer(0..1000), &{:shade, {:color, :red}, &1})
    ])
  end

  describe "round trips (spec/04 §5)" do
    @tag verifies: "themes-document-forms"
    property "from_json(to_json(t)) and from_map(to_map(t)) are {:ok, t} for generated themes" do
      check all(theme <- theme()) do
        assert {:ok, json} = Document.to_json(theme)
        assert Document.from_json(json) == {:ok, theme}
        assert Document.from_map(Document.to_map(theme)) == {:ok, theme}
      end
    end
  end
end
