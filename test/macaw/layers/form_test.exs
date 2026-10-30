defmodule Macaw.Layers.FormTest do
  # The atom table is the node's: nothing else may run while it is counted.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Form, Tags, Vocabulary}
  alias Macaw.Layers.Test.Atoms

  doctest Tags

  defmodule Card.Tags do
    use Macaw.Layers.Tags,
      live: ~w($ratio $color),
      retired: %{"$cols" => "was removed: say columns"},
      renamed: %{"$tint" => "$color"}
  end

  # A card at version 1: its keys, the atoms its documents may spell, and a value of its
  # own, `{:ratio, a, b}`, written under `$ratio`. `$color` is live but not read here.
  defmodule Card do
    @behaviour Macaw.Layers.Version
    @behaviour Macaw.Layers.Document
    @behaviour Macaw.Layers.Form

    @impl Macaw.Layers.Version
    def current, do: 1
    @impl Macaw.Layers.Version
    def step(_doc, from), do: raise("Card has no step from #{from}")

    @impl Macaw.Layers.Document
    def validate(_doc), do: :ok

    @impl Macaw.Layers.Form
    def tags, do: Card.Tags
    @impl Macaw.Layers.Form
    def keys, do: Vocabulary.table([:title, :blocks, :at, :kind, :size])
    @impl Macaw.Layers.Form
    def atoms, do: Vocabulary.table([:chart, :table, :text])

    @impl Macaw.Layers.Form
    def encode_value({:ratio, a, b}) when is_integer(a) and is_integer(b),
      do: {:ok, %{"$ratio" => [a, b]}}

    def encode_value(_), do: :default

    @impl Macaw.Layers.Form
    def decode_value("$ratio", [a, b]) when is_integer(a) and is_integer(b),
      do: {:ok, {:ratio, a, b}}

    def decode_value(_tag, _payload), do: :default
  end

  @at ~U[2026-10-27 12:00:00.123456Z]

  # -- generators -------------------------------------------------------------------------

  defp name do
    one_of([
      string(:alphanumeric, min_length: 1, max_length: 5) |> map(&("n" <> &1)),
      string(:alphanumeric, max_length: 4) |> map(&("$" <> &1)),
      string(:alphanumeric, max_length: 4) |> map(&("$$" <> &1))
    ])
  end

  defp leaf do
    one_of([
      constant(nil),
      boolean(),
      integer(),
      float(),
      string(:printable, max_length: 6),
      member_of([:chart, :table, :text]),
      constant(@at),
      tuple({constant(:ratio), integer(), integer()})
    ])
  end

  defp value do
    tree(leaf(), fn inner ->
      one_of([
        list_of(inner, max_length: 4),
        map_of(one_of([member_of([:title, :blocks, :at, :kind, :size]), name()]), inner,
          max_length: 4
        )
      ])
    end)
  end

  defp document do
    gen all(
          body <-
            map_of(one_of([member_of([:title, :blocks, :at, :kind, :size]), name()]), value(),
              max_length: 5
            ),
          stamped <- boolean()
        ) do
      if stamped, do: Map.put(body, "$version", 1), else: body
    end
  end

  # -- tests ------------------------------------------------------------------------------

  @tag verifies: "forms-round-trip"
  property "a valid value round-trips through the map form and the JSON form" do
    check all(v <- document()) do
      assert {:ok, map} = Form.to_map(v, Card)
      assert Form.from_map(map, Card) == {:ok, v}
      assert Form.to_map(elem(Form.from_map(map, Card), 1), Card) == {:ok, map}

      # The JSON form is stamped with the type's version, and the adapter's read drops it.
      assert {:ok, json} = Form.to_json(v, Card)
      assert JSON.decode!(json)["$version"] == 1
      assert Form.read(json, Card) == {:ok, Map.delete(v, "$version")}
    end
  end

  @tag verifies: "kernel-forms"
  test "one value in its three forms, each the exact inverse of the next" do
    value = %{
      "$version" => 1,
      :title => "Sales",
      :kind => :chart,
      :size => {:ratio, 16, 9},
      "$cost" => %{"region" => [1, 2.5]}
    }

    map = %{
      "$version" => 1,
      "title" => "Sales",
      "kind" => %{"$atom" => "chart"},
      "size" => %{"$ratio" => [16, 9]},
      "$$cost" => %{"region" => [1, 2.5]}
    }

    assert Form.to_map(value, Card) == {:ok, map}
    assert Form.from_map(map, Card) == {:ok, value}

    assert {:ok, json} = Form.to_json(value, Card)
    assert JSON.decode!(json) == map

    # Read through the gates to the map form at the current version, then to the value,
    # the stamp the line's and not data.
    assert Form.gates(json, Card) == {:ok, map}
    assert Form.read(json, Card) == {:ok, Map.delete(value, "$version")}
    assert Form.read(map, Card) == {:ok, Map.delete(value, "$version")}

    # A host's limits apply to the JSON form and the map form alike.
    assert {:error, [{[], {:limit, :items, 2, 3}}]} = Form.read(json, Card, limits: [items: 2])
    assert {:error, [{[], {:limit, :items, 2, 5}}]} = Form.gates(map, Card, limits: [items: 2])
  end

  @tag verifies: "forms-json-stamp"
  test "to_json stamps a type with a version line and no other, and read refuses a newer stamp" do
    assert {:ok, json} = Form.to_json(%{title: "t"}, Card)
    assert JSON.decode!(json) == %{"$version" => 1, "title" => "t"}

    # A fragment type with no version line is written with no stamp.
    alias Macaw.Layers.Test.Design
    assert {:ok, json} = Form.to_json(%{styles: %{"s" => %{fill: "red"}}}, Design)
    assert JSON.decode!(json) == %{"styles" => %{"s" => %{"fill" => "red"}}}

    assert Form.read(~s({"$version": 2, "title": "t"}), Card) ==
             {:error, [{[], {:newer_schema, 2, 1}}]}

    # A tag the value reads wrong stops the read before the value is judged.
    assert Form.read(~s({"kind": {"$atom": "chart_9q"}}), Card) ==
             {:error, [{[:kind], {:unknown_atom, "chart_9q"}}]}
  end

  @tag verifies: "forms-terms"
  test "each kernel term has its map form, and a bad $atom or $time is refused" do
    v = %{title: "t", kind: :chart, at: @at, size: 1.5, blocks: [nil, true, 3, [:text]]}

    assert Form.to_map(v, Card) ==
             {:ok,
              %{
                "title" => "t",
                "kind" => %{"$atom" => "chart"},
                "at" => %{"$time" => "2026-10-27T12:00:00.123456Z"},
                "size" => 1.5,
                "blocks" => [nil, true, 3, [%{"$atom" => "text"}]]
              }}

    # Checked on the document's own spelling, never the node's atom count (macaw_layers#1).
    fresh = Atoms.fresh()

    assert Form.from_map(
             %{"kind" => %{"$atom" => fresh}, "at" => %{"$time" => "yesterday"}},
             Card
           ) ==
             {:error,
              [
                {[:at], {:type, :time}},
                {[:kind], {:unknown_atom, fresh}}
              ]}

    assert Atoms.made([fresh]) == []

    # A time with an offset is not UTC, so it is not the kernel's $time.
    assert Form.from_map(%{"at" => %{"$time" => "2026-10-27T12:00:00+02:00"}}, Card) ==
             {:error, [{[:at], {:type, :time}}]}
  end

  @tag verifies: "forms-vocabulary"
  test "the vocabulary is the reader's: words given by code read as atoms, and no others" do
    # Words the type's tables lack, as an adopter registers them: existing atoms, given
    # by code. The document's other spellings are fresh, so no atom can be made of them.
    words = %{keys: [:caption], atoms: [:figure]}
    fresh_key = Atoms.fresh()
    fresh_atom = Atoms.fresh()
    map = %{"caption" => %{"$atom" => "figure"}, "kind" => %{"$atom" => "chart"}}

    assert Form.from_map(map, Card, vocabulary: words) ==
             {:ok, %{caption: :figure, kind: :chart}}

    # Without them the key stays its string and the atom is refused by its spelling, the
    # type's own atoms read as before.
    assert Form.from_map(map, Card) ==
             {:error, [{["caption"], {:unknown_atom, "figure"}}]}

    assert {:ok, json} = Form.to_json(%{caption: :figure, kind: :chart}, Card, vocabulary: words)
    assert Form.read(json, Card, vocabulary: words) == {:ok, %{caption: :figure, kind: :chart}}
    assert {:error, [{["caption"], {:unknown_atom, "figure"}}]} = Form.read(json, Card)

    # A word the vocabulary lacks is refused at its path, a fresh spelling made no atom.
    assert Form.from_map(
             %{fresh_key => 1, "kind" => %{"$atom" => fresh_atom}},
             Card,
             vocabulary: words
           ) == {:error, [{[:kind], {:unknown_atom, fresh_atom}}]}

    assert Atoms.made([fresh_key, fresh_atom]) == []

    # Writing: an atom key is the type's or the vocabulary's, else :unknown_key.
    assert Form.to_map(%{caption: 1}, Card) == {:error, [{[:caption], :unknown_key}]}
    assert Form.to_map(%{caption: 1}, Card, vocabulary: words) == {:ok, %{"caption" => 1}}

    for bad <- [[keys: [:a]], %{keys: ["a"]}, %{words: [:a]}, %{atoms: [nil]}] do
      assert_raise ArgumentError, ~r/vocabulary: is %\{keys: \[atom\], atoms: \[atom\]\}/, fn ->
        Form.from_map(map, Card, vocabulary: bad)
      end
    end
  end

  @tag verifies: "forms-keys"
  test "keys read against the type's table, and a value's keys are checked when written" do
    assert Form.from_map(%{"title" => 1, "ttle" => 2, "$$x" => 3}, Card) ==
             {:ok, %{:title => 1, "ttle" => 2, "$x" => 3}}

    assert Form.to_map(%{:titel => 1, "title" => 2, 3 => 4, "ok" => %{nope: 5}}, Card) ==
             {:error,
              [
                {[3], {:type, :name}},
                {[:titel], :unknown_key},
                {["ok", :nope], :unknown_key},
                {["title"], :key_spelling}
              ]}
  end

  @tag verifies: "forms-name-maps"
  test "a type without name_map?/1 has no name maps: every map is a node, at any depth" do
    refute Macaw.Layers.Callback.exported?(Card, :name_map?, 1)

    assert Form.from_map(%{"blocks" => %{"n" => %{"title" => 1, "$$size" => 2}}}, Card) ==
             {:ok, %{blocks: %{"n" => %{:title => 1, "$size" => 2}}}}

    assert Form.to_map(%{blocks: %{"n" => %{"title" => 1}, "size" => 2}}, Card) ==
             {:error,
              [{[:blocks, "n", "title"], :key_spelling}, {[:blocks, "size"], :key_spelling}]}
  end

  @tag verifies: "forms-no-functions"
  test "values with no document form are refused at their path, all of them" do
    v = %{
      title: fn -> :x end,
      blocks: [self(), make_ref(), {:a, :b}, URI.parse("https://x"), 1],
      kind: :chart
    }

    assert Form.to_map(v, Card) ==
             {:error,
              [
                {[:blocks, 0], {:type, :term}},
                {[:blocks, 1], {:type, :term}},
                {[:blocks, 2], {:type, :term}},
                {[:blocks, 3], {:type, :term}},
                {[:title], {:type, :term}}
              ]}

    assert Form.to_map([1], Card) == {:error, [{[], {:type, :map}}]}
    assert Form.from_map("x", Card) == {:error, [{[], {:type, :map}}]}
  end

  @tag verifies: "forms-own-values"
  test "encode_term writes one term's map form for a payload of the type's own, or its faults by path" do
    assert Form.encode_term([:chart, @at, %{size: {:ratio, 16, 9}}], Card) ==
             {:ok,
              [
                %{"$atom" => "chart"},
                %{"$time" => DateTime.to_iso8601(@at)},
                %{"size" => %{"$ratio" => [16, 9]}}
              ]}

    assert Form.encode_term("plain", Card) == {:ok, "plain"}
    assert Form.encode_term(%{size: self()}, Card) == {:error, [{[:size], {:type, :term}}]}
  end

  @tag verifies: "forms-own-values"
  test "a type's own value goes through its live tag, and a live tag it doesn't read is refused" do
    assert Form.to_map(%{size: {:ratio, 16, 9}}, Card) ==
             {:ok, %{"size" => %{"$ratio" => [16, 9]}}}

    assert Form.from_map(%{"size" => %{"$ratio" => [16, 9]}}, Card) ==
             {:ok, %{size: {:ratio, 16, 9}}}

    assert Form.from_map(%{"size" => %{"$color" => "red"}}, Card) ==
             {:error, [{[:size], {:unknown_tag, "$color"}}]}

    assert Form.from_map(%{"size" => %{"$ratio" => "16:9"}}, Card) ==
             {:error, [{[:size], {:unknown_tag, "$ratio"}}]}
  end

  @tag verifies: "tags-read"
  test "the table renames, refuses unknown and retired tags by path, and leaves $$ keys as data" do
    doc = %{
      "a" => %{"$tint" => "red"},
      "b" => [%{"$nope" => 1}, %{"$cols" => 3}],
      "c" => %{"$$data" => 1}
    }

    assert Tags.read(doc, Card.Tags) ==
             {:error,
              [
                {["b", 0], {:unknown_tag, "$nope"}},
                {["b", 1], {:retired_tag, "$cols", "was removed: say columns"}}
              ]}

    assert Card.Tags.read(%{"a" => %{"$tint" => "red"}, "c" => %{"$$data" => 1}}) ==
             {:ok, %{"a" => %{"$color" => "red"}, "c" => %{"$$data" => 1}}}

    assert Macaw.Layers.Fault.format(
             {["b", 1], {:retired_tag, "$cols", "was removed: say columns"}}
           ) ==
             ~s(b[1]: "$cols" was removed: say columns)

    assert "$atom" in Card.Tags.live() and "$ratio" in Card.Tags.live()
    assert Card.Tags.renamed() == %{"$tint" => "$color"}
  end

  @tag verifies: "tags-escape"
  property "escape and unescape are inverses on every key, and the root stamp is not escaped" do
    check all(key <- one_of([string(:printable), map(string(:printable), &("$" <> &1))])) do
      assert Tags.unescape(Tags.escape(key)) == key
      if String.starts_with?(key, "$"), do: assert(Tags.escape(key) == "$" <> key)
    end

    assert Form.to_map(%{"$version" => 1, "$p" => %{"$version" => 2}}, Card) ==
             {:ok, %{"$version" => 1, "$$p" => %{"$$version" => 2}}}

    assert Form.from_map(%{"$version" => 1}, Card) == {:ok, %{"$version" => 1}}
  end

  @tag verifies: "tags-compile"
  test "a literal tag the table lacks is a compile error; a computed one is checked when called" do
    assert_raise CompileError,
                 ~r/"\$nope" is not a live tag of Macaw.Layers.FormTest.Card.Tags/,
                 fn ->
                   Code.compile_string("""
                   defmodule Macaw.Layers.FormTest.Writer do
                     require Macaw.Layers.FormTest.Card.Tags, as: T
                     def write, do: T.tag("$nope", 1)
                   end
                   """)
                 end

    [{module, _}] =
      Code.compile_string("""
      defmodule Macaw.Layers.FormTest.Computed do
        require Macaw.Layers.FormTest.Card.Tags, as: T
        def write(name), do: T.tag(name, 1)
        def literal, do: T.tag("$ratio", [1, 2])
      end
      """)

    assert module.write("$ratio") == %{"$ratio" => 1}
    assert module.literal() == %{"$ratio" => [1, 2]}
    assert_raise ArgumentError, ~r/"\$nope" is not a live tag/, fn -> module.write("$nope") end

    assert_raise ArgumentError, ~r/a tag starts with a single \$/, fn ->
      Code.compile_string("""
      defmodule Macaw.Layers.FormTest.BadTable do
        use Macaw.Layers.Tags, live: ~w($$double)
      end
      """)
    end
  end
end
