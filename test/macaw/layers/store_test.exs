defmodule Macaw.Layers.StoreTest do
  # The store behavior, the memory store and typed ids (spec/03 §1, §1.2, §2).
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Bundle, Store}
  alias Macaw.Layers.Store.Memory
  alias Macaw.Layers.Test.{Design, Layout}

  doctest Macaw.Layers.Store

  # A store that tells the test what it was asked, and with which context.
  defmodule Recorder do
    @moduledoc false
    @behaviour Macaw.Layers.Store

    def types(context), do: tell(context, :types, [Macaw.Layers.Test.Design])
    def list(context), do: tell(context, :list, {:ok, []})
    def get(id, context), do: tell(context, {:get, id}, {:error, :not_found})
    def put(entry, context), do: tell(context, {:put, entry}, {:ok, {:style, 1}})
    def delete(id, context), do: tell(context, {:delete, id}, :ok)

    def import(bundle, context),
      do: tell(context, {:import, bundle}, {:ok, %{ids: %{}, outside: []}})

    defp tell(nil, _call, answer), do: answer

    defp tell(pid, call, answer) do
      send(pid, {:called, call})
      answer
    end
  end

  setup do
    store = {Memory, start_supervised!({Memory, types: [Design, Layout]})}
    %{store: store}
  end

  defp entry(fragment, name \\ "entry"), do: %{id: nil, name: name, fragment: fragment}

  describe "the behavior (spec/03 §1)" do
    @tag verifies: "stores-behavior-calls"
    test "the store functions call the assign's module with its context, a bare module with nil" do
      assign = {Recorder, self()}
      bundle = %Bundle{}

      assert Store.split(assign) == {Recorder, self()} and
               Store.split(Recorder) == {Recorder, nil}

      assert Store.types(assign) == [Design]
      assert Store.list(assign) == {:ok, []}
      assert Store.get(assign, {:style, 1}) == {:error, :not_found}
      assert Store.put(assign, entry(%{style: %{}})) == {:ok, {:style, 1}}
      assert Store.delete(assign, {:style, 1}) == :ok
      assert Store.import(assign, bundle) == {:ok, %{ids: %{}, outside: []}}

      for call <- [
            :types,
            :list,
            {:get, {:style, 1}},
            {:put, entry(%{style: %{}})},
            {:delete, {:style, 1}},
            {:import, bundle}
          ],
          do: assert_received({:called, ^call})

      assert Store.types(Recorder) == [Design]
      refute_received {:called, _}
    end

    @tag verifies: "stores-behavior-calls"
    test "put issues an id to a new entry and replaces a held one; get answers it, and delete makes it not found",
         %{store: store} do
      assert {:ok, {:style, 1} = id} =
               Store.put(store, entry(%{style: %{stroke: "#111"}}, "Styles:thick"))

      assert Store.get(store, id) ==
               {:ok, %{id: id, name: "Styles:thick", fragment: %{style: %{stroke: "#111"}}}}

      assert Store.put(store, %{
               id: id,
               name: "Styles:thin",
               fragment: %{style: %{stroke: "#222"}}
             }) == {:ok, id}

      assert Store.get(store, id) ==
               {:ok, %{id: id, name: "Styles:thin", fragment: %{style: %{stroke: "#222"}}}}

      assert Store.get(store, {:style, 9}) == {:error, :not_found}

      assert Store.put(store, %{id: {:style, 9}, name: "x", fragment: %{style: %{}}}) ==
               {:error, :not_found}

      assert Store.delete(store, id) == :ok
      assert Store.get(store, id) == {:error, :not_found}
      assert Store.delete(store, id) == :ok
    end

    @tag verifies: "stores-behavior-calls"
    test "a fragment of no kind is refused, and a held id of another kind than its fragment" do
      store = {Memory, start_supervised!({Memory, types: [Design]}, id: :design_only)}

      assert Store.put(store, entry(%{theme: :dark, version: 1})) == {:error, :no_kind}
      assert Store.put(store, entry(%{})) == {:error, :no_kind}
      assert Store.put(store, entry(%{panel: %{columns: 2}})) == {:error, :no_kind}

      {:ok, id} = Store.put(store, entry(%{style: %{}}))

      assert Store.put(store, %{id: id, name: "m", fragment: %{mark: %{id: "m"}}}) ==
               {:error, {:kind, :style, :mark}}
    end

    @tag verifies: "stores-behavior-calls"
    test "the types are checked when configured: kinds unique across them, every kind sorted, each kind's type",
         %{store: store} do
      assert Store.types(store) == [Design, Layout]
      assert Store.kinds(store) == Enum.sort(Design.kinds() ++ Layout.kinds())
      assert Store.kinds([Layout]) == [:panel]
      assert Store.type_of(store, :panel) == Layout and Store.type_of(store, :style) == Design
      assert Store.type_of(store, :widget) == nil
      assert Store.kind(store, %{panel: %{}}) == {Layout, :panel}
      assert Store.kind(store, %{styles: %{"s" => %{}}}) == {Design, :style}
      assert Store.kind([Design, Layout], %{theme: :dark, panels: %{}}) == nil

      assert_raise ArgumentError, ~r/Layout and .*Layout both declare the kind :panel/, fn ->
        Memory.start_link(types: [Layout, Layout])
      end
    end

    @tag verifies: "stores-behavior-calls"
    test "a name's filing is its segments before the last, empty ones dropped" do
      assert Store.group("thick") == {[], "thick"}
      assert Store.group("Styles:thick") == {["Styles"], "thick"}
      assert Store.group("Styles:Lines:thick") == {["Styles", "Lines"], "thick"}
      assert Store.group("Styles::thick") == {["Styles"], "thick"}
      assert Store.group(":thick") == {[], "thick"}
    end
  end

  describe "the memory store (spec/03 §1.2)" do
    @tag verifies: "stores-memory-sequences"
    test "ids are issued per kind from one, a deleted id never reissued", %{store: store} do
      ids =
        for f <- [%{style: %{}}, %{mark: %{id: "m"}}, %{style: %{a: 1}}, %{panel: %{}}],
            do: elem(Store.put(store, entry(f)), 1)

      assert ids == [{:style, 1}, {:mark, 1}, {:style, 2}, {:panel, 1}]

      :ok = Store.delete(store, {:style, 2})
      assert Store.put(store, entry(%{style: %{b: 2}})) == {:ok, {:style, 3}}
      assert Store.get(store, {:style, 2}) == {:error, :not_found}
    end

    @tag verifies: "stores-memory-sequences"
    test "list answers the summaries ordered by id, each kind derived", %{store: store} do
      {:ok, _} = Store.put(store, entry(%{style: %{}}, "b"))
      {:ok, _} = Store.put(store, entry(%{panel: %{}}, "c"))
      {:ok, _} = Store.put(store, entry(%{style: %{x: 1}}, "a"))
      {:ok, _} = Store.put(store, entry(%{marks: [%{id: "m"}]}, "d"))

      assert Store.list(store) ==
               {:ok,
                [
                  %{id: {:mark, 1}, name: "d", kind: :mark},
                  %{id: {:panel, 1}, name: "c", kind: :panel},
                  %{id: {:style, 1}, name: "b", kind: :style},
                  %{id: {:style, 2}, name: "a", kind: :style}
                ]}
    end

    @tag verifies: "stores-memory-sequences"
    test "the store is a child a supervisor starts, by name, holding the types it was given" do
      start_supervised!({Memory, types: [Layout], name: :macaw_store_test_library}, id: :named)
      assert Store.types({Memory, :macaw_store_test_library}) == [Layout]
      assert Store.list({Memory, :macaw_store_test_library}) == {:ok, []}
    end
  end

  describe "ids and references (spec/03 §2)" do
    @tag verifies: "stores-ids-encoded"
    test "an id encodes as kind colon n and decodes against the kinds by spelling" do
      kinds = Store.kinds([Design, Layout])

      assert Store.encode_id({:style, 11}) == "style:11"
      assert Store.decode_id(kinds, "style:11") == {:ok, {:style, 11}}
      assert Store.decode_id(kinds, Store.encode_id({:panel, 3})) == {:ok, {:panel, 3}}

      for bad <- [
            "style:0",
            "style:-1",
            "style:1.5",
            "style:x",
            "style:",
            "style",
            ":3",
            "style:3:4",
            "",
            nil,
            3,
            {:style, 1}
          ],
          do: assert(Store.decode_id(kinds, bad) == :error)
    end

    @tag verifies: "stores-ids-encoded"
    test "an unknown kind is refused without making an atom" do
      spelling = "never_a_kind_of_any_type_131"
      assert Store.decode_id([:style], spelling <> ":1") == :error
      assert_raise ArgumentError, fn -> String.to_existing_atom(spelling) end
    end

    @tag verifies: "stores-ids-encoded"
    test "a reference of the wrong kind is refused before it is resolved" do
      assert Store.ref_kind({:style, 2}, :style) == :ok
      assert Store.ref_kind({:mark, 2}, :style) == {:error, {:ref_kind, :style, :mark}}
    end
  end
end
