defmodule Macaw.Layers.CallbackTest do
  # Each site that asks for an optional callback, with the type module unloaded first: the
  # callback is still found (spec/01 §9, #4). Only this test unloads `ColdDesign`, so it
  # can run beside the rest.
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Callback, Form, Fragment, Var}
  alias Macaw.Layers.Test.ColdDesign

  # Unloads the type, as a fresh `iex` or test run has it before anything touches it.
  defp cold do
    :code.purge(ColdDesign)
    :code.delete(ColdDesign)
    refute :code.is_loaded(ColdDesign)
  end

  @tag verifies: "callbacks-unloaded"
  test "exported?/3 loads the module first, and raises for one that doesn't exist" do
    cold()
    assert Callback.exported?(ColdDesign, :identity, 2)
    refute Callback.exported?(ColdDesign, :no_such_callback, 1)
    assert_raise ArgumentError, fn -> Callback.exported?(NoSuchModule.AtAll, :x, 0) end
  end

  @tag verifies: "callbacks-unloaded"
  test "Form writes and reads a type's own value with the type unloaded" do
    # encode_term/2 asks for encode_value/1 before anything else touches the type.
    cold()
    assert Form.encode_term(Var.new("t"), ColdDesign) == {:ok, %{"$var" => "t"}}

    cold()

    assert {:ok, %{"text" => %{"$var" => "t"}} = map} =
             Form.to_map(%{text: Var.new("t")}, ColdDesign)

    cold()
    assert Form.from_map(map, ColdDesign) == {:ok, %{text: Var.new("t")}}
  end

  @tag verifies: "callbacks-unloaded"
  test "the cascade replaces an element by its identity with the type unloaded" do
    lower = %{marks: [%{id: "series", type: :line}, %{type: :rule}]}
    higher = %{marks: [%{id: "series", type: :area}]}

    cold()

    assert Fragment.stack(ColdDesign, lower, higher).marks == [
             %{id: "series", type: :area},
             %{type: :rule}
           ]
  end
end
