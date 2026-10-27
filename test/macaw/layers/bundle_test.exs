defmodule Macaw.Layers.BundleTest do
  # Bundles: the closure, the forms and import as a relocation (spec/03 §3).
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Bundle, Store, Use, Var}
  alias Macaw.Layers.Store.Memory
  alias Macaw.Layers.Test.{Design, Layout}

  @types [Design, Layout]
  @at ~U[2026-10-20 09:30:00.000000Z]

  setup do
    %{store: library(), other: {Memory, start_supervised!({Memory, types: @types}, id: :other)}}
  end

  # style 1, a mark 1 using it, a panel 1, and a composite 1 whose sites use all three.
  defp library do
    store = {Memory, start_supervised!({Memory, types: @types}, id: :library)}

    {:ok, style} =
      Store.put(store, %{id: nil, name: "Styles:thick", fragment: %{style: %{stroke: "#111"}}})

    {:ok, mark} =
      Store.put(store, %{id: nil, name: "Marks:line", fragment: %{mark: %{id: "m", style: style}}})

    {:ok, _panel} =
      Store.put(store, %{id: nil, name: "Panels:wide", fragment: %{panel: %{columns: 2}}})

    uses = [
      %Use{id: {:use, 1}, ref: mark},
      %Use{id: {:use, 2}, local: %{style: %{fill: Var.new(:c)}}, origin: style, key: "local"}
    ]

    {:ok, {:composite, 1}} =
      Store.put(store, %{id: nil, name: "Charts:one", fragment: %{composite: %{uses: uses}}})

    store
  end

  defp bundle(entries, store \\ "lib"),
    do: %Bundle{provenance: %{store: store, exported_at: @at, version: 1}, entries: entries}

  describe "export (spec/03 §3.1)" do
    @tag verifies: "stores-bundle-closure"
    test "export follows every reference transitively, use sites included, dependencies first and each once",
         %{store: store} do
      bundle = Bundle.export(store, {:composite, 1}, "lib")

      assert Enum.map(bundle.entries, & &1.id) == [{:style, 1}, {:mark, 1}, {:composite, 1}]
      assert Enum.map(bundle.entries, & &1.name) == ["Styles:thick", "Marks:line", "Charts:one"]

      assert %{store: "lib", version: 1, exported_at: %DateTime{time_zone: "Etc/UTC"}} =
               bundle.provenance

      assert bundle.snapshot == nil

      both =
        Bundle.export(store, [{:mark, 1}, {:composite, 1}, {:panel, 1}, {:mark, 1}], :library)

      assert Enum.map(both.entries, & &1.id) == [
               {:style, 1},
               {:mark, 1},
               {:composite, 1},
               {:panel, 1}
             ]

      assert both.provenance.store == :library
    end

    @tag verifies: "stores-bundle-closure"
    test "an id the store no longer holds is skipped, so the bundle carries what exists", %{
      store: store
    } do
      :ok = Store.delete(store, {:style, 1})

      assert Enum.map(Bundle.export(store, {:composite, 1}, "lib").entries, & &1.id) == [
               {:mark, 1},
               {:composite, 1}
             ]

      assert Bundle.export(store, [{:style, 9}, {:panel, 7}], "lib").entries == []
    end
  end

  describe "the forms (spec/03 §3.2)" do
    @tag verifies: "stores-bundle-round-trip"
    test "a bundle round-trips through its map and JSON forms, each part in its own form", %{
      store: store
    } do
      bundle = Bundle.export(store, [{:composite, 1}, {:panel, 1}], "lib")

      {:ok, map} = Bundle.to_map(bundle, @types)
      assert map["$version"] == 1
      assert map["provenance"]["store"] == "lib"
      assert map["snapshot"] == nil

      assert Enum.map(map["entries"], & &1["id"]) == [
               "style:1",
               "mark:1",
               "composite:1",
               "panel:1"
             ]

      assert Enum.at(map["entries"], 1)["fragment"] == %{
               "mark" => %{"id" => "m", "style" => %{"$id" => ["style", 1]}}
             }

      assert Enum.at(map["entries"], 3)["fragment"] == %{
               "$version" => 2,
               "panel" => %{"columns" => 2}
             }

      assert Bundle.from_map(map, @types) == {:ok, bundle}

      {:ok, json} = Bundle.to_json(bundle, @types)
      assert Bundle.from_json(json, @types) == {:ok, bundle}

      named = %{
        bundle
        | provenance: %{bundle.provenance | store: :lib},
          snapshot: %{"cell" => [1, 2]}
      }

      {:ok, json} = Bundle.to_json(named, @types)

      assert Bundle.from_json(json, @types) ==
               {:ok, %{named | provenance: %{named.provenance | store: "lib"}}}
    end

    @tag verifies: "stores-bundle-round-trip"
    test "a fragment carries its type's stamp and migrates on reading, and a newer one is refused at its path" do
      old = %{
        "$version" => 1,
        "entries" => [
          %{
            "id" => "panel:1",
            "name" => "p",
            "fragment" => %{"$version" => 1, "panel" => %{"cols" => 3}}
          }
        ]
      }

      map =
        Map.put(old, "provenance", %{
          "store" => "lib",
          "exported_at" => "2026-10-20T09:30:00.000000Z",
          "version" => 1
        })

      assert {:ok, %Bundle{entries: [%{fragment: %{panel: %{columns: 3}}}]}} =
               Bundle.from_map(map, @types)

      newer = put_in(map, ["entries", Access.at(0), "fragment", "$version"], 3)

      assert Bundle.from_map(newer, @types) ==
               {:error, [{[:entries, 0, :fragment], {:newer_schema, 3, 2}}]}
    end

    @tag verifies: "stores-bundle-round-trip"
    test "a newer stamp is refused before any key is read, and the limits apply over the whole document" do
      assert Bundle.from_map(%{"$version" => 2, "anything" => [1]}, @types) ==
               {:error, [{[], {:newer_schema, 2, 1}}]}

      assert Bundle.from_json(~s({"$version": 9, "entries": 3}), @types) ==
               {:error, [{[], {:newer_schema, 9, 1}}]}

      entries =
        for n <- 1..4, do: %{"id" => "style:#{n}", "name" => "s", "fragment" => %{"style" => %{}}}

      map = %{
        "provenance" => %{
          "store" => "lib",
          "exported_at" => "2026-10-20T09:30:00Z",
          "version" => 1
        },
        "entries" => entries
      }

      # Each entry and the provenance hold three keys, within the limit; the list holds four.
      assert Bundle.from_map(map, @types, limits: [items: 3]) ==
               {:error, [{["entries"], {:limit, :items, 3, 4}}]}

      assert {:error, [{["entries"], {:limit, :items, 3, 4}}]} =
               Bundle.from_json(JSON.encode!(map), @types, limits: [items: 3])

      assert {:ok, %Bundle{entries: [_, _, _, _]}} = Bundle.from_map(map, @types)
    end

    @tag verifies: "stores-bundle-round-trip"
    test "every fault of the envelope is at its path: unknown keys, required parts, a bad time, parts of the wrong type" do
      map = %{
        "extra" => 1,
        "provenance" => %{"store" => 7, "exported_at" => "2026-10-20T09:30:00+02:00", "ver" => 1},
        "entries" => [%{"id" => "style:1", "fragment" => 3, "note" => "x"}, "entry"],
        "snapshot" => [1]
      }

      assert Bundle.from_map(map, @types) ==
               {:error,
                [
                  {[:entries, 0, :fragment], {:type, :map}},
                  {[:entries, 0, :name], :required},
                  {[:entries, 0, "note"], :unknown_key},
                  {[:entries, 1], {:type, :map}},
                  {[:provenance, :exported_at], {:type, :utc_datetime}},
                  {[:provenance, :store], {:type, :string}},
                  {[:provenance, :version], :required},
                  {[:provenance, "ver"], :unknown_key},
                  {[:snapshot], {:type, :map}},
                  {["extra"], :unknown_key}
                ]}

      assert Bundle.from_map(%{}, @types) ==
               {:error, [{[:entries], :required}, {[:provenance], :required}]}

      assert Bundle.from_map(%{"provenance" => 1, "entries" => %{}}, @types) ==
               {:error, [{[:entries], {:type, :list}}, {[:provenance], {:type, :map}}]}

      bad = %{
        "provenance" => %{
          "store" => "lib",
          "exported_at" => "2026-10-20T09:30:00Z",
          "version" => 0
        },
        "entries" => [%{"id" => 1, "name" => 2, "fragment" => %{}}]
      }

      assert Bundle.from_map(bad, @types) ==
               {:error,
                [
                  {[:entries, 0, :id], {:type, :id}},
                  {[:entries, 0, :name], {:type, :string}},
                  {[:provenance, :version], {:type, :pos_integer}}
                ]}

      assert Bundle.from_map([], @types) == {:error, [{[], {:type, :map}}]}
      assert {:error, [{[], {:json, _words}}]} = Bundle.from_json("{not json", @types)
      assert Bundle.from_json("[1]", @types) == {:error, [{[], {:type, :map}}]}
    end

    @tag verifies: "stores-bundle-round-trip"
    test "every fault of an entry is at its path: an id of no kind, a duplicate, a fragment that does not read or has no kind" do
      spelling = "no_kind_of_any_type_132"

      entries = [
        %{"id" => spelling <> ":1", "name" => "a", "fragment" => %{"style" => %{}}},
        %{"id" => "style:1", "name" => "b", "fragment" => %{"style" => %{}}},
        %{"id" => "style:1", "name" => "c", "fragment" => %{"style" => %{}}},
        %{
          "id" => "mark:1",
          "name" => "d",
          "fragment" => %{"mark" => %{"style" => %{"$nope" => 1}}}
        },
        %{
          "id" => "style:2",
          "name" => "e",
          "fragment" => %{"theme" => %{"$atom" => "dark"}, "version" => 2}
        },
        %{"id" => "style:3", "name" => "f", "fragment" => %{"mark" => %{}}}
      ]

      map = %{
        "provenance" => %{
          "store" => "lib",
          "exported_at" => "2026-10-20T09:30:00Z",
          "version" => 1
        },
        "entries" => entries
      }

      assert Bundle.from_map(map, @types) ==
               {:error,
                [
                  {[:entries, 0, :id], {:type, :id}},
                  {[:entries, 2, :id], {:duplicate, {:style, 1}}},
                  {[:entries, 3, :fragment, "mark", "style"], {:unknown_tag, "$nope"}},
                  {[:entries, 4, :fragment], :no_kind},
                  {[:entries, 5, :fragment], {:kind, :style, :mark}}
                ]}

      assert_raise ArgumentError, fn -> String.to_existing_atom(spelling) end
    end

    @tag verifies: "stores-bundle-round-trip"
    test "a value with no form is refused when written, not written" do
      assert Bundle.to_map(bundle([], {:not, :a, :name}), @types) ==
               {:error, [{[:provenance, :store], {:type, :string}}]}

      entries = [
        %{id: {:style, 1}, name: "s", fragment: %{style: %{stroke: self()}}},
        %{id: {:widget, 1}, name: "w", fragment: %{}}
      ]

      assert {:error,
              [
                {[:entries, 0, :fragment, :style, :stroke], {:type, :term}},
                {[:entries, 1, :id], {:type, :id}}
              ]} = Bundle.to_map(bundle(entries), @types)
    end
  end

  describe "import (spec/03 §3.3)" do
    @tag verifies: "stores-import-relocation"
    test "import issues new ids and rewrites every reference through one table, use sites included",
         %{store: store, other: other} do
      {:ok, _} = Store.put(other, %{id: nil, name: "already", fragment: %{style: %{}}})
      {:ok, _} = Store.put(other, %{id: nil, name: "already", fragment: %{mark: %{id: "z"}}})

      assert Store.import(other, Bundle.export(store, {:composite, 1}, "lib")) ==
               {:ok,
                %{
                  ids: %{
                    {:style, 1} => {:style, 2},
                    {:mark, 1} => {:mark, 2},
                    {:composite, 1} => {:composite, 1}
                  },
                  outside: []
                }}

      assert {:ok, %{fragment: %{mark: %{id: "m", style: {:style, 2}}}}} =
               Store.get(other, {:mark, 2})

      {:ok, %{fragment: %{composite: %{uses: [linked, unlocked]}}}} =
        Store.get(other, {:composite, 1})

      assert %Use{ref: {:mark, 2}} = linked
      assert %Use{origin: {:style, 2}, ref: nil, key: "local"} = unlocked
    end

    @tag verifies: "stores-import-relocation"
    test "a bundle read from its JSON form imports as the in-memory one did, its fragments migrated",
         %{store: store, other: other} do
      bundle = Bundle.export(store, [{:composite, 1}, {:panel, 1}], "lib")
      {:ok, json} = Bundle.to_json(bundle, @types)

      json =
        String.replace(json, ~s("columns":2), ~s("cols":2))
        |> String.replace(~s("$version":2), ~s("$version":1))

      {:ok, read} = Bundle.from_json(json, @types)
      assert {:ok, %{ids: %{{:panel, 1} => {:panel, 1}}}} = Store.import(other, read)
      assert {:ok, %{fragment: %{panel: %{columns: 2}}}} = Store.get(other, {:panel, 1})
    end

    @tag verifies: "stores-import-relocation"
    test "a reference outside the bundle imports as it is and is reported by the entry that holds it",
         %{other: other} do
      entries = [%{id: {:mark, 4}, name: "m", fragment: %{mark: %{id: "m", style: {:style, 9}}}}]

      assert Store.import(other, bundle(entries)) ==
               {:ok, %{ids: %{{:mark, 4} => {:mark, 1}}, outside: [{{:style, 9}, [:entries, 0]}]}}

      assert {:ok, %{fragment: %{mark: %{style: {:style, 9}}}}} = Store.get(other, {:mark, 1})
    end

    @tag verifies: "stores-import-relocation"
    test "every check runs before anything is written: a bundle that does not read, and the host's check",
         %{other: other} do
      entries = [
        %{id: {:style, 1}, name: "fine", fragment: %{style: %{}}},
        %{id: {:style, 2}, name: "s", fragment: %{theme: :dark, version: 2}}
      ]

      assert Store.import(other, bundle(entries)) ==
               {:error, [{[:entries, 1, :fragment], :no_kind}]}

      assert Store.list(other) == {:ok, []}

      check = fn
        %{name: "Unknown:" <> _} -> {:error, [{[:name], :unknown_name}]}
        _entry -> :ok
      end

      checked = {Memory, start_supervised!({Memory, types: @types, check: check}, id: :checked)}

      entries = [
        %{id: {:style, 1}, name: "fine", fragment: %{style: %{}}},
        %{id: {:style, 2}, name: "Unknown:x", fragment: %{style: %{}}}
      ]

      assert Store.import(checked, bundle(entries)) ==
               {:error, [{[:entries, 1, :name], :unknown_name}]}

      assert Store.list(checked) == {:ok, []}
      assert {:ok, _imported} = Store.import(checked, bundle(Enum.take(entries, 1)))
    end

    @tag verifies: "stores-import-relocation"
    test "a write failing midway commits nothing, in a transaction, and is reported at its entry",
         %{other: other} do
      {_module, agent} = other

      entries =
        for n <- 1..3,
            do: %{id: {:style, n}, name: "s#{n}", fragment: %{style: %{stroke_width: n}}}

      failing = fn
        %{name: "s2"}, _state ->
          {:error, :disk_full}

        entry, state ->
          {:ok, entry.id || {:style, map_size(state) + 1}, Map.put(state, entry.name, entry)}
      end

      transaction = fn run ->
        Agent.get_and_update(agent, fn state ->
          case run.(%{}, failing) do
            {:ok, imported, _copy} -> {{:ok, imported}, state}
            {:error, faults} -> {{:error, faults}, state}
          end
        end)
      end

      assert Store.relocate(other, bundle(entries), transaction: transaction) ==
               {:error, [{[:entries, 1], :disk_full}]}

      assert Store.list(other) == {:ok, []}

      # Without a transaction the writes go through the store's own put, one by one.
      assert {:ok, %{ids: %{{:style, 1} => {:style, 1}}}} =
               Store.relocate(other, bundle(Enum.take(entries, 1)))

      assert {:ok, %{name: "s1", fragment: %{style: %{stroke_width: 1}}}} =
               Store.get(other, {:style, 1})
    end
  end
end
