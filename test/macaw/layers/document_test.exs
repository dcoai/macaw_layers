defmodule Macaw.Layers.DocumentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Document, Fault, Limits, Scan}

  doctest Document

  # A page at version 2. Version 1 held its blocks flat; step 1 wraps each in
  # `%{"block" => …}`, which deepens the document by one.
  defmodule Page do
    @behaviour Macaw.Layers.Version
    @behaviour Macaw.Layers.Document

    @impl Macaw.Layers.Version
    def current, do: 2

    @impl Macaw.Layers.Version
    def step(doc, 1),
      do: {:ok, Map.update(doc, "blocks", [], fn bs -> Enum.map(bs, &%{"block" => &1}) end)}

    @impl Macaw.Layers.Document
    def validate(doc) do
      send(self(), :validated)

      faults =
        Document.unknown_keys(doc, ["$version", "title", "blocks"]) ++
          if(is_binary(doc["title"]), do: [], else: [{["title"], :required}])

      if faults == [], do: :ok, else: {:error, faults}
    end
  end

  defp json(term), do: JSON.encode!(term)

  @tag verifies: "kernel-gates"
  test "a fetched document goes through every gate, in order, and is read as data only" do
    # As fetched: JSON from elsewhere, at version 1, with a key no page has.
    fetched =
      ~s|{"$version": 1, "title": "Sales", "blocks": ["a", "b"], "on_load": "System.halt()"}|

    assert Document.read(fetched, Page) == {:error, [{["on_load"], :unknown_key}]}
    assert_received :validated

    # Without it, the same document is read, migrated and returned at version 2.
    clean = ~s|{"$version": 1, "title": "Sales", "blocks": ["a", "b"]}|

    assert Document.read(clean, Page) ==
             {:ok,
              %{
                "$version" => 2,
                "title" => "Sales",
                "blocks" => [%{"block" => "a"}, %{"block" => "b"}]
              }}

    # The map form reads the same, and a host's tighter limits apply to both: at depth 2
    # the document passes, and its migrated blocks, one level deeper, do not.
    assert {:ok, _} = Document.read(JSON.decode!(clean), Page)

    grown =
      {:error,
       [
         {["blocks", 0], {:limit, :depth, 2, 3}},
         {["blocks", 1], {:limit, :depth, 2, 3}}
       ]}

    assert Document.read(clean, Page, limits: [depth: 2]) == grown
    assert Document.read(JSON.decode!(clean), Page, limits: [depth: 2]) == grown
  end

  @tag verifies: "gates-bytes"
  test "the bytes gate refuses one byte over a tightened limit, alone" do
    doc = json(%{"title" => "t"})
    size = byte_size(doc)

    assert {:ok, _} = Document.read(doc, Page, limits: [bytes: size])

    assert Document.read(doc, Page, limits: [bytes: size - 1]) ==
             {:error, [{[], {:limit, :bytes, size - 1, size}}]}

    # Over the limit and malformed: only the bytes fault, nothing decoded.
    assert Document.read("{" <> String.duplicate("x", 20), Page, limits: [bytes: 10]) ==
             {:error, [{[], {:limit, :bytes, 10, 21}}]}

    # The map form has no bytes.
    assert {:ok, _} =
             Document.read(%{"title" => String.duplicate("t", 50)}, Page, limits: [bytes: 10])
  end

  defp reductions(fun) do
    {:reductions, before} = Process.info(self(), :reductions)
    result = fun.()
    {:reductions, later} = Process.info(self(), :reductions)
    {later - before, result}
  end

  @tag verifies: "gates-scan-stops"
  test "a million deep, or a million entries, is refused at the first limit with bounded work" do
    deep = String.duplicate("[", 1_000_000)
    wide = "[" <> String.duplicate("1,", 1_000_000) <> "1]"
    limits = Limits.new(items: 1_000)

    {work, result} = reductions(fn -> Scan.scan(deep, limits) end)
    assert {:error, {path, {:limit, :depth, 64, 65}}} = result
    assert length(path) == 64
    assert work < 50_000, "the scan did #{work} reductions on a 1 MB document"

    {work, result} = reductions(fn -> Scan.scan(wide, limits) end)
    assert result == {:error, {[], {:limit, :items, 1_000, 1_001}}}
    assert work < 50_000, "the scan did #{work} reductions on a 2 MB document"

    # Reading the whole of the wide document costs far more: the scan stopped early.
    {decode_work, _} = reductions(fn -> JSON.decode(wide) end)
    assert decode_work > 10 * work

    # Through read/3, the same faults.
    assert {:error, [{_, {:limit, :depth, 64, 65}}]} = Document.read(deep, Page)
  end

  @tag verifies: "gates-scan-paths"
  test "the scan's fault names the container's path, and strings are not structure" do
    limits = Limits.new(depth: 3)

    assert Scan.scan(~s({"a": [1, "x]}{,\\"", {"b": [3]}]}), limits) ==
             {:error, {["a", 2, "b"], {:limit, :depth, 3, 4}}}

    assert Scan.scan(~s({"k\\u0041\\"": {"n": [[1]]}}), limits) ==
             {:error, {["kA\"", "n", 0], {:limit, :depth, 3, 4}}}

    assert Scan.scan(~s({"a": "[[[[", "b": [1, 2, 3]}), Limits.new(items: 2)) ==
             {:error, {["b"], {:limit, :items, 2, 3}}}

    assert Scan.scan(~s({"a": 1, "b": 2, "c": 3}), Limits.new(items: 2)) ==
             {:error, {[], {:limit, :items, 2, 3}}}

    assert Scan.scan(~s([{"a": "]]]]"}, [true, null, -1.5e3]]), limits) == :ok
  end

  # A JSON value: scalars, and lists and maps of them, a few levels deep.
  defp json_value do
    scalar = one_of([integer(), boolean(), constant(nil), string(:printable, max_length: 6)])

    tree(scalar, fn inner ->
      one_of([
        list_of(inner, max_length: 5),
        map_of(string(:printable, max_length: 4), inner, max_length: 5)
      ])
    end)
  end

  @tag verifies: "gates-scan-agrees"
  property "the scan and the walk of the decoded value agree" do
    check all(
            value <- json_value(),
            depth <- integer(1..6),
            items <- integer(1..6)
          ) do
      limits = Limits.new(depth: depth, items: items)
      walked = Limits.structure(value, limits)

      case Scan.scan(json(value), limits) do
        :ok ->
          assert walked == []

        {:error, {path, {:limit, kind, max, _given}}} ->
          assert Enum.any?(walked, &match?({^path, {:limit, ^kind, ^max, _}}, &1)),
                 "scan: #{inspect({path, kind})}, walk: #{inspect(walked)}"
      end
    end
  end

  @tag verifies: "gates-json"
  test "malformed JSON is one fault at the root, and a root that is not an object is refused" do
    for bad <- ["{", "{\"a\": }", "[1,]", "tru", "1 2", "", "\"\\u12\"", "}"] do
      assert {:error, [{[], {:json, words}}]} = Document.read(bad, Page)
      assert is_binary(words)
      assert Fault.format({[], {:json, words}}) =~ "JSON does not parse"
    end

    for not_object <- ["[]", "1", "\"page\"", "null"],
        do: assert(Document.read(not_object, Page) == {:error, [{[], {:type, :map}}]})

    assert Document.read(:page, Page) == {:error, [{[], {:type, :map}}]}
  end

  @tag verifies: "gates-json"
  property "no bytes make the scan or the read fail" do
    check all(bytes <- one_of([binary(), string(:printable)])) do
      assert Scan.scan(bytes, Limits.defaults()) == :ok or
               match?({:error, {_, {:limit, _, _, _}}}, Scan.scan(bytes, Limits.defaults()))

      assert match?({:ok, _}, Document.read(bytes, Page)) or
               match?({:error, [_ | _]}, Document.read(bytes, Page))
    end
  end

  @tag verifies: "gates-order"
  test "each gate stops the ones after it, and the last reports all its faults" do
    # Newer: refused by name, validate never runs.
    assert Document.read(json(%{"$version" => 3, "ttle" => 1}), Page) ==
             {:error, [{[], {:newer_schema, 3, 2}}]}

    refute_received :validated

    # Over a limit: no version read, though the stamp is newer.
    assert {:error, [{_, {:limit, :items, 2, 3}}]} =
             Document.read(json(%{"$version" => 9, "a" => 1, "b" => 2}), Page, limits: [items: 2])

    refute_received :validated

    # Valid at version 1: migrated, then validated.
    assert Document.read(json(%{"$version" => 1, "title" => "t", "blocks" => ["x"]}), Page) ==
             {:ok, %{"$version" => 2, "title" => "t", "blocks" => [%{"block" => "x"}]}}

    assert_received :validated

    # The type's faults and the recount's, together, ordered by path: at version 1 the
    # document passes depth 2, and the migration wraps its block one level deeper.
    doc = json(%{"$version" => 1, "ttle" => "t", "blocks" => ["x"]})

    assert Document.read(doc, Page, limits: [depth: 2]) ==
             {:error,
              [
                {["blocks", 0], {:limit, :depth, 2, 3}},
                {["title"], :required},
                {["ttle"], :unknown_key}
              ]}
  end

  @tag verifies: "gates-recount"
  test "a migration that grows a document past a limit is refused after it" do
    assert {:ok, _} =
             Document.read(
               json(%{"$version" => 2, "title" => "t", "blocks" => [%{"block" => "x"}]}),
               Page,
               limits: [depth: 3]
             )

    assert Document.read(json(%{"$version" => 1, "title" => "t", "blocks" => [["x"]]}), Page,
             limits: [depth: 3]
           ) ==
             {:error, [{["blocks", 0, "block"], {:limit, :depth, 3, 4}}]}

    # The map form is walked before and after: the same.
    assert Document.read(%{"$version" => 1, "title" => "t", "blocks" => [["x"]]}, Page,
             limits: [depth: 3]
           ) ==
             {:error, [{["blocks", 0, "block"], {:limit, :depth, 3, 4}}]}
  end

  @tag verifies: "gates-limits"
  test "limits tighten, keep their defaults otherwise, and never loosen" do
    assert Limits.defaults() == %{bytes: 8_000_000, depth: 64, items: 100_000}
    assert Limits.new(items: 10) == %{bytes: 8_000_000, depth: 64, items: 10}
    assert Limits.new(%{depth: 3, bytes: 100}) == %{bytes: 100, depth: 3, items: 100_000}
    assert Limits.new([]) == Limits.defaults()

    for bad <- [
          [items: 100_001],
          [depth: 65],
          [bytes: 8_000_001],
          [items: 0],
          [depth: -1],
          [items: 1.5],
          [items: "5"],
          [rows: 3]
        ] do
      assert_raise ArgumentError, fn -> Limits.new(bad) end
    end

    assert_raise ArgumentError, fn -> Document.read("{}", Page, limits: [items: 200_000]) end
  end

  @tag verifies: "gates-limits-raise"
  test "a host raises a named limit only by saying so, and the raised value still holds" do
    assert Limits.new(items: {:raise, 500_000}) == %{bytes: 8_000_000, depth: 64, items: 500_000}
    assert Limits.new(depth: {:raise, 65}, items: 10).depth == 65

    # One entry over the default reads under a raise, and one over the raise is refused.
    blocks = fn n -> JSON.encode!(%{"title" => "t", "blocks" => List.duplicate(["x"], n)}) end

    assert {:error, [{["blocks"], {:limit, :items, 100_000, 100_001}}]} =
             Document.read(blocks.(100_001), Page)

    assert {:ok, %{"blocks" => read}} =
             Document.read(blocks.(100_001), Page, limits: [items: {:raise, 100_001}])

    assert length(read) == 100_001

    assert Document.read(blocks.(100_002), Page, limits: [items: {:raise, 100_001}]) ==
             {:error, [{["blocks"], {:limit, :items, 100_001, 100_002}}]}

    for bad <- [
          [items: {:raise, 100_000}],
          [items: {:raise, 10}],
          [items: {:raise, 1.5e6}],
          [items: {:lift, 200_000}],
          [rows: {:raise, 5}]
        ] do
      assert_raise ArgumentError, fn -> Limits.new(bad) end
    end
  end

  @tag verifies: "gates-unknown-keys"
  test "unknown keys are refused at their own spelling, under the path" do
    map = %{"title" => 1, "ttle" => 2, "Title" => 3, "blocks" => 4}

    assert Document.unknown_keys(map, ["title", "blocks"], [:pages, 0]) ==
             [{[:pages, 0, "Title"], :unknown_key}, {[:pages, 0, "ttle"], :unknown_key}]

    assert Document.unknown_keys(map, ["title", "ttle", "Title", "blocks"]) == []
    assert Document.unknown_keys(%{}, []) == []
  end
end
