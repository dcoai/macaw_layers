defmodule Macaw.Layers.VersionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.Version

  # A type at version 3. Each step appends the version it migrates from, and the stamp it
  # saw, to the document's "trail", so a test sees which steps ran and in what order.
  defmodule Layout do
    @behaviour Macaw.Layers.Version

    @impl true
    def current, do: 3

    @impl true
    def step(doc, from) when from in [1, 2] do
      {:ok,
       Map.update(doc, "trail", [{from, doc["$version"]}], &(&1 ++ [{from, doc["$version"]}]))}
    end
  end

  # Another type, with a line of its own.
  defmodule Note do
    @behaviour Macaw.Layers.Version

    @impl true
    def current, do: 1

    @impl true
    def step(_doc, from), do: raise("Note has no step from #{from}")
  end

  # A type whose second step refuses the document.
  defmodule Strict do
    @behaviour Macaw.Layers.Version

    @impl true
    def current, do: 3

    @impl true
    def step(doc, 1), do: {:ok, Map.put(doc, "one", true)}

    def step(_doc, 2),
      do: {:error, [{["z"], :required}, {["a", 0], {:type, :string}}]}
  end

  # The moduledoc's example type: `cols` became `columns` at version 2.
  defmodule Grid do
    @behaviour Macaw.Layers.Version

    @impl true
    def current, do: 2

    @impl true
    def step(%{"cols" => cols} = doc, 1),
      do: {:ok, doc |> Map.delete("cols") |> Map.put("columns", cols)}

    def step(doc, 1), do: {:ok, doc}
  end

  @tag verifies: "kernel-versions"
  test "a type's line: its stamp read first, its steps run, the current stamp written" do
    # The stamp is a string key in either form, and the kernel writes it after the step.
    assert Version.migrate(%{"$version" => 1, "cols" => 3}, Grid) ==
             {:ok, %{"$version" => 2, "columns" => 3}}

    assert Version.migrate(%{"$version" => 2, "columns" => 3}, Grid) ==
             {:ok, %{"$version" => 2, "columns" => 3}}

    assert Version.check(%{"$version" => 3, "cols" => 3}, Grid) ==
             {:error, [{[], {:newer_schema, 3, 2}}]}
  end

  @tag verifies: "versions-unstamped"
  test "a document with no stamp is current, and migrates unchanged but for the stamp" do
    doc = %{"title" => "t"}
    assert Version.check(doc, Layout) == {:ok, 3}
    assert Version.migrate(doc, Layout) == {:ok, %{"title" => "t", "$version" => 3}}
    assert Version.stamp() == "$version"
  end

  @tag verifies: "versions-newer"
  test "a newer stamp is refused by name alone, and a malformed one at the stamp" do
    # Whatever else the document holds, nothing of it is read.
    doc = %{"$version" => 4, "trail" => :not_a_list, "junk" => fn -> :x end}
    assert Version.check(doc, Layout) == {:error, [{[], {:newer_schema, 4, 3}}]}
    assert Version.migrate(doc, Layout) == {:error, [{[], {:newer_schema, 4, 3}}]}

    for bad <- [0, -1, 1.0, "2", nil] do
      fault = {:error, [{["$version"], {:type, :pos_integer}}]}
      assert Version.check(%{"$version" => bad}, Layout) == fault
      assert Version.migrate(%{"$version" => bad}, Layout) == fault
    end
  end

  @tag verifies: "versions-steps"
  test "an old document runs each step in order, seeing the stamp it migrates from" do
    assert Version.migrate(%{"$version" => 1}, Layout) ==
             {:ok, %{"$version" => 3, "trail" => [{1, 1}, {2, 2}]}}

    assert Version.migrate(%{"$version" => 2}, Layout) ==
             {:ok, %{"$version" => 3, "trail" => [{2, 2}]}}

    assert Version.migrate(%{"$version" => 3, "x" => 1}, Layout) ==
             {:ok, %{"$version" => 3, "x" => 1}}
  end

  @tag verifies: "versions-lines"
  test "each type reads a document against its own line" do
    assert Version.check(%{"$version" => 2}, Note) == {:error, [{[], {:newer_schema, 2, 1}}]}
    assert Version.check(%{"$version" => 2}, Layout) == {:ok, 2}
    assert Version.migrate(%{"$version" => 1}, Note) == {:ok, %{"$version" => 1}}

    assert {:ok, %{"$version" => 3}} = Version.migrate(%{"$version" => 1}, Layout)
  end

  @tag verifies: "versions-step-faults"
  test "a step's faults stop the migration, ordered by path" do
    assert Version.migrate(%{"$version" => 1}, Strict) ==
             {:error, [{["a", 0], {:type, :string}}, {["z"], :required}]}
  end

  @tag verifies: "versions-pure"
  property "migrating is repeatable, and a migrated document migrates to itself" do
    check all(
            from <- integer(1..3),
            body <- map_of(map(string(:alphanumeric), &("k" <> &1)), integer(), max_length: 4)
          ) do
      doc = Map.put(body, "$version", from)
      assert {:ok, once} = Version.migrate(doc, Layout)
      assert Version.migrate(doc, Layout) == {:ok, once}
      assert Version.migrate(once, Layout) == {:ok, once}
      assert once["$version"] == 3
    end
  end
end
