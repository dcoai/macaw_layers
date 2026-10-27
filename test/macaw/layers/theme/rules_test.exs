defmodule Macaw.Layers.Theme.RulesTest do
  # What visualize's themes did not have: extensions (spec/04 §3.4), the color profile and
  # data colors (§4), the contrast floors as faults (§2.6), and precedence (§3.3).
  use ExUnit.Case, async: true

  import Macaw.Layers.Color, only: [color: 1, intensity: 2, blend: 1, alpha: 2, lighten: 2]

  alias Macaw.Layers.{Color, Fragment, Theme, Use}
  alias Macaw.Layers.Test.Design
  alias Macaw.Layers.Theme.Document

  defmodule Marks do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "marks"

    def styles,
      do: %{
        lane: {:furniture, %{stroke: %{type: :solid, color: {:color, :lane}}}},
        flash: {:state, %{opacity: 0.6}},
        wide: {:modifier, %{stroke: %{width: 4}}}
      }

    def colors, do: %{lane: "#8a8f99"}
  end

  defmodule Dup do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "dup"
    def styles, do: %{lane: {:modifier, %{opacity: 0.5}}}
    def colors, do: %{}
  end

  defmodule Library do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "library"
    def styles, do: %{hover: {:state, %{opacity: 0.5}}}
    def colors, do: %{}
  end

  defmodule Hued do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "hued"
    def styles, do: %{glow: {:state, %{stroke: %{type: :solid, color: {:color, :text}}}}}
    def colors, do: %{}
  end

  defmodule Lump do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "lump"
    def styles, do: %{heavy: {:modifier, %{stroke: %{width: 4}, opacity: 0.5}}}
    def colors, do: %{}
  end

  defmodule Strayed do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "strayed"
    def styles, do: %{lost: {:mark, %{opacity: 0.5}}}
    def colors, do: %{}
  end

  describe "extensions (spec/04 §3.4)" do
    @tag verifies: "themes-extensions-registered"
    test "a registered extension's names join the palette and the table, after the library's, with their defaults" do
      theme = Theme.new(extensions: [Marks])

      assert Enum.take(Theme.style_names(theme), -3) == [:flash, :lane, :wide]
      assert Theme.style(theme, :lane) == %{stroke: %{type: :solid, color: {:color, :lane}}}
      assert Theme.style(theme, "flash") == %{opacity: 0.6}
      assert Theme.color_name?(theme, :lane) and Theme.color_name?(theme, "lane")
      assert :lane in Theme.color_names(theme)
      assert Theme.resolve(theme, :lane, :css) == "var(--mw-lane, #8a8f99)"
      assert Color.resolve(color(:lane), theme, :literal) == "#8a8f99"

      refute Theme.color_name?(Theme.default(), :lane)

      assert_raise ArgumentError, ~r/unknown palette style :lane/, fn ->
        Theme.style(Theme.default(), :lane)
      end
    end

    @tag verifies: "themes-extensions-registered"
    test "a theme's own entry and color beat an extension's defaults, and travel through the document" do
      theme =
        Theme.new(
          name: :house,
          extensions: [Marks],
          styles: %{lane: %{stroke: %{type: :solid, color: {:color, :axis}, width: 2}}},
          colors: %{lane: "#111111"}
        )

      assert Theme.style(theme, :lane) == %{
               stroke: %{type: :solid, color: {:color, :axis}, width: 2}
             }

      assert Theme.resolve(theme, :lane, :literal) == "#111111"

      assert Document.from_map(Document.to_map(theme), extensions: [Marks]) == {:ok, theme}
      {:ok, json} = Document.to_json(theme)
      assert Document.from_json(json, extensions: [Marks]) == {:ok, theme}

      # Without the extension registered, its name is no palette name.
      assert {:error, [{[:theme, :styles, "lane"], {:contract, message}}]} =
               Document.from_map(Document.to_map(theme))

      assert message =~ "is not a name of the palette"
    end

    @tag verifies: "themes-extensions-registered"
    test "an unregistered name is a fault naming it: a palette name, and a color an entry paints with" do
      assert_raise ArgumentError,
                   ~r/style :lane breaks its contract: is not a name of the palette/,
                   fn ->
                     Theme.new(styles: %{lane: %{opacity: 0.5}})
                   end

      assert_raise ArgumentError, ~r/names "lane", not a color of the theme's color table/, fn ->
        Theme.new(styles: %{hover: %{stroke: %{type: :solid, color: {:color, :lane}, width: 2}}})
      end
    end

    @tag verifies: "themes-extensions-registered"
    test "an extension's names are held to their group's contracts, its defaults included" do
      assert_raise ArgumentError,
                   ~r/style :glow breaks its contract: a state style must read without hue/,
                   fn ->
                     Theme.new(extensions: [Hued])
                   end

      assert_raise ArgumentError,
                   ~r/style :heavy breaks its contract: a modifier changes one thing/,
                   fn ->
                     Theme.new(extensions: [Lump])
                   end

      assert_raise ArgumentError,
                   ~r/style :lane breaks its contract: the grid must resolve a stroke/,
                   fn ->
                     Theme.new(extensions: [Marks], styles: %{lane: %{stroke: %{type: :none}}})
                   end
    end

    @tag verifies: "themes-extensions-registered"
    test "two extensions adding one name, an extension adding a library name, or another group raise naming both" do
      assert_raise ArgumentError, ~r/extensions "marks" and "dup" both add the style :lane/, fn ->
        Theme.new(extensions: [Marks, Dup])
      end

      assert_raise ArgumentError,
                   ~r/extension "library" adds the style :hover, which the library already names/,
                   fn ->
                     Theme.new(extensions: [Library])
                   end

      assert_raise ArgumentError,
                   ~r/extension "strayed": style :lost names the group :mark/,
                   fn ->
                     Theme.new(extensions: [Strayed])
                   end
    end
  end

  describe "the profile and data colors (spec/04 §4)" do
    @tag verifies: "themes-profile-colors"
    test "under roles a literal anywhere in a color value is refused, and every typed value passes" do
      for value <- [
            color(:bad),
            color(:bad) |> lighten(0.2),
            {:series, 3},
            {:ramp, :thermal, 0.4},
            blend([color(:red), color(:blue)]),
            {:contrast, :under}
          ],
          do: assert(Theme.check_color(value, :roles) == :ok)

      for value <- [
            "#ff0000",
            alpha("#3b6fa8", 0.5),
            blend([color(:red), intensity("#00ff00", 0.5)]),
            {:contrast, "#000000"}
          ],
          do: assert(Theme.check_color(value, :roles) == {:error, {:literal_color, value}})

      for value <- ["#ff0000", color(:bad), blend([color(:red), intensity("#00ff00", 0.5)])],
          do: assert(Theme.check_color(value, :open) == :ok)

      assert_raise ArgumentError, ~r/a color profile is :roles or :open/, fn ->
        Theme.check_color("#fff", :loose)
      end
    end

    @tag verifies: "themes-profile-colors"
    test "a data color reaching 3:1 against the background is its literal, one under is refused with its ratio" do
      theme = Theme.default()

      assert Theme.data_color(theme, "#3b6fa8") == {:ok, "#3b6fa8"}
      assert Theme.data_color(theme, color(:bad)) == {:ok, "#c23238"}
      assert Theme.data_color(theme, "#ffff00") == {:error, {:contrast, 1.07}}
      assert {:error, {:contrast, ratio}} = Theme.data_color(theme, alpha("#3b6fa8", 0.2))
      assert ratio < 3

      # On the dark background the yellow reads.
      assert Theme.data_color(Theme.dark(), "#ffff00") == {:ok, "#ffff00"}
    end

    @tag verifies: "themes-profile-colors"
    test "a data color that does not resolve is unreadable, never raised" do
      for value <- [
            color(:nope),
            "not a color",
            "#12345z",
            :bad,
            7,
            {:ramp, :nope, 0.5},
            alpha("nope", 0.5)
          ],
          do:
            assert(
              Theme.data_color(Theme.default(), value) == {:error, :unreadable},
              inspect(value)
            )
    end
  end

  describe "the floors (spec/04 §2.6)" do
    defp floor(color, background),
      do: Float.floor(Color.contrast(Color.parse(color), Color.parse(background)), 2)

    @tag verifies: "themes-floors-builtins"
    test "floors refuses text under 4.5:1, an axis or series color under 3:1, a grid under 1.2:1 and a surface equal to the grid" do
      for theme <- [Theme.default(), Theme.dark(), Theme.color_safe(), Theme.print()],
          do: assert(Theme.floors(theme) == :ok)

      faint =
        Theme.new(
          text: "#999999",
          axis: "#bbbbbb",
          series: ["#3b6fa8", "#ffdd88"],
          grid: "#f8f8f8",
          surface: "#f8f8f8"
        )

      assert Theme.floors(faint) ==
               {:error,
                [
                  {:text, {:contrast, floor("#999999", "#ffffff"), 4.5}},
                  {:axis, {:contrast, floor("#bbbbbb", "#ffffff"), 3.0}},
                  {:series_2, {:contrast, floor("#ffdd88", "#ffffff"), 3.0}},
                  {:grid, {:contrast, floor("#f8f8f8", "#ffffff"), 1.2}},
                  {:surface, {:equal, :grid}}
                ]}
    end
  end

  describe "the vocabularies (spec/04 §1.3, §2.3)" do
    @tag verifies: "themes-ramps-contracts"
    test "the four ramps and the five roles are the library's, in order" do
      assert Theme.ramp_names() == [:status, :thermal, :diverging, :sequential]
      assert Theme.role_names() == [:good, :warning, :bad, :info, :neutral]
    end

    @tag verifies: "color-typed-transforms"
    test "contrast with no color is the ink over what is under, resolved against the theme's background" do
      assert Color.contrast() == {:contrast, :under}
      assert Color.resolve(Color.contrast(), Theme.default(), :css) == "#333333"
      assert Color.resolve(Color.contrast(), Theme.dark(), :literal) == "#e6e6e6"
    end
  end

  describe "the series cap (spec/04 §2.1, §5)" do
    @tag verifies: "themes-slots-order"
    test "a theme holds at most 64 series colors, each slot the library's atom" do
      colors = for k <- 1..64, do: "#" <> String.pad_leading(Integer.to_string(k * 3, 16), 6, "0")
      theme = Theme.build(Theme.default(), series: colors)
      assert length(Theme.slots(theme)) == 64 + 14

      assert Theme.series_slot(theme, 64) == :series_64 and
               Theme.series_slot(theme, 65) == :series_1

      assert Theme.color_slots(theme) ==
               Enum.take(Theme.slots(theme), 64) ++
                 [:axis, :grid, :text, :background, :surface] ++ Theme.role_names()

      assert_raise ArgumentError, ~r/series: a theme holds at most 64 colors, got 65/, fn ->
        Theme.new(series: colors ++ ["#000000"])
      end
    end

    @tag verifies: "themes-document-forms"
    test "a document's series longer than 64 is refused at its path" do
      series = List.duplicate("#3b6fa8", 65)

      assert Document.from_map(%{theme: %{series: series}}) ==
               {:error, [{[:theme, :series], {:limit, :series, 64, 65}}]}
    end
  end

  describe "precedence (spec/04 §3.3)" do
    @tag verifies: "themes-precedence-layers"
    test "a theme's entry or color beats the default's, the default's the CSS name's" do
      assert Theme.style(Theme.new(styles: %{muted: %{opacity: 0.4}}), :muted) == %{opacity: 0.4}
      assert Theme.style(%{Theme.default() | styles: %{}}, :muted) == %{opacity: 0.25}

      assert Theme.resolve(Theme.new(colors: %{red: "#aa0000"}), :red, :literal) == "#aa0000"
      assert Theme.resolve(Theme.default(), :red, :literal) == "#c23238"
      # gray is both the default theme's own and a CSS name: the default's wins.
      assert Theme.resolve(Theme.default(), :gray, :literal) == "#6f7480"
      assert Theme.resolve(Theme.default(), :tomato, :literal) == "#ff6347"
    end

    @tag verifies: "themes-precedence-layers"
    test "a document's own palette entry beats the theme's, and a page masks a component's theme" do
      theme = Theme.default()
      from_theme = %{styles: %{"muted" => Theme.style(theme, :muted)}}
      document = %{styles: %{"muted" => %{opacity: 0.6}}}

      assert Fragment.stack(Design, from_theme, document) == %{
               styles: %{"muted" => %{opacity: 0.6}}
             }

      component = %{theme: :dark, marks: [%{id: "m"}]}
      page = %{theme: :print}

      assert Fragment.stack(Design, [page, Use.mask(component, [:theme])]) == %{
               theme: :print,
               marks: [%{id: "m"}]
             }

      assert Fragment.stack(Design, [page, component]) == %{theme: :dark, marks: [%{id: "m"}]}
    end

    @tag verifies: "themes-precedence-layers"
    test "a theme document stacked over a built-in is the merged theme" do
      lower = Document.to_map(Theme.default())

      upper = %{
        theme: %{
          name: "house",
          axis: "#555555",
          colors: %{"brand" => "#123456"},
          styles: %{muted: %{opacity: 0.4}}
        }
      }

      expected =
        Theme.merge(Theme.default(),
          name: :house,
          axis: "#555555",
          colors: %{brand: "#123456"},
          styles: %{muted: %{opacity: 0.4}}
        )

      assert Document.from_map(Fragment.stack(Document, lower, upper)) == {:ok, expected}
      assert Fragment.kind(Document, Document.fragment(expected)) == :theme
    end
  end
end
