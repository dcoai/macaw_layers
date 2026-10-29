defmodule Macaw.Layers.Fragment.NameMapsTest do
  # Name maps in the JSON adapter (spec/01 §6) and where a fragment type has them
  # (spec/02 §9), over the test type: a name spelled like one of the type's keys is a name.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Form, Fragment, Use, Var}
  alias Macaw.Layers.Test.Design

  doctest Fragment

  # A type whose singular wrapper `frame:` names a kind that holds a name map.
  defmodule Wrapped do
    @moduledoc false
    def root, do: :doc
    def key(:doc, :frames), do: %{merge: :deep, element: :frame}
    def key(:frame, :scales), do: %{merge: :union, element: :scale}
    def key(_kind, _key), do: nil
    def wrapper(:frame), do: :frame
    def wrapper(_key), do: nil
  end

  defp json(value) do
    with {:ok, json} <- Form.to_json(value, Design),
         do: json |> JSON.decode!() |> Form.from_map(Design)
  end

  # -- where the name maps are ------------------------------------------------------------

  @tag verifies: "fragments-name-map-positions"
  test "a :union or :deep key holds a name map, whose entries, lists and leaves are none" do
    yes = [[:styles], [:frames], [:frames, "main", :scales], [:sources], [:vars]]

    no = [
      [],
      [:styles, "x"],
      [:styles, "x", :fill],
      [:frames, "main"],
      [:frames, "main", :scales, "x"],
      [:marks],
      [:marks, 0],
      [:marks, 0, :data],
      [:theme],
      [:nope],
      [:nope, :styles],
      ["styles"],
      [:style]
    ]

    for path <- yes, do: assert(Fragment.name_map?(Design, path), inspect(path))
    for path <- no, do: refute(Fragment.name_map?(Design, path), inspect(path))
  end

  @tag verifies: "fragments-name-map-positions"
  test "below a tag, a use site's local is at the type's positions and every other part a node" do
    assert Fragment.name_map?(Design, [{:tag, "$use"}, "local", :styles])
    assert Fragment.name_map?(Design, [{:tag, "$use"}, :local, :frames, "m", :scales])
    refute Fragment.name_map?(Design, [{:tag, "$use"}, "local"])
    refute Fragment.name_map?(Design, [{:tag, "$use"}, "vars"])
    refute Fragment.name_map?(Design, [{:tag, "$var"}, "local", :styles])
    refute Fragment.name_map?(Design, [{:tag, "$use"}])
  end

  @tag verifies: "fragments-name-map-positions"
  test "a singular wrapper at the root leads to a node of the kind it names" do
    assert Fragment.name_map?(Wrapped, [:frame, :scales])
    assert Fragment.name_map?(Wrapped, [:frames, "a", :scales])
    refute Fragment.name_map?(Wrapped, [:frame])
    refute Fragment.name_map?(Wrapped, [:frame, :scales, "x"])
    # A wrapper names a kind only at the root.
    refute Fragment.name_map?(Wrapped, [:frames, "a", :frame, :scales])
  end

  # -- the codec at a name map ------------------------------------------------------------

  @tag verifies: "forms-name-maps"
  test "a name spelled like a type key round-trips as the name, in the map and JSON forms" do
    value = %{
      styles: %{"fill" => %{fill: %{opacity: 0.4}}, "$styles" => %{opacity: 0.5}},
      frames: %{"main" => %{kind: :cartesian, scales: %{"x" => %{type: :line}, "scale" => %{}}}}
    }

    assert {:ok, map} = Form.to_map(value, Design)
    assert map["styles"]["fill"] == %{"fill" => %{"opacity" => 0.4}}
    assert map["styles"]["$$styles"] == %{"opacity" => 0.5}
    assert Map.keys(map["frames"]["main"]["scales"]) |> Enum.sort() == ["scale", "x"]

    assert Form.from_map(map, Design) == {:ok, value}
    assert json(value) == {:ok, value}
  end

  @tag verifies: "forms-name-maps"
  test "at a node a string spelled like a type key is still refused, and at a name map an atom is" do
    assert Form.to_map(%{"marks" => [], styles: %{"s" => %{"fill" => 1}}}, Design) ==
             {:error, [{[:styles, "s", "fill"], :key_spelling}, {["marks"], :key_spelling}]}

    # Names are strings: an atom, even one of the type's keys, is no name.
    assert Form.to_map(%{styles: %{fill: %{}, primary: %{}}}, Design) ==
             {:error, [{[:styles, :fill], {:type, :name}}, {[:styles, :primary], {:type, :name}}]}

    assert Form.to_map(%{frames: %{"m" => %{scales: %{1 => %{}}}}}, Design) ==
             {:error, [{[:frames, "m", :scales, 1], {:type, :name}}]}
  end

  @tag verifies: "forms-name-maps"
  test "a use site's local is a fragment of the type: its names round-trip, wherever it stands" do
    use = %Use{
      id: {:use, 1},
      local: %{styles: %{"fill" => %{fill: %{opacity: 0.4}}}},
      vars: %{"n" => %{default: 1}},
      key: "fill"
    }

    value = %{composite: %{uses: [use]}, styles: %{"s" => %{fill: use}}}

    assert {:ok, map} = Form.to_map(value, Design)
    [written] = map["composite"]["uses"]

    assert written["$use"]["local"] == %{
             "styles" => %{"fill" => %{"fill" => %{"opacity" => 0.4}}}
           }

    assert Form.from_map(map, Design) == {:ok, value}
    assert json(value) == {:ok, value}

    # The local is placed as the reader reads it: an atom name there is no name.
    bad = %{composite: %{uses: [%{use | local: %{styles: %{fill: %{}}}}]}}
    assert {:error, [{[:composite, :uses, 0], {:type, :term}}]} = Form.to_map(bad, Design)

    assert Form.encode_term(%{styles: %{fill: %{}}}, Design, [{:tag, "$use"}, "local"]) ==
             {:error, [{[:styles, :fill], {:type, :name}}]}
  end

  @tag verifies: "forms-name-maps"
  test "below a tag every map is a node, written and read" do
    # A variable's payload is the tag's, so a name map's place under it is none.
    value = %{styles: %{"fill" => Var.new("fill")}}
    assert {:ok, %{"styles" => %{"fill" => %{"$var" => "fill"}}}} = Form.to_map(value, Design)
    assert json(value) == {:ok, value}
  end

  # -- the property -----------------------------------------------------------------------

  @spellings ~w(fill styles frames kind scales version theme id type text default)

  defp name do
    one_of([
      member_of(@spellings),
      string(:alphanumeric, min_length: 1, max_length: 4) |> map(&("n" <> &1)),
      string(:alphanumeric, max_length: 4) |> map(&("$" <> &1)),
      member_of(@spellings) |> map(&("$" <> &1)),
      string(:alphanumeric, max_length: 3) |> map(&("$$" <> &1))
    ])
  end

  defp leaf do
    one_of([
      constant(nil),
      boolean(),
      integer(),
      string(:printable, max_length: 5),
      member_of([:line, :area, :dark, :cartesian]),
      map(member_of(~w(a b)), &Var.new/1)
    ])
  end

  # An entry, a node: the type's keys, and string keys no type key spells.
  defp entry do
    map_of(
      one_of([
        member_of([:fill, :stroke, :opacity, :id, :type, :text]),
        string(:alphanumeric, min_length: 1, max_length: 3) |> map(&("n" <> &1))
      ]),
      leaf(),
      max_length: 3
    )
  end

  defp frame do
    gen all(
          kind <- member_of([:cartesian, :polar]),
          scales <- map_of(name(), entry(), max_length: 3)
        ) do
      %{kind: kind, scales: scales}
    end
  end

  defp design do
    optional_map(%{
      styles: map_of(name(), entry(), max_length: 4),
      sources: map_of(name(), entry(), max_length: 3),
      vars: map_of(name(), entry(), max_length: 2),
      frames: map_of(name(), frame(), max_length: 3),
      marks: list_of(entry(), max_length: 3)
    })
  end

  @tag verifies: "forms-name-maps"
  property "a value with names at name positions round-trips, its names' spellings whatever" do
    check all(v <- design()) do
      assert {:ok, map} = Form.to_map(v, Design)
      assert Form.from_map(map, Design) == {:ok, v}
      assert Form.to_map(elem(Form.from_map(map, Design), 1), Design) == {:ok, map}
      assert json(v) == {:ok, v}
    end
  end
end
