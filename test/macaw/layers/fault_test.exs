defmodule Macaw.Layers.FaultTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.Fault

  doctest Fault

  @tag verifies: "faults-sort"
  test "faults are ordered by path, and faults at one path keep their order" do
    faults = [
      {[:marks, 1], :b},
      {[:marks, 0, "x"], :c},
      {[], :root},
      {[:marks, 1], :a},
      {[:frames], :d}
    ]

    assert Fault.sort(faults) == [
             {[], :root},
             {[:frames], :d},
             {[:marks, 0, "x"], :c},
             {[:marks, 1], :b},
             {[:marks, 1], :a}
           ]
  end

  @tag verifies: "faults-sort"
  property "sorting is total over generated paths, ordered and stable" do
    segment = one_of([atom(:alphanumeric), string(:alphanumeric), integer(0..20)])

    check all(faults <- list_of(tuple({list_of(segment, max_length: 4), integer()}))) do
      sorted = Fault.sort(faults)
      paths = Enum.map(sorted, &elem(&1, 0))
      assert paths == Enum.sort(paths)
      assert Enum.sort(sorted) == Enum.sort(faults)

      # Stable: at each path, the reasons in the order they were given.
      for path <- Enum.uniq(paths) do
        given = for {^path, r} <- faults, do: r
        kept = for {^path, r} <- sorted, do: r
        assert kept == given
      end
    end
  end

  @tag verifies: "faults-path"
  test "a path reads as keys joined by dots and indexes in brackets, the root by its name" do
    assert Fault.format_path([:marks, 0, :channels]) == "marks[0].channels"
    assert Fault.format_path([:frames, "main", "wdth"]) == "frames.main.wdth"
    assert Fault.format_path([0, :a]) == "[0].a"
    assert Fault.format_path([]) == "document"
    assert Fault.format_path([], root: "design") == "design"
    assert Fault.format({[], :required}, root: "design") == "design: is required"
  end

  @tag verifies: "faults-words"
  test "every reason the kernel words, as spec/01 §3's table says" do
    words = fn reason -> Fault.format({[:k], reason}) |> String.replace_prefix("k: ", "") end

    assert words.(:required) == "is required"
    assert words.(:unknown_key) == "is not a key of this node"

    assert words.(:key_spelling) ==
             "is a name spelled like a key of this document; it would read back as the key"

    assert words.({:enum, [:a, :b]}) == "must be one of :a, :b"

    assert words.({:unknown_atom, "wide"}) ==
             ~s("wide" is not an atom this reader knows; an adopter's atoms are given in vocabulary:)

    assert words.({:newer_schema, 4, 3}) == "needs schema v4, this is v3"
    assert words.({:limit, :bytes, 10, 12}) == "is 12 bytes; the limit bytes is 10"
    assert words.({:limit, :depth, 64, 65}) == "is nested 65 deep; the limit depth is 64"
    assert words.({:limit, :items, 5, 6}) == "holds at least 6 items; the limit items is 5"
    assert words.({:json, "unexpected byte"}) == "JSON does not parse: unexpected byte"
    assert words.({:unknown_tag, "$x"}) == ~s("$x" is not a tag this document reads)
    assert words.({:retired_tag, "$old", "was removed"}) == ~s("$old" was removed)

    for {type, expected} <- [
          string: "a string",
          name: "a name: a non-empty string",
          integer: "an integer",
          non_neg_integer: "a non-negative integer",
          pos_integer: "a positive integer",
          number: "a number",
          positive: "a positive number",
          boolean: "true or false",
          map: "a map",
          list: "a list",
          term:
            "a value with a document form: no function, PID, reference, port, tuple or struct",
          time: "an ISO 8601 time in UTC"
        ] do
      assert words.({:type, type}) == "must be #{expected}"
    end

    assert words.({:type, {:enum, [:x]}}) == "must be one of :x"
    assert words.({:type, {:list, :string}}) == "must be a list of a string"
    assert words.({:type, {:map, :number}}) == "must be a map from names to a number"
    assert words.({:type, {:node, :frame}}) == "must be a frame node"

    assert words.({:type, {:one_of, [:string, {:list, :integer}]}}) ==
             "must be a string or a list of an integer"
  end

  @tag verifies: "faults-fallback"
  test "a reason the kernel does not word is the type's, or inspected; none fails" do
    type_words = fn
      {:type, :color} -> "must be a color"
      {:type, {:list, :color}} -> "must be a list of colors"
      {:cycle, name} -> "#{name} is in a cycle"
    end

    assert Fault.format({[:a], {:cycle, "x"}}, words: type_words) == "a: x is in a cycle"
    assert Fault.format({[:a], {:type, :color}}, words: type_words) == "a: must be a color"

    # A compound type with a part the kernel does not word goes to the type whole.
    assert Fault.format({[:a], {:type, {:list, :color}}}, words: type_words) ==
             "a: must be a list of colors"

    # The kernel's own reasons stay the kernel's, whatever the type says.
    assert Fault.format({[:a], :required}, words: fn _ -> "never" end) == "a: is required"

    assert Fault.format({[:a], {:weird, 1}}) == "a: {:weird, 1}"

    assert Fault.format({[:a], {:type, {:one_of, [:string, :color]}}}) ==
             "a: {:type, {:one_of, [:string, :color]}}"
  end

  @tag verifies: "faults-fallback"
  property "format/2 words any reason" do
    check all(reason <- term()) do
      assert is_binary(Fault.format({[:k], reason}))
    end
  end

  @tag verifies: "kernel-faults"
  test "a reader's faults, every one, ordered by path and each worded by the one formatter" do
    # As a reader reports them: in the order it met them, an unknown key at its own spelling.
    faults = [
      {[:frames, "main", "wdth"], :unknown_key},
      {[:marks, 0, :channels], :required},
      {[], {:newer_schema, 2, 1}},
      {[:marks, 0, :x], {:type, :number}}
    ]

    assert faults |> Fault.sort() |> Enum.map(&Fault.format(&1, root: "design")) == [
             "design: needs schema v2, this is v1",
             "frames.main.wdth: is not a key of this node",
             "marks[0].channels: is required",
             "marks[0].x: must be a number"
           ]
  end
end
