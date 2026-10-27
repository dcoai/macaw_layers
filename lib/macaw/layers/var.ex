defmodule Macaw.Layers.Var do
  @moduledoc """
  A variable (spec/02 §5): a term allowed wherever a value can appear, carrying only its
  name, a string. Its default is declared once by the document that uses it, so two
  fragments cannot disagree about it. A variable is a struct, so it is a leaf of every
  walk: it stands for a value rather than being one.

      iex> Macaw.Layers.Var.new(:color)
      %Macaw.Layers.Var{name: "color"}
  """

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{name: String.t()}

  @doc "The variable of a name, an atom read as its string."
  @spec new(atom() | String.t()) :: t()
  def new(name) when is_binary(name), do: %__MODULE__{name: name}

  def new(name) when is_atom(name) and name not in [nil, true, false],
    do: %__MODULE__{name: Atom.to_string(name)}
end
