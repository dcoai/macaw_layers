defmodule Macaw.Layers.Theme.NamesTest do
  @moduledoc """
  A theme's names are strings, one key per spelling (spec/04 §2.1, §2.2, §3.4, §5): atom
  input is normalized once, at construction, so a host's name spelled like the library's is
  that name, the host's entry winning; a typed color's name is held as its string wherever
  it stands; words are kept as given; and the vocabulary is the JSON reader's, an
  extension's words read back only with the extension given, no atom made from a document.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Color, Theme}
  alias Macaw.Layers.Test.Atoms
  alias Macaw.Layers.Theme.{Document, Sheet}

  # An adopter's extension: a palette name, a color name, and the words its styles and
  # defaults use beyond the library's.
  defmodule Curves do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "curves"
    def styles, do: %{trace: {:furniture, %{stroke: %{type: :solid, color: {:color, :trace}}}}}
    def colors, do: %{trace: {:color, :blue}}
    def words, do: %{keys: [:line_height, :anchor, :interpolate], atoms: [:monotone_x, :middle]}
  end

  defmodule Twice do
    @moduledoc false
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "twice"
    def styles, do: %{}
    def colors, do: %{:lane => ~RGB"#8a8f99", "lane" => ~RGB"#8a8f99"}
  end

  @blue ~RGB"#2f5d8a"
  @status [~RGB"#5996d6", ~RGB"#cd6012", ~RGB"#b92931"]

  # -- the defect of macaw#181 ---------------------------------------------------------

  describe "a host's name spelled like the library's is that name (macaw#181)" do
    @tag verifies: "themes-names-strings"
    test "a host's \"info\" color is the info the theme draws with" do
      theme = Theme.new(colors: %{"info" => @blue})

      assert theme.colors["info"] === @blue
      refute Map.has_key?(theme.colors, :info)
      assert Theme.resolve(theme, :info, :literal) === @blue
      assert Theme.resolve(theme, "info", :css) == "var(--mw-info, #2f5d8a)"
      assert Color.resolve(Color.color(:info), theme, :literal) === @blue
      assert Theme.style(theme, :info).fill.color == {:color, "info"}
    end

    @tag verifies: "themes-names-strings"
    test "a host's \"status\" ramp is the status ramp, and its roles follow" do
      theme = Theme.new(ramps: %{"status" => @status})

      assert theme.ramps["status"] == @status
      assert Theme.ramp(theme, :status, 0) === hd(@status)
      assert Theme.ramp(theme, "status", 1) === List.last(@status)
      assert Theme.resolve(theme, :good, :literal) === hd(@status)
      assert Theme.resolve(theme, {:ramp, :status, 0.5}, :literal) === Enum.at(@status, 1)
    end

    @tag verifies: "themes-names-strings"
    test "a host's \"muted\" style is the muted style" do
      theme = Theme.new(styles: %{"muted" => %{opacity: 0.4}})

      assert theme.styles["muted"] == %{opacity: 0.4}
      assert Theme.style(theme, :muted) == %{opacity: 0.4}
      assert Theme.style(theme, "muted") == %{opacity: 0.4}
    end

    @tag verifies: "themes-names-strings"
    test "one name given both as its atom and as its string in one map raises" do
      for {field, both} <- [
            colors: %{:info => @blue, "info" => @blue},
            ramps: %{:status => @status, "status" => @status},
            styles: %{:muted => %{opacity: 0.4}, "muted" => %{opacity: 0.3}},
            defaults: %{:line => %{width: 1}, "line" => %{width: 2}}
          ] do
        message =
          assert_raise(ArgumentError, fn -> Theme.new([{:name, :house}, {field, both}]) end).message

        assert message ==
                 ~s(theme "house": #{field} gives "#{both |> Map.keys() |> Enum.find(&is_binary/1)}" ) <>
                   "both as an atom and as a string; a theme's names are strings, so the two " <>
                   "are one name: give it once"
      end

      assert_raise ArgumentError, ~r/theme "default": colors gives "info" both/, fn ->
        Theme.merge(Theme.default(), colors: %{:info => @blue, "info" => @blue})
      end

      assert_raise ArgumentError, ~r/extension "twice": colors gives "lane" both/, fn ->
        Theme.new(extensions: [Twice])
      end
    end
  end

  # -- typed colors -------------------------------------------------------------------

  describe "a typed color's name is held as its string, wherever it stands" do
    @tag verifies: "themes-names-strings"
    test "anchors, entries, pinned steps, paints and defaults" do
      theme =
        Theme.new(
          colors: %{
            brand: @blue,
            accent: {:lighten, {:color, :brand}, 0.2},
            mix: {:blend, [{:intensity, {:color, :brand}, 0.6}, {:color, "red"}]},
            ink: {:contrast, {:color, :brand}},
            deep: {:shade, {:color, :brand}, 900},
            hot: {:alpha, {:ramp, :thermal, 1}, 0.8}
          },
          ramps: %{sequential: [~RGB"#e9f2fc", {:color, :brand}, ~RGB"#004580"]},
          styles: %{
            hover: %{stroke: %{type: :solid, color: :text, width: 2}},
            grid: [%{stroke: %{type: :solid, color: {:color, :grid}}}, :thin],
            selected: %{stroke: %{width: 2}, effect: %{type: :glow, color: {:color, :brand}}}
          },
          defaults: %{line: %{stroke: %{color: {:color, :brand}}}}
        )

      assert theme.colors["accent"] == {:lighten, {:color, "brand"}, 0.2}

      assert theme.colors["mix"] ==
               {:blend, [{:intensity, {:color, "brand"}, 0.6}, {:color, "red"}]}

      assert theme.colors["ink"] == {:contrast, {:color, "brand"}}
      assert theme.colors["deep"] == {:shade, {:color, "brand"}, 900}
      assert theme.colors["hot"] == {:alpha, {:ramp, "thermal", 1}, 0.8}
      assert Enum.at(theme.ramps["sequential"], 1) == {:color, "brand"}
      assert theme.styles["hover"].stroke.color == {:color, "text"}
      assert theme.styles["grid"] == [%{stroke: %{type: :solid, color: {:color, "grid"}}}, "thin"]
      assert theme.styles["selected"].effect == %{type: :glow, color: {:color, "brand"}}
      assert theme.defaults == %{"line" => %{stroke: %{color: {:color, "brand"}}}}
      assert theme.colors["red"] === Theme.default().colors["red"]
    end

    @tag verifies: "themes-document-forms"
    test "a ramp anchor {:color, :brand} round-trips through JSON as {:color, \"brand\"}, both ways" do
      theme =
        Theme.new(
          name: :house,
          colors: %{brand: @blue},
          ramps: %{sequential: [~RGB"#e9f2fc", {:color, :brand}, ~RGB"#004580"]}
        )

      assert {:ok, json} = Document.to_json(theme)
      sequential = JSON.decode!(json)["theme"]["ramps"]["sequential"]
      assert Enum.at(sequential, 1) == %{"$color" => "brand"}
      assert Document.from_json(json) == {:ok, theme}
      assert Document.from_map(Document.to_map(theme)) == {:ok, theme}

      # The JSON form written by hand, the name as a document spells it, is the same theme.
      written =
        JSON.encode!(%{
          "$version" => 2,
          "theme" => %{
            "name" => "house",
            "colors" => %{"brand" => %{"$rgb" => "#2f5d8a"}},
            "ramps" => %{
              "sequential" => [
                %{"$rgb" => "#e9f2fc"},
                %{"$color" => "brand"},
                %{"$rgb" => "#004580"}
              ]
            }
          }
        })

      assert Document.from_json(written) == {:ok, theme}
    end

    @tag verifies: "themes-names-strings"
    test "a document value giving one name both ways is a fault at the name" do
      assert Document.from_map(%{theme: %{ramps: %{:status => @status, "status" => @status}}}) ==
               {:error, [{[:theme, :ramps, "status"], {:duplicate, :name}}]}

      assert Document.from_map(%{theme: %{styles: %{:muted => %{}, "muted" => %{}}}}) ==
               {:error, [{[:theme, :styles, "muted"], {:duplicate, :name}}]}
    end
  end

  # -- one key per spelling, over generated themes ----------------------------------------

  # Names a theme takes, each written in source so both spellings exist: the library's own
  # and a host's.
  @library ~w(info neutral red blue green amber gray)a
  @host ~w(brand accent wash ink deep)a
  @states ~w(hover focused active disabled muted emphasis)a

  defp spelling(atom), do: member_of([atom, Atom.to_string(atom)])

  defp spelled(names, value) do
    names
    |> Enum.map(fn name -> tuple({spelling(name), value}) end)
    |> fixed_list()
    |> map(&Map.new/1)
  end

  # A theme's input, its names spelled either way, and the same input spelled in strings.
  defp input do
    gen all(
          library <- list_of(member_of(@library), max_length: 4) |> map(&Enum.uniq/1),
          host <- list_of(member_of(@host), max_length: 4) |> map(&Enum.uniq/1),
          states <- list_of(member_of(@states), max_length: 3) |> map(&Enum.uniq/1),
          colors <- spelled(Enum.uniq([:brand | library ++ host]), constant(nil)),
          ramp <- spelling(:sequential),
          styles <- spelled(states, constant(nil)),
          anchor <- member_of([{:color, :brand}, {:color, "brand"}, {:color, :blue}])
        ) do
      %{
        colors: Map.new(colors, fn {name, nil} -> {name, color_for(name)} end),
        ramps: %{ramp => [~RGB"#e9f2fc", anchor, ~RGB"#004580"]},
        styles:
          Map.new(styles, fn {name, nil} -> {name, %{opacity: 0.5, stroke: %{width: 2}}} end)
      }
    end
  end

  # A value each name holds to its contract: a chromatic blue for info, a gray for
  # neutral, and the library's own hue for a status color.
  defp color_for(name) do
    case to_string(name) do
      "info" -> @blue
      "neutral" -> ~RGB"#6f7480"
      "gray" -> ~RGB"#6f7480"
      "red" -> ~RGB"#c23238"
      "amber" -> ~RGB"#bd7407"
      "green" -> ~RGB"#4ca34b"
      "blue" -> @blue
      "brand" -> @blue
      _host -> {:lighten, {:color, :blue}, 0.1}
    end
  end

  defp strings(input) do
    Map.new(input, fn {field, names} ->
      {field,
       Map.new(names, fn {name, entry} ->
         {to_string(name), Macaw.Layers.Theme.Names.value(entry_strings(entry))}
       end)}
    end)
  end

  defp entry_strings(anchors) when is_list(anchors),
    do: Enum.map(anchors, &Macaw.Layers.Theme.Names.value/1)

  defp entry_strings(entry), do: entry

  @tag verifies: "themes-names-strings"
  property "every name a theme holds is a string, one key per spelling, atom and string agreeing" do
    check all(input <- input(), max_runs: 60) do
      theme = Theme.new(Map.to_list(input))

      for field <- [:ramps, :colors, :styles],
          do: assert(theme |> Map.fetch!(field) |> Map.keys() |> Enum.all?(&is_binary/1))

      # Atom input and string input build one theme.
      assert Theme.new(Map.to_list(strings(input))) == theme

      # The ramp anchor's name, however spelled, is held as a string.
      assert {:color, anchor} = Enum.at(theme.ramps["sequential"], 1)
      assert is_binary(anchor)

      # Each name answers alike by either spelling, and the host's entry is the one drawn.
      for {name, _entry} <- input.colors do
        atom =
          if is_atom(name),
            do: name,
            else: Enum.find(@library ++ @host, &(Atom.to_string(&1) == name))

        string = Atom.to_string(atom)
        assert Theme.resolve(theme, atom, :literal) === Theme.resolve(theme, string, :literal)
        assert Theme.color_name?(theme, atom) and Theme.color_name?(theme, string)
        assert Map.has_key?(theme.colors, string)
      end

      for {name, entry} <- input.styles do
        assert Theme.style(theme, name) == entry
        assert Theme.style(theme, to_string(name)) == entry
      end

      for name <- Theme.color_names(theme) ++ Theme.style_names(theme) ++ Theme.slots(theme),
          do: assert(is_binary(name))
    end
  end

  # -- the theme's own name ---------------------------------------------------------------

  describe "a theme's own name and its counterparts are strings (#16)" do
    @tag verifies: "themes-names-own"
    test "new(name: :house) and new(name: \"house\") are one theme" do
      assert Theme.new(name: :house) == Theme.new(name: "house")
      assert Theme.new(name: :house).name == "house"
      assert Theme.new(name: :default) == Theme.new(name: "default")
      assert Theme.new(dark: :dark) == Theme.new(dark: "dark")
      assert Theme.new(dark: :dark).dark == "dark"
      assert Theme.merge(Theme.dark(), name: :night) == Theme.merge(Theme.dark(), name: "night")
      assert Sheet.rule(Theme.new(name: :house)) == Sheet.rule(Theme.new(name: "house"))
      assert Sheet.rule(Theme.new(name: "house")) =~ ~r/\A\.mw-theme-house \{/
    end

    @tag verifies: "themes-names-own"
    test "every built-in's name and counterparts are strings, and builtin/1 takes either spelling" do
      assert Theme.builtin("dark") == Theme.builtin(:dark)

      assert Theme.builtins() == ~w(default dark color_safe print)

      for {atom, name} <- [
            default: "default",
            dark: "dark",
            color_safe: "color_safe",
            print: "print"
          ] do
        theme = Theme.builtin(name)
        assert theme.name == name
        assert Theme.builtin(atom) == theme
        assert Enum.all?([theme.dark, theme.light], &(is_nil(&1) or is_binary(&1)))
      end

      assert {Theme.default().dark, Theme.dark().light} == {"dark", "default"}
      assert Theme.builtin(Theme.default().dark) == Theme.dark()
      assert Theme.builtin("house") == nil
    end

    @tag verifies: "themes-names-own"
    test "a theme document naming dark: \"dark\" resolves; a version 1 $atom name migrates to its string" do
      house = Theme.new(name: :house, dark: :dark)

      assert Document.from_map(%{theme: %{name: "house", dark: "dark"}}) == {:ok, house}
      assert Document.from_map(%{theme: %{name: :house, dark: :dark}}) == {:ok, house}

      v2 = ~s({"$version": 2, "theme": {"name": "house", "dark": "dark"}})
      assert Document.from_json(v2) == {:ok, house}

      # Version 1 (macaw_layers 0.2.4) wrote a built-in's name as a `$atom`: the step to
      # version 2 makes it the string it spells. At version 2 a name is a string only.
      v1 = ~s({"$version": 1, "theme": {"name": "house", "dark": {"$atom": "dark"}}})
      assert Document.from_json(v1) == {:ok, house}
      v1_named = ~s({"$version": 1, "theme": {"$atom": "dark"}})
      assert Document.from_json(v1_named) == {:ok, Theme.dark()}

      v2_atom = ~s({"$version": 2, "theme": {"name": "house", "dark": {"$atom": "dark"}}})
      assert {:error, [{[:theme, :dark], _fault}]} = Document.from_json(v2_atom)

      assert {:ok, json} = Document.to_json(house)
      assert JSON.decode!(json)["theme"]["dark"] == "dark"
      assert Document.from_map(%{theme: "dark"}) == {:ok, Theme.dark()}

      assert Document.from_map(%{theme: %{dark: "night"}}) ==
               {:error, [{[:theme, :dark], {:unknown_theme, "night"}}]}
    end
  end

  # -- words ------------------------------------------------------------------------------

  describe "words are kept as given" do
    @tag verifies: "themes-words-given"
    test "a style's and a default's words outside the library's vocabulary survive new/1" do
      theme =
        Theme.new(
          styles: %{hover: %{stroke: %{width: 2}, curve: %{type: :monotone_x}}},
          defaults: %{font: %{line_height: 1.2}, text: %{anchor: :middle}}
        )

      assert theme.styles["hover"] == %{stroke: %{width: 2}, curve: %{type: :monotone_x}}
      assert theme.defaults == %{"font" => %{line_height: 1.2}, "text" => %{anchor: :middle}}
      assert Theme.style(theme, :hover).curve == %{type: :monotone_x}
    end

    @tag verifies: "themes-extension-words"
    test "JSON with the extension's words reads them back; without them, the word is refused" do
      theme =
        Theme.new(
          name: :house,
          extensions: [Curves],
          styles: %{
            hover: %{stroke: %{width: 2}, curve: %{type: :monotone_x, interpolate: true}},
            trace: %{stroke: %{type: :solid, color: :trace, width: 1}}
          },
          defaults: %{font: %{line_height: 1.2}, text: %{anchor: :middle}}
        )

      assert theme.styles["trace"].stroke.color == {:color, "trace"}
      assert "trace" in Theme.style_names(theme) and "trace" in Theme.color_names(theme)

      assert {:ok, json} = Document.to_json(theme)
      assert Document.from_json(json, extensions: [Curves]) == {:ok, theme}

      # Without the extension the reader has no word :monotone_x nor :middle to make.
      assert {:error, faults} = Document.from_json(json)

      assert [{[:theme, :defaults, "text", "anchor"], {:unknown_atom, "middle"}}] =
               Enum.filter(faults, &match?({[:theme, :defaults | _], _}, &1))

      assert [{[:theme, :styles, "hover", :curve, :type], {:unknown_atom, "monotone_x"}}] =
               Enum.filter(faults, &match?({[:theme, :styles | _], _}, &1))

      # Without its words, the extension's own keys can't be written either.
      bare = %{theme | extensions: []}
      assert {:error, faults} = Document.to_json(bare)
      assert {[:theme, :defaults, "font", :line_height], :unknown_key} in faults
    end

    @tag verifies: "themes-extension-words"
    test "no atom is made from a document, its words and names fresh" do
      [word, key, name] = for _ <- 1..3, do: Atoms.fresh()

      json =
        JSON.encode!(%{
          "$version" => 2,
          "theme" => %{
            "colors" => %{name => %{"$rgb" => "#2f5d8a"}},
            "styles" => %{
              "hover" => %{
                "stroke" => %{"width" => 2},
                "curve" => %{"type" => %{"$atom" => word}}
              }
            },
            "defaults" => %{name => %{key => 1}}
          }
        })

      for opts <- [[], [extensions: [Curves]]] do
        assert Document.from_json(json, opts) ==
                 {:error, [{[:theme, :styles, "hover", :curve, :type], {:unknown_atom, word}}]}
      end

      assert Atoms.made([word, key, name]) == []
    end
  end
end
