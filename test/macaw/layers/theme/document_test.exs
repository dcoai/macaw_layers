defmodule Macaw.Layers.Theme.DocumentTest do
  @moduledoc """
  A theme as a document (spec/04 §5): its value and JSON form, the value judged as terms
  after the version check, the JSON form read back through the adapter's gates, and both
  held to per-kind validity and the contracts, every fault in the kernel's shape.
  """
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Fault, Form, Theme, Var}
  alias Macaw.Layers.Theme.Document

  doctest Document

  @house Theme.new(
           name: :house,
           series: ~w(#2f5d8a #b5651d #a23b3b),
           background: "#fbfaf6",
           font_family: "Georgia, serif",
           ramps: %{status: ~w(#4ca34b #bd7407 #c23238)},
           roles: %{info: "#2f5d8a"}
         )

  @themes [Theme.default(), Theme.dark(), Theme.color_safe(), @house]

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
      assert node.ramps == @house.ramps
      assert node.colors == @house.colors
      assert node.colors.info == "#2f5d8a"
      assert node.styles == @house.styles
      # Every field but a counterpart the theme does not declare, root defaults it does not
      # set, and the host's extensions, which never travel.
      assert Map.keys(node) |> Enum.sort() ==
               (Map.keys(Map.from_struct(@house)) -- [:dark, :light, :defaults, :extensions])
               |> Enum.sort()
    end

    @tag verifies: "themes-document-forms"
    test "a theme's own root defaults travel in its document" do
      defaults = %{stroke: %{width: 1.5}, line: %{curve: %{type: :step}}}
      theme = Theme.merge(@house, defaults: defaults)
      # A key or atom outside the library's vocabulary is held by its string.
      held = %{:stroke => %{width: 1.5}, "line" => %{curve: %{type: "step"}}}
      assert %{theme: %{defaults: ^held}} = Document.to_map(theme)
      assert Document.from_map(Document.to_map(theme)) == {:ok, theme}
      assert {:ok, json} = Document.to_json(theme)
      assert Document.from_json(json) == {:ok, theme}
    end

    @tag verifies: "themes-document-forms"
    test "the JSON form is the stamped fragment document" do
      {:ok, json} = Document.to_json(@house)
      decoded = JSON.decode!(json)
      assert decoded["$version"] == Document.current()
      assert decoded["theme"]["name"] == "house"
      assert decoded["theme"]["ramps"]["status"] == ~w(#4ca34b #bd7407 #c23238)
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
      {:ok, theme} = Document.from_map(%{theme: %{axis: "#111111"}})
      assert theme == Theme.new(axis: "#111111")
    end
  end

  describe "reading under the version policy" do
    @tag verifies: "themes-document-forms"
    test "a newer document is refused by name before a key is read" do
      assert Document.from_map(%{version: 4, theme: %{nonsense: 1}}) ==
               {:error, [{[], {:newer_schema, 4, 1}}]}

      assert Document.from_json(~s({"$version": 4, "theme": {"never_an_atom_4c1": 1}})) ==
               {:error, [{[], {:newer_schema, 4, 1}}]}
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
      node = %{series: List.duplicate("#3b6fa8", 6)}

      # A value is no encoding: nothing reads it, so no limit bounds it (spec/01 §5).
      assert {:ok, %Theme{series: series}} = Document.from_map(%{theme: node})
      assert series == node.series

      # The limits gate walks the JSON form, before any key is read.
      json = JSON.encode!(%{"$version" => 1, "theme" => %{"series" => node.series}})

      assert {:error, [{path, {:limit, :items, 5, 6}}]} =
               Document.from_json(json, limits: [items: 5])

      assert Fault.format({path, {:limit, :items, 5, 6}}) =~ "theme.series"
    end
  end

  describe "validity and the contracts" do
    @tag verifies: "themes-document-forms"
    test "a ramp that breaks its contract is the contract fault at its path" do
      assert {:error, [{[:theme, :ramps, :status], {:contract, message}}]} =
               Document.from_map(%{theme: %{ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}}})

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
               Document.from_map(%{theme: %{ink: "#000000"}})

      # The envelope's own faults (spec/01 §3): a key it does not know at its own spelling, a
      # missing theme required, and a value that is not a map document.
      assert Document.from_map(%{theme: %{}, styles: %{}}) ==
               {:error, [{[:styles], :unknown_key}]}

      assert Document.from_json(~s({"theme": {}, "stles": {}})) ==
               {:error, [{["stles"], :unknown_key}]}

      assert Document.from_map(%{axis: "#000000"}) ==
               {:error, [{[:axis], :unknown_key}, {[:theme], :required}]}

      assert Document.from_map(@house) == {:error, [{[], {:type, :map}}]}
    end

    @tag verifies: "themes-document-value"
    test "a value is judged as terms, never through its form" do
      # Root defaults built in Elixir under an atom key the JSON form has no spelling for:
      # the form refuses the value, and the theme, which holds a name outside its
      # vocabulary by its string, takes it.
      node = %{defaults: %{line: %{curve: %{type: :step}}}}

      assert Form.to_map(%{theme: node}, Document) ==
               {:error, [{[:theme, :defaults, :line], :unknown_key}]}

      assert {:ok, theme} = Document.from_map(%{theme: node})
      assert theme.defaults == %{"line" => %{curve: %{type: "step"}}}

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
