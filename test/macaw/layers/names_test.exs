defmodule Macaw.Layers.NamesTest do
  # "Makes no atom" is checked on the input's own names, never the node's atom count
  # (macaw_layers#1).
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Macaw.Layers.Names, only: [is_name: 1]
  alias Macaw.Layers.Names
  alias Macaw.Layers.Test.Atoms

  doctest Names

  defp guarded(v) when is_name(v), do: true
  defp guarded(_v), do: false

  @tag verifies: "names-name"
  test "an atom reads as its spelling, a string as it is, anything else untouched" do
    fresh = Atoms.fresh()

    assert Names.name(:sales) == "sales"
    assert Names.name("sales") == "sales"
    assert Names.name(fresh) == fresh

    for other <- [nil, true, false, 3, {:id, 1}, [:a]],
        do: assert(Names.name(other) == other)

    assert Atoms.made([fresh]) == []
  end

  @tag verifies: "names-predicate"
  test "name?/1 holds for a non-empty string or an atom; is_name/1 agrees but for the empty string" do
    for v <- ["a", :a], do: assert(Names.name?(v) and guarded(v))

    for v <- [nil, true, false, 1, [:a], %{}] do
      refute Names.name?(v)
      refute guarded(v)
    end

    refute Names.name?("")
    assert guarded("")
  end

  @tag verifies: "names-predicate"
  property "name?/1 and is_name/1 agree for every value but the empty string" do
    check all(
            v <-
              one_of([
                string(:printable),
                atom(:alphanumeric),
                integer(),
                boolean(),
                constant(nil)
              ])
          ) do
      assert Names.name?(v) == (guarded(v) and v != "")
    end
  end

  @tag verifies: "names-category"
  test "category values compare by spelling, booleans and nil excepted" do
    assert Names.category(:ok) == "ok"
    for v <- [nil, true, false, 1, 2.5, "ok"], do: assert(Names.category(v) == v)

    assert Names.same?(:ok, "ok")
    assert Names.same?("ok", :ok)
    assert Names.same?(1, 1)
    refute Names.same?(true, "true")
    refute Names.same?(nil, "nil")
    refute Names.same?(:ok, "OK")
  end

  @tag verifies: "names-keys"
  test "keys/1 rewrites a plain map's keys as names and leaves anything else" do
    assert Names.keys(%{:a => 1, "b" => 2}) == %{"a" => 1, "b" => 2}
    assert Names.keys(%{nil => 1}) == %{nil => 1}

    struct = URI.parse("https://example.com")
    assert Names.keys(struct) == struct
    assert Names.keys(a: 1) == [a: 1]
  end

  @tag verifies: "names-key"
  test "key/2 and fetch/2 find a name under either spelling, the exact key first" do
    assert Names.key(%{sales: 1}, "sales") == {:ok, :sales}
    assert Names.key(%{"sales" => 1}, :sales) == {:ok, "sales"}
    assert Names.key(%{"sales" => 1, sales: 2}, :sales) == {:ok, :sales}
    assert Names.key(%{"sales" => 1, sales: 2}, "sales") == {:ok, "sales"}
    assert Names.key(%{sales: 1}, "cost") == :error
    assert Names.key(%{1 => :a}, 1) == {:ok, 1}
    assert Names.key(%{"1" => :a}, 1) == :error

    assert Names.fetch(%{sales: 1}, "sales") == {:ok, 1}
    assert Names.fetch(%{"sales" => 1}, :sales) == {:ok, 1}
    assert Names.fetch(%{"sales" => 1}, "cost") == :error
  end

  @tag verifies: "kernel-names"
  test "no Names function makes an atom from a document's string" do
    fresh = for _ <- 1..500, do: Atoms.fresh()
    map = %{"a" => 1, b: 2}

    for s <- fresh do
      assert Names.name(s) == s
      assert Names.name?(s)
      assert Names.category(s) == s
      refute Names.same?(s, :b)
      assert Names.key(map, s) == :error
      assert Names.fetch(map, s) == :error
      assert Names.keys(%{s => 1}) == %{s => 1}
    end

    assert Atoms.made(fresh) == []
  end
end
