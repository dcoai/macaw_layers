defmodule Macaw.Layers.VocabularyTest do
  # The atom table is the node's: nothing else may run while it is counted.
  use ExUnit.Case, async: false

  alias Macaw.Layers.Vocabulary

  @anchors Vocabulary.table([:title, :caption])

  @tag verifies: "vocabulary-lookup"
  test "a string is looked up, in a table or a list, and anything else is :error" do
    assert @anchors == %{"title" => :title, "caption" => :caption}
    assert Vocabulary.table([:title, :caption]) == @anchors

    for vocabulary <- [@anchors, [:title, :caption]] do
      assert Vocabulary.fetch(vocabulary, "title") == {:ok, :title}
      assert Vocabulary.fetch(vocabulary, "footer") == :error
      assert Vocabulary.fetch(vocabulary, :title) == :error
      assert Vocabulary.fetch(vocabulary, 1) == :error
      assert Vocabulary.read(vocabulary, "caption") == :caption
      assert Vocabulary.read(vocabulary, "footer") == "footer"
    end
  end

  # A string no atom has been made of: unique to this run.
  defp fresh, do: "zz#{System.unique_integer([:positive])}q#{:rand.uniform(1_000_000_000)}"

  @tag verifies: "vocabulary-no-atoms"
  test "reading fresh strings makes no atom, and read/2 returns each as it was" do
    strings = for _ <- 1..2_000, do: fresh()
    # Warm up: load every module the reads reach.
    Vocabulary.read(@anchors, "warm")
    Vocabulary.fetch([:title], "warm")

    before = :erlang.system_info(:atom_count)

    for s <- strings do
      assert Vocabulary.fetch(@anchors, s) == :error
      assert Vocabulary.fetch([:title, :caption], s) == :error
      assert Vocabulary.read(@anchors, s) == s
    end

    assert :erlang.system_info(:atom_count) == before
  end

  # The atom-making calls, as remote calls in code; none may appear in the library. Read
  # from the parsed source, so prose that names one (as this module's own docs do) is not
  # a call.
  @makers [
    {String, :to_atom},
    {String, :to_existing_atom},
    {List, :to_atom},
    {List, :to_existing_atom},
    {:erlang, :binary_to_atom},
    {:erlang, :binary_to_existing_atom},
    {:erlang, :list_to_atom},
    {:erlang, :list_to_existing_atom}
  ]

  defp calls(source) do
    {_, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, _} = node, acc ->
          {node, [{Module.concat(parts), fun} | acc]}

        {{:., _, [module, fun]}, _, _} = node, acc when is_atom(module) ->
          {node, [{module, fun} | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  @tag verifies: "kernel-vocabulary"
  test "the library never makes an atom from a string, nor asks whether one exists" do
    sources = Path.wildcard("lib/**/*.ex")
    assert sources != []

    for path <- sources do
      made = path |> File.read!() |> calls() |> Enum.filter(&(&1 in @makers))
      assert made == [], "#{path} calls #{inspect(made)}"
    end

    # The walk sees a call when there is one.
    assert {String, :to_atom} in calls(~S|String.to_atom(x)|)
    assert {:erlang, :binary_to_atom} in calls(~S|:erlang.binary_to_atom(x, :utf8)|)
  end
end
