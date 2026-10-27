defmodule Macaw.Layers.Fragment.FormsTest do
  # The forms of variables, ids and use sites (spec/02 §9), over the test type.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Form, Fragment, Use, Var}
  alias Macaw.Layers.Test.Design

  defp round_trip(fragment) do
    {:ok, map} = Form.to_map(fragment, Design)

    {map, Form.from_map(map, Design),
     map |> JSON.encode!() |> JSON.decode!() |> Form.from_map(Design)}
  end

  @tag verifies: "fragments-forms-round-trip"
  test "a composite holding use sites, ids and variables round-trips through the map and JSON forms" do
    fragment = %{
      composite: %{
        uses: [
          %Use{
            id: {:use, 1},
            ref: {:style, 11},
            mask: [["stroke"]],
            vars: %{"color" => Var.new(:color_1)},
            local: %{style: %{opacity: 0.8}},
            key: "series"
          },
          %Use{id: {:use, 2}, mask: :all, origin: {:mark, 3}}
        ],
        vars: %{"color_1" => %{default: "blue"}}
      }
    }

    {map, from_map, from_json} = round_trip(fragment)
    assert from_map == {:ok, fragment}
    assert from_json == {:ok, fragment}

    [first, second] = map["composite"]["uses"]
    assert first["$use"]["ref"] == %{"$id" => ["style", 11]}
    assert first["$use"]["vars"] == %{"color" => %{"$var" => "color_1"}}
    assert second["$use"]["mask"] == "all"
    assert second["$use"]["origin"] == %{"$id" => ["mark", 3]}
  end

  @tag verifies: "fragments-forms-round-trip"
  test "a fragment of variables and ids at reference sites round-trips, and its tags are the file's" do
    fragment = %{
      styles: %{"s" => %{fill: Var.new(:c)}},
      marks: [%{id: "m", type: :line, style: {:style, 4}}],
      theme: Var.new("t")
    }

    {map, from_map, from_json} = round_trip(fragment)
    assert from_map == {:ok, fragment}
    assert from_json == {:ok, fragment}
    assert map["theme"] == %{"$var" => "t"}
    assert hd(map["marks"])["style"] == %{"$id" => ["style", 4]}

    assert Fragment.encode_value(Design, {:style, 0}) == :default
    assert Fragment.encode_value(Design, {:widget, 1}) == :default
    assert Fragment.encode_value(Design, "plain") == :default
    assert Fragment.encode_value(Design, %Use{id: {:use, 1}, local: %{style: self()}}) == :default

    assert {:error, [{[:theme], {:type, :term}}]} =
             Form.to_map(%{theme: %Use{id: {:use, 1}, local: %{a: self()}}}, Design)
  end

  @tag verifies: "fragments-forms-round-trip"
  test "an id of a kind the type does not hold, or a malformed payload, is refused at its path and makes no atom" do
    spelling = "widget_kind_never_an_atom_130"

    assert Form.from_map(%{"theme" => %{"$id" => [spelling, 3]}}, Design) ==
             {:error, [{[:theme], {:unknown_tag, "$id"}}]}

    assert_raise ArgumentError, fn -> String.to_existing_atom(spelling) end

    assert Form.from_map(%{"theme" => %{"$id" => ["style", 0]}}, Design) ==
             {:error, [{[:theme], {:unknown_tag, "$id"}}]}

    assert Form.from_map(%{"theme" => %{"$var" => ""}}, Design) ==
             {:error, [{[:theme], {:unknown_tag, "$var"}}]}

    assert Form.from_map(%{"theme" => %{"$use" => %{"ref" => nil}}}, Design) ==
             {:error, [{[:theme], {:unknown_tag, "$use"}}]}
  end
end
