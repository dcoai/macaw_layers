defmodule Macaw.Layers.Fragment.Compose do
  @moduledoc false
  # Composition of two fragments by the type's merge rules (spec/02 §3.1): `:concat` lists
  # append, `:union` name maps unite with a conflict at a name declared differently by
  # both, `:deep` name maps unite and merge a name both declare as a node, `:override` takes
  # the later value, recursing into a node both give as a map, and `{:type, name}` is the
  # type's own merge. A struct is a leaf (spec/02 §1): at a mergeable key it is one value,
  # equal in both taken once, different a conflict at the key's own path.
  #
  # Ported from visualize's `Visualize.Chart.Compose`.

  alias Macaw.Layers.Fault

  @spec merge(module(), map(), map()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def merge(type, a, b) do
    case node(type, type.root(), a, b, []) do
      {merged, []} -> {:ok, merged}
      {_merged, faults} -> {:error, Enum.sort_by(faults, &elem(&1, 0))}
    end
  end

  defp node(type, kind, a, b, path) do
    (Map.keys(a) ++ Map.keys(b))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn k, {acc, faults} ->
      case {Map.fetch(a, k), Map.fetch(b, k)} do
        {{:ok, va}, {:ok, vb}} ->
          {v, f} = key(type, kind, k, va, vb, path ++ [k])
          {Map.put(acc, k, v), faults ++ f}

        {{:ok, va}, :error} ->
          {Map.put(acc, k, va), faults}

        {:error, {:ok, vb}} ->
          {Map.put(acc, k, vb), faults}
      end
    end)
  end

  defp key(type, kind, k, va, vb, path) do
    case spec(type, kind, k) do
      nil -> {vb, []}
      spec -> rule(type, spec, va, vb, path)
    end
  end

  @doc false
  # A key's spec; at the root a key the type does not know but wraps (`style:`) is a node
  # of the kind it names, so two wrapped fragments combine as two such nodes would.
  @spec spec(module(), atom(), term()) :: map() | nil
  def spec(type, kind, k) do
    case type.key(kind, k) do
      nil ->
        if kind == type.root() do
          case type.wrapper(k) do
            nil -> nil
            inner -> %{merge: :override, node: inner, element: nil}
          end
        end

      spec ->
        Map.merge(%{node: nil, element: nil}, spec)
    end
  end

  defp rule(type, %{merge: {:type, name}}, va, vb, _path), do: {type.merge(name, va, vb), []}

  defp rule(_type, %{merge: :concat}, va, vb, _path) when is_list(va) and is_list(vb),
    do: {va ++ vb, []}

  defp rule(_type, %{merge: :union}, va, vb, path) do
    if node_map?(va) and node_map?(vb), do: union(va, vb, path), else: whole(va, vb, path)
  end

  defp rule(type, %{merge: :deep, element: element}, va, vb, path) do
    if node_map?(va) and node_map?(vb) and element != nil,
      do: deep(type, element, va, vb, path),
      else: whole(va, vb, path)
  end

  defp rule(type, %{node: node}, va, vb, path) when node != nil do
    if node_map?(va) and node_map?(vb), do: node(type, node, va, vb, path), else: {vb, []}
  end

  defp rule(_type, _spec, _va, vb, _path), do: {vb, []}

  defp deep(type, kind, va, vb, path) do
    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, faults} ->
      case {Map.fetch(va, name), Map.fetch(vb, name)} do
        {{:ok, x}, {:ok, y}} ->
          {v, f} =
            if node_map?(x) and node_map?(y),
              do: node(type, kind, x, y, path ++ [name]),
              else: whole(x, y, path ++ [name])

          {Map.put(acc, name, v), faults ++ f}

        {{:ok, x}, :error} ->
          {Map.put(acc, name, x), faults}

        {:error, {:ok, y}} ->
          {Map.put(acc, name, y), faults}
      end
    end)
  end

  defp union(va, vb, path) do
    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, faults} ->
      case {Map.fetch(va, name), Map.fetch(vb, name)} do
        {{:ok, x}, {:ok, x}} -> {Map.put(acc, name, x), faults}
        {{:ok, _}, {:ok, y}} -> {Map.put(acc, name, y), faults ++ [{path ++ [name], :conflict}]}
        {{:ok, x}, :error} -> {Map.put(acc, name, x), faults}
        {:error, {:ok, y}} -> {Map.put(acc, name, y), faults}
      end
    end)
  end

  defp whole(v, v, _path), do: {v, []}
  defp whole(_va, vb, path), do: {vb, [{path, :conflict}]}

  defp node_map?(v), do: is_map(v) and not is_struct(v)
end
