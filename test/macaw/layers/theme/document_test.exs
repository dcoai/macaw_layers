defmodule Macaw.Layers.Theme.DocumentTest do
  @moduledoc """
  A theme as a document (spec/04 §5): its map and JSON forms, stamped with the schema
  version and read back through the version gate, the limits, per-kind validity and the
  contracts, every fault in the kernel's shape.
  """
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Fault, Theme, Var}
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

    @tag verifies: "themes-document-forms"
    test "the limits are applied to the document as given" do
      node = %{series: List.duplicate("#3b6fa8", 6)}

      # The limits gate walks the document's form, before any key is read (spec/01 §5).
      assert Document.from_map(%{theme: node}, limits: [items: 5]) ==
               {:error, [{["theme", "series"], {:limit, :items, 5, 6}}]}

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
               {:error, [{["styles"], :unknown_key}]}

      assert Document.from_map(%{axis: "#000000"}) ==
               {:error, [{[:theme], :required}, {["axis"], :unknown_key}]}

      assert Document.from_map(@house) == {:error, [{[], {:type, :map}}]}
    end

    @tag verifies: "themes-document-forms"
    test "JSON that does not parse is a fault in the same shape" do
      assert {:error, [{[], {:json, _message}}]} = Document.from_json("not json")
    end
  end
end
