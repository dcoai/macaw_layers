defmodule Macaw.Layers.Var do
  @moduledoc """
  A variable (spec/02 §5): a term allowed wherever a value can appear, carrying only its
  name, a string. Its default is declared once by the document that uses it, so two
  fragments cannot disagree about it. A variable is a struct, so it is a leaf of every
  walk: it stands for a value rather than being one.

  - `bind/2,3` substitutes variables: a literal sets one, another variable renames it
    (§5.1);
  - `free/2` lists the variables still open in a stack, each with every path it stands at
    and the layer that set it (§5.2).

  Ported from visualize's `Visualize.Chart.Var`, `Use.bind/2` and `Stack.free_vars/1`.

      iex> Macaw.Layers.Var.new(:color)
      %Macaw.Layers.Var{name: "color"}
      iex> Macaw.Layers.Var.bind(%{fill: Macaw.Layers.Var.new(:color)}, %{color: "blue"})
      %{fill: "blue"}
  """

  alias Macaw.Layers.{Fragment, Names}
  alias Macaw.Layers.Fragment.{Cascade, Compose}

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{name: String.t()}

  @doc "The variable of a name, an atom read as its string."
  @spec new(atom() | String.t()) :: t()
  def new(name) when is_binary(name), do: %__MODULE__{name: name}

  def new(name) when is_atom(name) and name not in [nil, true, false],
    do: %__MODULE__{name: Atom.to_string(name)}

  # -- binding -----------------------------------------------------------------------------

  @doc """
  The fragment with its variables substituted (spec/02 §5.1): every `%Var{name: k}`
  becomes the value `bindings` gives `k` — a literal sets it, another variable renames it
  — read by either spelling, and a variable `bindings` does not name stays. A bound value
  is not searched again: binding is single level. Any other struct is a leaf.
  """
  @spec bind(term(), map()) :: term()
  def bind(fragment, bindings) when map_size(bindings) == 0, do: fragment

  def bind(%__MODULE__{name: name} = var, bindings) do
    case Names.fetch(bindings, name) do
      {:ok, value} -> value
      :error -> var
    end
  end

  def bind(%_{} = struct, _bindings), do: struct

  def bind(map, bindings) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, bind(v, bindings)} end)

  def bind(list, bindings) when is_list(list), do: Enum.map(list, &bind(&1, bindings))

  def bind(tuple, bindings) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> bind(bindings) |> List.to_tuple()

  def bind(leaf, _bindings), do: leaf

  @doc """
  `bind/2`, and a value of the type's own syntax (a text's holes) substituted by the type's
  `bind_holes/4` at the key it stands at (spec/02 §5.1).
  """
  @spec bind(module(), term(), map()) :: term()
  def bind(_type, fragment, bindings) when map_size(bindings) == 0, do: fragment

  def bind(type, fragment, bindings) do
    if Fragment.callback?(type, :bind_holes, 4),
      do: walk_bind(type, type.root(), fragment, bindings),
      else: bind(fragment, bindings)
  end

  defp walk_bind(_type, _kind, %__MODULE__{} = var, bindings), do: bind(var, bindings)
  defp walk_bind(_type, _kind, %_{} = struct, _bindings), do: struct

  defp walk_bind(type, kind, map, bindings) when is_map(map) do
    Map.new(map, fn {k, v} ->
      v = type.bind_holes(kind, k, v, bindings)
      {k, walk_bind(type, child(type, kind, k), v, bindings)}
    end)
  end

  defp walk_bind(type, kind, list, bindings) when is_list(list),
    do: Enum.map(list, &walk_bind(type, kind, &1, bindings))

  defp walk_bind(_type, _kind, other, bindings), do: bind(other, bindings)

  # The node kind a key's value is read as: its node, a name map's or a list's element.
  defp child(type, kind, k) do
    case kind && Compose.spec(type, kind, k) do
      %{node: node} when node != nil -> node
      %{element: element} when element != nil -> element
      _other -> nil
    end
  end

  # -- the variables still open ----------------------------------------------------------------

  @doc """
  One entry per variable still in the stack of `layers` (a fragment is a one-layer stack),
  ordered by name (spec/02 §5.2): `%{name, uses}`, each use `%{path, layer}`, ordered by
  path. The walk descends into every map and list but a struct, and through the type's
  `holes/3` into a value of its own syntax, whose variables stand at its key, each named
  once there.
  """
  @spec free(module(), map() | [Fragment.layer()]) :: [%{name: String.t(), uses: [map()]}]
  def free(type, fragment) when is_map(fragment), do: free(type, [fragment])

  def free(type, layers) when is_list(layers) do
    {stacked, provenance} = Cascade.fold(type, Fragment.named(layers))

    type
    |> variables(type.root(), stacked, [])
    |> Enum.uniq()
    |> Enum.group_by(fn {_path, name} -> name end, fn {path, _name} -> path end)
    |> Enum.map(fn {name, paths} ->
      %{
        name: name,
        uses: paths |> Enum.sort() |> Enum.map(&%{path: &1, layer: layer_of(provenance, &1)})
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp variables(_type, _kind, %__MODULE__{name: name}, path), do: [{path, name}]
  defp variables(_type, _kind, %_{}, _path), do: []

  defp variables(type, kind, map, path) when is_map(map) do
    Enum.flat_map(map, fn {k, v} ->
      holes(type, kind, k, v, path ++ [k]) ++
        variables(type, child(type, kind, k), v, path ++ [k])
    end)
  end

  defp variables(type, kind, list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> variables(type, kind, v, path ++ [i]) end)
  end

  defp variables(_type, _kind, _leaf, _path), do: []

  defp holes(type, kind, k, v, path) do
    if Fragment.callback?(type, :holes, 3),
      do: for(%__MODULE__{name: name} <- type.holes(kind, k, v), do: {path, name}),
      else: []
  end

  # The layer of the leaf a variable stands in: its own path, else the enclosing leaf's.
  defp layer_of(provenance, path) do
    case {Map.fetch(provenance, path), path} do
      {{:ok, {layer, _overrode}}, _path} -> layer
      {:error, []} -> nil
      {:error, path} -> layer_of(provenance, Enum.drop(path, -1))
    end
  end
end
