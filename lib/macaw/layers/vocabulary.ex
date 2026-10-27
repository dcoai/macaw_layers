defmodule Macaw.Layers.Vocabulary do
  @moduledoc """
  A closed vocabulary read from a string (spec/01 §2).

  A table maps each member's spelling to the member, built from the vocabulary's own list.
  A reader looks a document's string up in it and never makes an atom of one. Nor does it
  ask the node whether such an atom exists (`String.to_existing_atom/1`), which would let a
  document probe the atom table and make a read depend on which modules are loaded. A
  string the table lacks is the caller's to refuse at its path.

  Build a table once, in a module attribute, wherever the list is known at compile time:

      @anchors Vocabulary.table([:title, :subtitle, :caption])
      Vocabulary.fetch(@anchors, "title")   #=> {:ok, :title}
      Vocabulary.fetch(@anchors, "footer")  #=> :error

  Ported from visualize's `Visualize.Vocabulary`.
  """

  @typedoc "A vocabulary's members by their spelling."
  @type table :: %{String.t() => atom()}

  @doc "The table of a list of atoms."
  @spec table([atom()]) :: table()
  def table(members) when is_list(members), do: Map.new(members, &{Atom.to_string(&1), &1})

  @doc """
  The member a string spells, from a table or, for a list known only at run time and a few
  members long, from the list itself. Anything that is not a string is `:error`.
  """
  @spec fetch(table() | [atom()], term()) :: {:ok, atom()} | :error
  def fetch(table, string) when is_map(table) and is_binary(string), do: Map.fetch(table, string)

  def fetch(members, string) when is_list(members) and is_binary(string) do
    case Enum.find(members, &(Atom.to_string(&1) == string)) do
      nil -> :error
      member -> {:ok, member}
    end
  end

  def fetch(_vocabulary, _other), do: :error

  @doc """
  The member a string spells, or the string itself: a value a validator then refuses by
  type at its path.
  """
  @spec read(table() | [atom()], String.t()) :: atom() | String.t()
  def read(vocabulary, string) when is_binary(string) do
    case fetch(vocabulary, string) do
      {:ok, member} -> member
      :error -> string
    end
  end
end
