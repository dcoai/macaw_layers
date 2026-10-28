defmodule Macaw.Layers.VocabularyTest do
  # "Makes no atom" is checked on the input's own names, never the node's atom count
  # (macaw_layers#1).
  use ExUnit.Case, async: true

  alias Macaw.Layers.Test.Atoms
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

  @tag verifies: "vocabulary-no-atoms"
  test "reading fresh strings makes no atom, and read/2 returns each as it was" do
    strings = for _ <- 1..2_000, do: Atoms.fresh()

    for s <- strings do
      assert Vocabulary.fetch(@anchors, s) == :error
      assert Vocabulary.fetch([:title, :caption], s) == :error
      assert Vocabulary.read(@anchors, s) == s
    end

    assert Atoms.made(strings) == []
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

  # A read of the node's atom count, as a call in code: every process on the node moves
  # it, so it measures no one test, and no test can hold the atom table to itself
  # (macaw_layers#1). A test checks its input's own names (Macaw.Layers.Test.Atoms).
  defp counts(source) do
    {_, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [:erlang, :system_info]}, _, [:atom_count]} = node, acc ->
          {node, [node | acc]}

        {{:., _, [:erlang, :memory]}, _, [kind]} = node, acc when kind in [:atom, :atom_used] ->
          {node, [node | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  @tag verifies: "vocabulary-no-atoms"
  test "no test reads the node's atom count" do
    sources = Path.wildcard("test/**/*.{ex,exs}")
    assert sources != []

    for path <- sources do
      assert counts(File.read!(path)) == [], "#{path} reads the node's atom count"
    end

    # The walk sees a read when there is one, and not one in a comment.
    assert [_] = counts(~S|before = :erlang.system_info(:atom_count)|)
    assert [_] = counts(~S|:erlang.memory(:atom_used)|)
    assert [] = counts("# :erlang.system_info(:atom_count)\n:ok")
  end
end
