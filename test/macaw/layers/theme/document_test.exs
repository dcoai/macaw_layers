defmodule Macaw.Layers.Theme.DocumentTest do
  @moduledoc """
  A theme as a document (spec/04 §5): its value and JSON form, the value judged as terms
  after the version check, the JSON form read back through the adapter's gates, and both
  held to per-kind validity and the contracts, every fault in the kernel's shape.
  """
  use ExUnit.Case, async: true

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Bundle, Fault, Form, Store, Theme, Var}
  alias Macaw.Layers.Store.Memory
  alias Macaw.Layers.Theme.Document

  doctest Document

  # An adopter's extension registering a word its defaults use (spec/04 §3.4).
  defmodule Steps do
    @behaviour Macaw.Layers.Theme.Extension
    def name, do: "steps"
    def styles, do: %{}
    def colors, do: %{}
    def words, do: %{atoms: [:step]}
  end

  @house Theme.new(
           name: :house,
           series: [~RGB"#2f5d8a", ~RGB"#b5651d", ~RGB"#a23b3b"],
           background: ~RGB"#fbfaf6",
           font_family: "Georgia, serif",
           ramps: %{status: [~RGB"#4ca34b", ~RGB"#bd7407", ~RGB"#c23238"]},
           roles: %{info: ~RGB"#2f5d8a"}
         )

  @themes [Theme.default(), Theme.dark(), Theme.color_safe(), @house]

  defp strings(names), do: Map.new(names, fn {k, v} -> {to_string(k), v} end)

  describe "round trips" do
    @tag verifies: "themes-document-forms"
    test "every built-in theme and a host theme read back as themselves, in both forms" do
      for theme <- @themes do
        assert Document.from_map(Document.to_map(theme)) == {:ok, theme}
        assert {:ok, json} = Document.to_json(theme)
        assert Document.from_json(json) == {:ok, theme}
      end
    end

    @tag verifies: "themes-document-forms"
    test "the map form is stamped with the current version and holds every field" do
      %{version: version, theme: node} = Document.to_map(@house)
      assert version == Document.current()
      # Every name a string (spec/04 §2.1), as the theme holds it.
      assert node.ramps == strings(@house.ramps)
      assert node.colors == strings(@house.colors)
      assert node.colors["info"] === ~RGB"#2f5d8a"
      assert node.styles == strings(@house.styles)
      # Every field but a counterpart the theme does not declare, root defaults it does not
      # set, and the host's extensions, which never travel.
      assert Map.keys(node) |> Enum.sort() ==
               (Map.keys(Map.from_struct(@house)) -- [:dark, :light, :defaults, :extensions])
               |> Enum.sort()
    end

    @tag verifies: "themes-document-forms"
    test "a theme's own root defaults travel in its document" do
      defaults = %{stroke: %{width: 1.5}, line: %{curve: %{type: :step}}}
      theme = Theme.merge(@house, defaults: defaults, extensions: [Steps])
      # Every name a string; the words of an entry as given, `:step` outside the library's
      # vocabulary included (spec/04 §2.1).
      held = %{"stroke" => %{width: 1.5}, "line" => %{curve: %{type: :step}}}
      assert theme.defaults == held
      assert %{theme: %{defaults: ^held}} = Document.to_map(theme)
      assert Document.from_map(Document.to_map(theme), extensions: [Steps]) == {:ok, theme}
      assert {:ok, json} = Document.to_json(theme)
      assert Document.from_json(json, extensions: [Steps]) == {:ok, theme}

      # The vocabulary is the JSON reader's: without the extension that registers it, the
      # word is no atom the reader may make, refused at its path.
      assert {:error, [{[:theme, :defaults, "line", :curve, :type], {:enum, words}}]} =
               Document.from_json(json)

      refute :step in words
    end

    @tag verifies: "themes-document-forms"
    test "the JSON form is the stamped fragment document" do
      {:ok, json} = Document.to_json(@house)
      decoded = JSON.decode!(json)
      assert decoded["$version"] == Document.current()
      assert decoded["theme"]["name"] == "house"
      # A literal is tagged $rgb (spec/04 §1.6, §5).
      assert decoded["theme"]["ramps"]["status"] ==
               Enum.map(~w(#4ca34b #bd7407 #c23238), &%{"$rgb" => &1})

      assert decoded["theme"]["background"] == %{"$rgb" => "#fbfaf6"}
    end

    @tag verifies: "themes-document-forms"
    test "a node's name maps hold names as strings, read back as the strings they are" do
      assert Document.name_map?([:theme, :styles])
      refute Document.name_map?([:theme, :styles, "primary"])

      node = Document.node(@house)

      for key <- [:ramps, :colors, :styles],
          do: assert(node |> Map.fetch!(key) |> Map.keys() |> Enum.all?(&is_binary/1))

      {:ok, json} = Document.to_json(@house)
      assert JSON.decode!(json)["theme"]["colors"]["info"] == %{"$rgb" => "#2f5d8a"}
      assert {:ok, %Theme{colors: %{"info" => ~RGB"#2f5d8a"}}} = Document.from_json(json)

      # A node spelling the library's names as atoms builds the same theme.
      atoms = %{
        ramps: %{status: [~RGB"#4ca34b", ~RGB"#bd7407", ~RGB"#c23238"]},
        colors: %{info: ~RGB"#2f5d8a"},
        styles: %{muted: %{opacity: 0.4}}
      }

      assert {:ok, theme} = Document.from_map(%{theme: atoms})

      assert Document.from_map(%{theme: Map.new(atoms, fn {k, v} -> {k, strings(v)} end)}) ==
               {:ok, theme}

      # A host's name spelled as the library's is that name, the host's entry winning.
      host = Theme.new(name: :house, colors: %{"info" => ~RGB"#123456"})
      assert host.colors["info"] === ~RGB"#123456"
      assert Document.node(host).colors["info"] === ~RGB"#123456"

      # A value giving one name both ways is refused at the name.
      assert Document.from_map(%{
               theme: %{colors: %{:info => ~RGB"#2f5d8a", "info" => ~RGB"#123456"}}
             }) == {:error, [{[:theme, :colors, "info"], {:duplicate, :name}}]}
    end

    @tag verifies: "themes-document-forms"
    test "a theme entry of a store round-trips through a bundle's forms and relocates" do
      store = {Memory, start_supervised!({Memory, types: [Document]}, id: :themes)}
      other = {Memory, start_supervised!({Memory, types: [Document]}, id: :other_themes)}
      {:ok, id} = Store.put(store, %{id: nil, name: "House", fragment: Document.fragment(@house)})
      bundle = Bundle.export(store, id, "lib")

      assert {:ok, map} = Bundle.to_map(bundle, [Document])
      assert Bundle.from_map(map, [Document]) == {:ok, bundle}
      assert {:ok, json} = Bundle.to_json(bundle, [Document])
      assert Bundle.from_json(json, [Document]) == {:ok, bundle}

      assert {:ok, %{ids: %{^id => new}}} = Store.import(other, bundle)
      assert {:ok, %{fragment: fragment}} = Store.get(other, new)
      assert Document.from_map(fragment) == {:ok, @house}
    end

    @tag verifies: "themes-document-forms"
    test "the store's fragment is a theme fragment and reads as the current version" do
      fragment = Document.fragment(@house)
      assert Document.from_map(fragment) == {:ok, @house}
    end

    @tag verifies: "themes-document-forms"
    test "a name reads as the built-in theme, any other name is not a theme" do
      assert Document.from_map(%{theme: :color_safe}) == {:ok, Theme.color_safe()}

      assert Document.from_map(%{theme: :house}) ==
               {:error, [{[:theme], {:unknown_theme, "house"}}]}
    end

    @tag verifies: "themes-document-forms"
    test "a partial node names only what it changes; the rest is the default's" do
      {:ok, theme} = Document.from_map(%{theme: %{axis: ~RGB"#111111"}})
      assert theme == Theme.new(axis: ~RGB"#111111")
    end
  end

  describe "reading under the version policy" do
    @tag verifies: "themes-document-forms"
    test "a newer document is refused by name before a key is read" do
      assert Document.from_map(%{version: 4, theme: %{nonsense: 1}}) ==
               {:error, [{[], {:newer_schema, 4, 2}}]}

      assert Document.from_json(~s({"$version": 4, "theme": {"never_an_atom_4c1": 1}})) ==
               {:error, [{[], {:newer_schema, 4, 2}}]}
    end

    @tag verifies: "themes-document-forms"
    test "a version below one, or not an integer, is refused" do
      # The kernel's version gate (spec/01 §4): a stamp that is not a positive integer.
      assert Document.from_map(%{version: 0, theme: %{}}) ==
               {:error, [{["$version"], {:type, :pos_integer}}]}

      assert Document.from_map(%{version: "2", theme: %{}}) ==
               {:error, [{["$version"], {:type, :pos_integer}}]}
    end

    @tag verifies: "themes-document-value"
    test "the limits are the JSON form's, and a value is judged with none" do
      node = %{series: List.duplicate(~RGB"#3b6fa8", 6)}

      # A value is no encoding: nothing reads it, so no limit bounds it (spec/01 §5).
      assert {:ok, %Theme{series: series}} = Document.from_map(%{theme: node})
      assert series == node.series

      # The limits gate walks the JSON form, before any key is read.
      json = JSON.encode!(%{"theme" => %{"series" => List.duplicate(%{"$rgb" => "#3b6fa8"}, 6)}})

      assert {:error, [{path, {:limit, :items, 5, 6}}]} =
               Document.from_json(json, limits: [items: 5])

      assert Fault.format({path, {:limit, :items, 5, 6}}) =~ "theme.series"
    end
  end

  describe "validity and the contracts" do
    @tag verifies: "themes-document-forms"
    test "a ramp that breaks its contract is the contract fault at its path" do
      assert {:error, [{[:theme, :ramps, "status"], {:contract, message}}]} =
               Document.from_map(%{
                 theme: %{ramps: %{status: [~RGB"#c23238", ~RGB"#bd7407", ~RGB"#4ca34b"]}}
               })

      assert message =~ "good (0) must be green or blue"
    end

    @tag verifies: "themes-document-forms"
    test "a variable is not a theme's: nothing applies a theme document" do
      assert Document.from_map(%{theme: %{axis: Var.new(:ink)}}) ==
               {:error, [{[:theme, :axis], {:unresolved, :var, "ink"}}]}
    end

    @tag verifies: "themes-document-forms"
    test "an unknown key, a key beside the theme, and a map that is no theme are refused" do
      assert {:error, [{[:theme, :ink], :unknown_key}]} =
               Document.from_map(%{theme: %{ink: ~RGB"#000000"}})

      # The envelope's own faults (spec/01 §3): a key it does not know at its own spelling, a
      # missing theme required, and a value that is not a map document.
      assert Document.from_map(%{theme: %{}, styles: %{}}) ==
               {:error, [{[:styles], :unknown_key}]}

      assert Document.from_json(~s({"theme": {}, "stles": {}})) ==
               {:error, [{["stles"], :unknown_key}]}

      assert Document.from_map(%{axis: ~RGB"#000000"}) ==
               {:error, [{[:axis], :unknown_key}, {[:theme], :required}]}

      assert Document.from_map(@house) == {:error, [{[], {:type, :map}}]}
    end

    @tag verifies: "themes-document-value"
    test "a value is judged as terms, never through its form" do
      # Root defaults built in Elixir under an atom name, which the JSON form's name map
      # can't hold (its names are strings): the form refuses the value, and the theme,
      # which holds every name by its string and every word as given, takes it.
      node = %{defaults: %{line: %{curve: %{type: :step}}}}

      assert Form.to_map(%{theme: node}, Document) ==
               {:error, [{[:theme, :defaults, :line], {:type, :name}}]}

      assert {:ok, theme} = Document.from_map(%{theme: node})
      assert theme.defaults == %{"line" => %{curve: %{type: :step}}}

      # The same theme as the JSON form spells it reads back as the same theme.
      assert {:ok, json} = Document.to_json(@house)
      assert Document.from_json(json) == Document.from_map(Document.to_map(@house))
    end

    @tag verifies: "themes-document-forms"
    test "JSON that does not parse is a fault in the same shape" do
      assert {:error, [{[], {:json, _message}}]} = Document.from_json("not json")
    end
  end
end
