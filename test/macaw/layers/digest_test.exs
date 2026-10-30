defmodule Macaw.Layers.DigestTest do
  # The digest is over the value itself (spec/01 §7, #3): any data term, never a
  # representation of it.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Document, Form, Var, Vocabulary}

  defmodule Note.Tags do
    use Macaw.Layers.Tags
  end

  defmodule Note do
    @behaviour Macaw.Layers.Form

    @impl true
    def tags, do: Note.Tags
    @impl true
    def keys, do: Vocabulary.table([:title, :kind, :tags])
    @impl true
    def atoms, do: Vocabulary.table([:memo, :todo])
  end

  @tag verifies: "kernel-digest"
  test "a record cites a value by its digest, however it was built, and its own forms are other values" do
    built = %{title: "Q3", kind: :memo, tags: %{"b" => 2, "a" => 1}}
    rebuilt = Map.new([{:tags, Map.new([{"a", 1}, {"b", 2}])}, {:kind, :memo}, {:title, "Q3"}])

    cited = Document.digest(built)
    assert cited == Document.digest(rebuilt)
    assert cited =~ ~r/\A[0-9a-f]{64}\z/

    # Any change to the value is a different citation.
    refute Document.digest(%{built | kind: :todo}) == cited

    # The map form is a representation, a different term: it has a digest of its own.
    {:ok, map} = Form.to_map(built, Note)
    refute Document.digest(map) == cited
  end

  # Data terms: every kind the encoding tags, nested.
  defp data do
    leaf =
      one_of([
        constant(nil),
        boolean(),
        integer(),
        float(),
        string(:printable, max_length: 6),
        member_of([:a, :b, :memo]),
        member_of([~D[2026-10-29], ~U[2026-10-29 12:00:00Z], Var.new("v")]),
        map(integer(0..64), &Integer.pow(2, 64 + &1))
      ])

    tree(leaf, fn inner ->
      one_of([
        list_of(inner, max_length: 4),
        map(list_of(inner, max_length: 3), &List.to_tuple/1),
        map_of(one_of([string(:printable, max_length: 4), atom(:alphanumeric)]), inner,
          max_length: 4
        )
      ])
    end)
  end

  # The same term with every map rebuilt from its pairs in reverse order: an equal map whose
  # construction order differs.
  defp reordered(%_{} = struct), do: struct

  defp reordered(map) when is_map(map),
    do: map |> Enum.reverse() |> Enum.map(fn {k, v} -> {k, reordered(v)} end) |> Map.new()

  defp reordered(list) when is_list(list), do: Enum.map(list, &reordered/1)

  defp reordered(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> reordered() |> List.to_tuple()

  defp reordered(leaf), do: leaf

  @tag verifies: "digest-order"
  property "key order changes nothing, and the digest is 64 lowercase hex" do
    check all(t <- data()) do
      d = Document.digest(t)
      assert d == Document.digest(reordered(t))
      assert d =~ ~r/\A[0-9a-f]{64}\z/
    end

    a = Map.new([{"x", 1}, {:y, %{"p" => 1, "q" => 2}}])
    b = Map.new([{:y, Map.new([{"q", 2}, {"p", 1}])}, {"x", 1}])
    assert Document.digest(a) == Document.digest(b)
  end

  @tag verifies: "digest-differs"
  property "different terms have different digests" do
    check all(a <- data(), b <- data(), a !== b) do
      assert Document.digest(a) != Document.digest(b)
    end

    pairs = [
      {1, 1.0},
      {0.0, -0.0},
      {:a, "a"},
      {{:a}, [:a]},
      {nil, "nil"},
      {%{v: nil}, %{}},
      {"ab", ["a", "b"]},
      {[[], []], [[[]]]},
      {<<1::3>>, <<1::3, 0::5>>},
      {Var.new("v"), Map.from_struct(Var.new("v"))},
      {DateTime.from_unix!(0), DateTime.from_unix!(0, :microsecond)},
      {~U[2026-10-29 12:00:00Z],
       DateTime.shift_zone!(~U[2026-10-29 12:00:00Z], "Etc/UTC") |> Map.put(:zone_abbr, "X")}
    ]

    for {a, b} <- pairs, do: refute(Document.digest(a) == Document.digest(b), inspect({a, b}))
  end

  @tag verifies: "digest-golden"
  test "fixed values' digests are the recorded ones" do
    golden = [
      {nil, "f925af3d1d75cc8481a42b9f539e972fb5866ee4b3585cc50bfe024393b0e5dd"},
      {%{"$version" => 1, title: "Sales", kind: :chart, size: {16, 9}, at: [2.5, -0.0]},
       "33c35a0ea6d505e406a6fc1edea1824ec637e1145e826e20e7f20a2b445d89fe"},
      {%{note: "é\"\n", big: Integer.pow(2, 80), on: ~D[2026-10-29], bits: <<5::3>>},
       "e88bd16e1cdc5be235a82908b0b65620e0b385bcb385c64d9c93407b2b91122d"}
    ]

    for {value, digest} <- golden, do: assert({value, Document.digest(value)} == {value, digest})
  end

  @tag verifies: "digest-canonical"
  test "a struct implementing the protocol digests as its canonical term, wherever it sits" do
    alias Macaw.Layers.Test.Chunked
    rows = [%{"v" => 1}, %{"v" => 2.5}, %{"v" => nil}, %{"v" => "x"}, %{"v" => 5}]
    [a, b] = [Chunked.new(rows, 2), Chunked.new(rows, 3)]

    # Two layouts of one value: different structs, one digest, the canonical term's.
    refute a == b
    assert Document.digest(a) == Document.digest(b)
    assert Document.digest(a) == Document.digest({"test.chunked", rows})

    # Nested anywhere, it is encoded as its canonical term.
    for wrap <- [&%{"t" => &1}, &[1, &1], &{:ok, &1}],
        do: assert(Document.digest(wrap.(a)) == Document.digest(wrap.(b)))

    refute Document.digest(Chunked.new(Enum.reverse(rows), 2)) == Document.digest(a)

    # A struct without an implementation is its map, __struct__ and all, as before.
    at = ~U[2026-10-30 12:00:00Z]

    assert Document.digest(at) ==
             Document.digest(Map.from_struct(at) |> Map.put(:__struct__, DateTime))
  end

  @tag verifies: "digest-canonical"
  property "the digest is the SHA-256 of the version byte and encode/1" do
    check all(term <- data()) do
      hashed = :crypto.hash(:sha256, [Document.encoding_version() | Document.encode(term)])
      assert Base.encode16(hashed, case: :lower) == Document.digest(term)
    end
  end

  @tag verifies: "digest-not-data"
  test "a term that is not data raises, naming it" do
    for term <- [fn -> :ok end, self(), make_ref(), [1 | 2], %{"k" => [self()]}] do
      assert_raise ArgumentError, ~r/not data, so it has no digest/, fn ->
        Document.digest(term)
      end
    end
  end
end
