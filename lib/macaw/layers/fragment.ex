defmodule Macaw.Layers.Fragment do
  @moduledoc """
  Fragments and stacking (spec/02): the fragment-type behavior, and the operations over
  fragments of a type.

  A **fragment** is a document of a type, or any part of one: a map with the type's keys,
  not necessarily all of them and not validated. A document type that stacks implements
  this behavior, declaring what visualize read from its chart schema: how each key
  combines (`c:key/2`), which elements a layer replaces in place (`c:identity/2`), the kinds
  its fragments can be (`c:kinds/0`, `c:wrapper/1`) and where each kind lands in a whole
  document (`c:place/3`). The machinery holds no type's vocabulary, so every type combines
  the same way:

  - `compose/3`, the union, reports a name two fragments declare differently (§3.1);
  - `stack/2`, the cascade, takes the higher layer's word (§3.2);
  - `explain/2` says which layer set every value of a stack (§6.3);
  - `kind/2`, `refs/2` and `relocate/3` read a fragment's kind and ids (§6.1, §6.2).

  **A struct is a leaf of every walk** (visualize D-92): a `%Macaw.Layers.Var{}` stands for
  a value rather than being one. Only `refs/2` and `relocate/3` read a struct's parts, a
  `%Macaw.Layers.Use{}`'s, by name.

  Ported from visualize's `Visualize.Chart.Compose`, `Stack` and `Fragment`.
  """

  alias Macaw.Layers.Fragment.{Cascade, Compose}
  alias Macaw.Layers.{Fault, Use}

  @typedoc "A node kind of a document type."
  @type kind :: atom()

  @typedoc "How a key combines (spec/02 §2)."
  @type rule :: :concat | :union | :deep | :override | {:type, atom()}

  @typedoc """
  A key's spec: its rule, the node kind of a node-valued key, and the node kind of a
  list's or a name map's elements.
  """
  @type spec :: %{merge: rule(), node: kind() | nil, element: kind() | nil}

  @typedoc "An id a store issued: `{kind, n}`."
  @type id :: {kind(), pos_integer()}

  @typedoc "A layer of a stack: a fragment, or a `{name, fragment}` pair."
  @type layer :: map() | {term(), map()}

  @doc "The node kind of a whole document of the type."
  @callback root() :: kind()

  @doc "How a key of a node of `kind` combines, or `nil` for a key the type does not know."
  @callback key(kind(), term()) :: spec() | nil

  @doc "The identity of an element of a `:concat` list of `kind` elements, or `nil`."
  @callback identity(kind(), map()) :: term()

  @doc "Every kind a fragment of the type can be, and so every kind an id can carry."
  @callback kinds() :: [kind()]

  @doc "The kind a singular wrapper key names (`style:` → `:style`), or `nil`."
  @callback wrapper(term()) :: kind() | nil

  @doc "Where a composite site of `kind` lands in a whole document (spec/02 §8.2)."
  @callback place(kind(), map(), String.t() | nil) :: {:ok, map()} | :keyless

  @doc "The variables a value of the type's own syntax holds (a text's holes)."
  @callback holes(kind(), term(), term()) :: [Macaw.Layers.Var.t()]

  @doc "That value with its holes substituted, written back in the type's syntax."
  @callback bind_holes(kind(), term(), term(), map()) :: term()

  @doc "The type's own merge of a key whose rule is `{:type, name}`."
  @callback merge(atom(), term(), term()) :: term()

  @doc "Every id left at a reference site of a flattened document resolved through `fetch`."
  @callback inline(map(), (id() -> {:ok, map()} | :error)) :: {map(), [{id(), list()}]}

  @doc "A whole document as inline sites, one kind each."
  @callback decompose(map()) :: [Use.t()]

  @optional_callbacks identity: 2, holes: 3, bind_holes: 4, merge: 3, inline: 2, decompose: 1

  # -- composition and the stack --------------------------------------------------------

  @doc """
  `b` over `a` by every key's rule (spec/02 §3.1): `{:ok, fragment}`, or `{:error, faults}`
  with every `:conflict` at its path, ordered by path.
  """
  @spec compose(module(), map(), map()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def compose(type, a, b) when is_map(a) and is_map(b), do: Compose.merge(type, a, b)

  @doc "The left fold of `compose/3`; `compose(type, [])` is `{:ok, %{}}`."
  @spec compose(module(), [map()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def compose(type, fragments) when is_list(fragments) do
    Enum.reduce_while(fragments, {:ok, %{}}, fn fragment, {:ok, acc} ->
      case compose(type, acc, fragment) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        {:error, faults} -> {:halt, {:error, faults}}
      end
    end)
  end

  @doc """
  The cascade of `higher` over `lower` (spec/02 §3.2): for every key the higher layer
  wins. It cannot fail, so it answers the fragment itself.
  """
  @spec stack(module(), map(), map()) :: map()
  def stack(type, lower, higher) when is_map(lower) and is_map(higher),
    do: Cascade.cascade(type, lower, higher)

  @doc """
  The left fold of `stack/3`, the later layer the higher: `stack(type, [])` is `%{}` and
  `stack(type, [a])` is `a`. A layer may be a `{name, fragment}` pair, whose name is
  ignored here and reported by `explain/2`.
  """
  @spec stack(module(), [layer()]) :: map()
  def stack(_type, []), do: %{}
  def stack(_type, [layer]), do: fragment(layer)

  def stack(type, [first | rest]),
    do: Enum.reduce(rest, fragment(first), &stack(type, &2, fragment(&1)))

  @doc """
  One entry per leaf path of `stack/2` of `layers` (spec/02 §6.3), ordered by path:
  `%{path, value, layer, overrode}`, `layer` the layer's name or its zero-based position.
  It recomputes the stack by the cascade's own walk, so it cannot drift from it.
  """
  @spec explain(module(), [layer()]) :: [map()]
  def explain(type, layers) when is_list(layers), do: Cascade.explain(type, named(layers))

  @doc false
  # The layers as `{name, fragment}` pairs, a bare fragment named by its position.
  @spec named([layer()]) :: [{term(), map()}]
  def named(layers) do
    layers
    |> Enum.with_index()
    |> Enum.map(fn
      {{name, fragment}, _i} when is_map(fragment) -> {name, fragment}
      {fragment, i} when is_map(fragment) -> {i, fragment}
    end)
  end

  defp fragment({_name, fragment}) when is_map(fragment), do: fragment
  defp fragment(fragment) when is_map(fragment), do: fragment

  # -- kinds -------------------------------------------------------------------------------

  @doc """
  The kind of a fragment, derived (spec/02 §6.1): walking down while exactly one key is
  set, the last kind reached. A singular wrapper is the kind it names, a name map or list
  holding one entry the entry's kind, a composite `:composite`. `nil` for a fragment that
  branches at the top, which is no kind of fragment, and for one that reaches no kind
  below the root.
  """
  @spec kind(module(), map()) :: kind() | nil
  def kind(type, fragment) when is_map(fragment) and not is_struct(fragment) do
    root = type.root()

    case Map.to_list(fragment) do
      [{:composite, %{uses: uses}}] when is_list(uses) ->
        :composite

      [{key, value}] ->
        case type.key(root, key) do
          nil -> type.wrapper(key)
          spec -> none(root, descend(type, root, spec, value))
        end

      _several ->
        nil
    end
  end

  defp none(root, root), do: nil
  defp none(_root, kind), do: kind

  defp walk(type, kind, node) when is_map(node) and not is_struct(node) do
    case Map.to_list(node) do
      [{key, value}] ->
        case type.key(kind, key) do
          nil -> kind
          spec -> descend(type, kind, spec, value)
        end

      _several ->
        kind
    end
  end

  defp walk(_type, kind, _value), do: kind

  # One node under the key: keep walking. A name map or a list with one member: walk into
  # it. Several members: the fragment is about that kind, however many.
  defp descend(type, _kind, %{node: node}, value) when node != nil, do: walk(type, node, value)

  defp descend(type, _kind, %{merge: merge, element: element}, value)
       when merge in [:union, :deep] and element != nil and is_map(value) and not is_struct(value) do
    case Map.values(value) do
      [only] -> walk(type, element, only)
      _several -> element
    end
  end

  defp descend(type, _kind, %{merge: :concat, element: element}, [only]) when element != nil,
    do: walk(type, element, only)

  defp descend(_type, _kind, %{merge: :concat, element: element}, value)
       when element != nil and is_list(value),
       do: element

  defp descend(_type, kind, _spec, _value), do: kind

  # -- ids ---------------------------------------------------------------------------------

  @doc """
  Every id a fragment refers to, once each, sorted (spec/02 §6.2): a `{kind, n}` of the
  type's `c:kinds/0` with `n` a positive integer, wherever it stands, a use site's `ref`,
  `origin`, `local` and `vars` included. Sorted, since the order a map is walked is the
  runtime's.
  """
  @spec refs(module(), term()) :: [id()]
  def refs(type, fragment) do
    kinds = MapSet.new(type.kinds())
    fragment |> collect(kinds, []) |> Enum.uniq() |> Enum.sort()
  end

  defp collect({kind, n} = id, kinds, acc) when is_atom(kind) and is_integer(n) and n > 0 do
    if MapSet.member?(kinds, kind), do: [id | acc], else: acc
  end

  defp collect(%Use{ref: ref, origin: origin, local: local, vars: vars}, kinds, acc),
    do: Enum.reduce([ref, origin, local, vars], acc, &collect(&1, kinds, &2))

  defp collect(%_{}, _kinds, acc), do: acc

  defp collect(map, kinds, acc) when is_map(map),
    do: Enum.reduce(map, acc, fn {_key, value}, acc -> collect(value, kinds, acc) end)

  defp collect(list, kinds, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect(&1, kinds, &2))

  defp collect(tuple, kinds, acc) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> collect(kinds, acc)

  defp collect(_leaf, _kinds, acc), do: acc

  @doc """
  The fragment with every id rewritten through `table`, `%{old => new}`, and the ids the
  table did not carry, sorted (spec/02 §6.2). A use site's ids are rewritten in place, the
  site still a `%Use{}`; an id not in the table is left, to resolve as a mask.
  """
  @spec relocate(module(), term(), %{id() => id()}) :: {term(), [id()]}
  def relocate(type, fragment, table) when is_map(table) do
    kinds = MapSet.new(type.kinds())
    {rewritten, missed} = rewrite(fragment, kinds, table, [])
    {rewritten, missed |> Enum.uniq() |> Enum.sort()}
  end

  defp rewrite({kind, n} = id, kinds, table, missed)
       when is_atom(kind) and is_integer(n) and n > 0 do
    cond do
      not MapSet.member?(kinds, kind) -> {id, missed}
      Map.has_key?(table, id) -> {Map.fetch!(table, id), missed}
      true -> {id, [id | missed]}
    end
  end

  defp rewrite(%Use{} = use, kinds, table, missed) do
    Enum.reduce([:ref, :origin, :local, :vars], {use, missed}, fn field, {use, missed} ->
      {value, missed} = rewrite(Map.fetch!(use, field), kinds, table, missed)
      {Map.put(use, field, value), missed}
    end)
  end

  defp rewrite(%_{} = struct, _kinds, _table, missed), do: {struct, missed}

  defp rewrite(map, kinds, table, missed) when is_map(map) do
    Enum.reduce(map, {%{}, missed}, fn {key, value}, {acc, missed} ->
      {value, missed} = rewrite(value, kinds, table, missed)
      {Map.put(acc, key, value), missed}
    end)
  end

  defp rewrite(list, kinds, table, missed) when is_list(list) do
    {rewritten, missed} =
      Enum.reduce(list, {[], missed}, fn value, {acc, missed} ->
        {value, missed} = rewrite(value, kinds, table, missed)
        {[value | acc], missed}
      end)

    {Enum.reverse(rewritten), missed}
  end

  defp rewrite(tuple, kinds, table, missed) when is_tuple(tuple) do
    {elements, missed} = rewrite(Tuple.to_list(tuple), kinds, table, missed)
    {List.to_tuple(elements), missed}
  end

  defp rewrite(leaf, _kinds, _table, missed), do: {leaf, missed}
end
