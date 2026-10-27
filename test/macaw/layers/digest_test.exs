defmodule Macaw.Layers.DigestTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Document, Form, Vocabulary}

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
  test "a record cites a value by the digest of its map form, however the value was built" do
    built = %{title: "Q3", kind: :memo, tags: %{"b" => 2, "a" => 1}}
    rebuilt = Map.new([{:tags, Map.new([{"a", 1}, {"b", 2}])}, {:kind, :memo}, {:title, "Q3"}])

    {:ok, map} = Form.to_map(built, Note)
    {:ok, again} = Form.to_map(rebuilt, Note)
    {:ok, json} = Form.to_json(built, Note)

    cited = Document.digest(map)
    assert cited == Document.digest(again)
    assert cited == Document.digest(JSON.decode!(json))
    assert cited =~ ~r/\A[0-9a-f]{64}\z/

    # Any change to the value is a different citation.
    {:ok, edited} = Form.to_map(%{built | kind: :todo}, Note)
    refute Document.digest(edited) == cited
  end

  # A map form: string keys, JSON values.
  defp map_form do
    leaf =
      one_of([constant(nil), boolean(), integer(), float(), string(:printable, max_length: 6)])

    tree(leaf, fn inner ->
      one_of([
        list_of(inner, max_length: 4),
        map_of(string(:printable, max_length: 4), inner, max_length: 4)
      ])
    end)
    |> map(&%{"v" => &1})
  end

  # The same map form with every map's keys in reverse order: built from a list, so the
  # map is equal while its construction order differs.
  defp reordered(map) when is_map(map),
    do: map |> Enum.reverse() |> Enum.map(fn {k, v} -> {k, reordered(v)} end) |> Map.new()

  defp reordered(list) when is_list(list), do: Enum.map(list, &reordered/1)
  defp reordered(leaf), do: leaf

  @tag verifies: "digest-order"
  property "key order changes nothing, and the digest is 64 lowercase hex" do
    check all(m <- map_form()) do
      d = Document.digest(m)
      assert d == Document.digest(reordered(m))
      assert d =~ ~r/\A[0-9a-f]{64}\z/
    end

    # Insertion order, made visible: two maps built in opposite orders.
    a = Map.new([{"x", 1}, {"y", %{"p" => 1, "q" => 2}}])
    b = Map.new([{"y", Map.new([{"q", 2}, {"p", 1}])}, {"x", 1}])
    assert Document.digest(a) == Document.digest(b)
  end

  @tag verifies: "digest-round-trip"
  property "a map form and its JSON round trip have one digest" do
    check all(m <- map_form()) do
      assert Document.digest(m) == Document.digest(JSON.decode!(JSON.encode!(m)))
    end
  end

  @tag verifies: "digest-differs"
  property "different map forms have different digests" do
    check all(a <- map_form(), b <- map_form(), a != b) do
      assert Document.digest(a) != Document.digest(b)
    end

    refute Document.digest(%{"v" => 1}) == Document.digest(%{"v" => 1.0})
    refute Document.digest(%{"v" => "a"}) == Document.digest(%{"v" => ["a"]})
    refute Document.digest(%{"v" => nil}) == Document.digest(%{})
  end

  @tag verifies: "digest-golden"
  test "a fixed document's digest is the recorded one" do
    doc = %{
      "$version" => 1,
      "title" => "Sales",
      "kind" => %{"$atom" => "chart"},
      "size" => [16, 9, 2.5, -0.0, 1.0e21],
      "note" => "é\"\n"
    }

    assert Document.digest(doc) ==
             "7e60f849312595d03599decb268f1e0d24ab4230ef0c4fe5f9adf3b697f2abf4"
  end

  @tag verifies: "digest-not-map-form"
  test "a term that is not a map form raises, naming it" do
    assert_raise ArgumentError, ~r/keys are strings, got: :title/, fn ->
      Document.digest(%{title: "t"})
    end

    assert_raise ArgumentError, ~r/not a map form's value: :chart/, fn ->
      Document.digest(%{"kind" => :chart})
    end

    assert_raise ArgumentError, ~r/not a map form's value: \{:ratio, 16, 9\}/, fn ->
      Document.digest(%{"size" => [{:ratio, 16, 9}]})
    end
  end
end
