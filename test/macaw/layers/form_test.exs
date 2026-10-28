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

      assert {:ok, json} = Form.to_json(v, Card)
      assert {:ok, read} = Form.from_json(json, Card)
      assert read == Map.put_new(v, "$version", 1)
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
    assert Form.from_json(json, Card) == {:ok, value}

    # Read through the gates: a host's limits apply to the JSON form.
    assert {:error, [{[], {:limit, :items, 2, 3}}]} =
             Form.from_json(json, Card, limits: [items: 2])
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
                {[:kind], {:enum, [:chart, :table, :text]}}
              ]}

    assert Atoms.made([fresh]) == []

    # A time with an offset is not UTC, so it is not the kernel's $time.
    assert Form.from_map(%{"at" => %{"$time" => "2026-10-27T12:00:00+02:00"}}, Card) ==
             {:error, [{[:at], {:type, :time}}]}
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
