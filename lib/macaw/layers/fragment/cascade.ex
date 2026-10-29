defmodule Macaw.Layers.Fragment.Cascade do
  @moduledoc false
  # The cascade of one fragment over another (spec/02 §3.2) and the provenance of a stack
  # (§6.3), which are one walk with two results. For every key the higher layer wins:
  # `:override` keys recurse into a node both layers give as a map; `:union` keys take the
  # higher layer's entry whole; `:deep` keys cascade a name both declare as a node;
  # `:concat` keys read both lists as one sequence, each identity keeping its first
  # position and its last value; `{:type, name}` is the type's merge. Nothing can fail.
  #
  # `node/5` returns the merged node and the leaf paths the higher layer contributed to it.
  # `cascade/3` drops the second; `explain/2` folds the layers and keeps it, so what
  # provenance reports and what the cascade produces cannot drift.
  #
  # Ported from visualize's `Visualize.Chart.Stack`.

  alias Macaw.Layers.Callback
  alias Macaw.Layers.Fragment.Compose

  @spec cascade(module(), map(), map()) :: map()
  def cascade(type, a, b), do: type |> node(type.root(), a, b, []) |> elem(0)

  @spec explain(module(), [{term(), map()}]) :: [map()]
  def explain(type, layers) do
    {stacked, provenance} = fold(type, layers)

    type
    |> leaves(%{node: type.root(), element: nil, merge: :override}, stacked, [])
    |> Enum.sort()
    |> Enum.map(fn path ->
      {layer, overrode} = origin(provenance, path)
      %{path: path, value: at(stacked, path), layer: layer, overrode: overrode}
    end)
  end

  # A leaf's `{layer, overrode}`: its own, else that of the nearest path above it, the
  # value a layer set whole and the type normalized into parts (spec/02 §3.3).
  defp origin(provenance, []), do: Map.fetch!(provenance, [])

  defp origin(provenance, path) do
    case Map.fetch(provenance, path) do
      {:ok, origin} -> origin
      :error -> origin(provenance, Enum.drop(path, -1))
    end
  end

  @doc false
  # The stacked result and, for each leaf path, `{layer, overrode}`.
  @spec fold(module(), [{term(), map()}]) :: {map(), map()}
  def fold(type, layers) do
    Enum.reduce(layers, {%{}, %{}}, fn {name, fragment}, {acc, provenance} ->
      {merged, set} = node(type, type.root(), acc, fragment, [])
      {merged, Enum.reduce(set, provenance, &record(&1, name, &2))}
    end)
  end

  # The layer takes the path; the layer that held it before becomes the last of the
  # layers it overrode, so the list reads lowest first.
  defp record(path, name, provenance) do
    Map.update(provenance, path, {name, []}, fn {previous, overrode} ->
      {name, overrode ++ [previous]}
    end)
  end

  # -- the walk ----------------------------------------------------------------------------

  defp node(type, kind, a, b, path) do
    a = Compose.under(type, kind, a, b)

    (Map.keys(a) ++ Map.keys(b))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn k, {acc, set} ->
      case {Map.fetch(a, k), Map.fetch(b, k)} do
        {{:ok, va}, {:ok, vb}} ->
          {v, s} = key(type, kind, k, va, vb, path ++ [k])
          {Map.put(acc, k, v), set ++ s}

        {{:ok, va}, :error} ->
          {Map.put(acc, k, va), set}

        {:error, {:ok, vb}} ->
          {Map.put(acc, k, vb), set ++ leaves(type, Compose.spec(type, kind, k), vb, path ++ [k])}
      end
    end)
  end

  defp key(type, kind, k, va, vb, path) do
    {va, vb} = Compose.normalize(type, kind, k, va, vb)

    case Compose.spec(type, kind, k) do
      nil -> {vb, [path]}
      spec -> rule(type, spec, va, vb, path)
    end
  end

  defp rule(type, %{merge: {:type, name}} = spec, va, vb, path),
    do: {type.merge(name, va, vb), leaves(type, spec, vb, path)}

  defp rule(type, %{merge: :concat, element: element} = spec, va, vb, path)
       when is_list(va) and is_list(vb),
       do: concat(type, element, spec, va, vb, path)

  # The higher layer's entry replaces the lower's whole: derivation within an entry is the
  # type's business, never the cascade's.
  defp rule(type, %{merge: :union} = spec, va, vb, path) do
    if node_map?(va) and node_map?(vb),
      do: union(type, spec, va, vb, path),
      else: {vb, leaves(type, %{spec | merge: :override}, vb, path)}
  end

  defp rule(type, %{merge: :deep, element: element} = spec, va, vb, path) do
    if node_map?(va) and node_map?(vb) and element != nil,
      do: deep(type, element, va, vb, path),
      else: {vb, leaves(type, %{spec | merge: :override}, vb, path)}
  end

  defp rule(type, %{node: node} = spec, va, vb, path) do
    if node != nil and node_map?(va) and node_map?(vb),
      do: node(type, node, va, vb, path),
      else: {vb, leaves(type, spec, vb, path)}
  end

  defp deep(type, kind, va, vb, path) do
    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, set} ->
      entry = %{merge: :override, node: kind, element: nil}

      case {Map.fetch(va, name), Map.fetch(vb, name)} do
        {{:ok, x}, {:ok, y}} ->
          {v, s} =
            if node_map?(x) and node_map?(y),
              do: node(type, kind, x, y, path ++ [name]),
              else: {y, leaves(type, entry, y, path ++ [name])}

          {Map.put(acc, name, v), set ++ s}

        {{:ok, x}, :error} ->
          {Map.put(acc, name, x), set}

        {:error, {:ok, y}} ->
          {Map.put(acc, name, y), set ++ leaves(type, entry, y, path ++ [name])}
      end
    end)
  end

  defp union(type, %{element: element}, va, vb, path) do
    entry = %{merge: :override, node: element, element: nil}

    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, set} ->
      case Map.fetch(vb, name) do
        {:ok, v} -> {Map.put(acc, name, v), set ++ leaves(type, entry, v, path ++ [name])}
        :error -> {Map.put(acc, name, Map.fetch!(va, name)), set}
      end
    end)
  end

  # The lower's elements and the higher's read as one sequence, each identity keeping its
  # first position and its last value: the cascade is then associative over `:concat`
  # keys, and a duplicate identity in either list collapses.
  defp concat(type, kind, spec, lower, higher, path) do
    merged =
      Enum.reduce(tag(lower, :lower) ++ tag(higher, :higher), [], fn {element, _} = e, acc ->
        case identity(type, kind, element) do
          nil -> acc ++ [e]
          id -> place(type, kind, acc, id, e)
        end
      end)

    entry = %{merge: :override, node: spec.element, element: nil}

    set =
      for {{element, :higher}, index} <- Enum.with_index(merged),
          leaf <- leaves(type, entry, element, path ++ [index]),
          do: leaf

    {Enum.map(merged, &elem(&1, 0)), set}
  end

  defp tag(elements, origin), do: Enum.map(elements, &{&1, origin})

  defp place(type, kind, acc, id, element) do
    case Enum.find_index(acc, fn {e, _} -> identity(type, kind, e) == id end) do
      nil -> acc ++ [element]
      index -> List.replace_at(acc, index, element)
    end
  end

  defp identity(type, kind, element) do
    if kind != nil and node_map?(element) and Callback.exported?(type, :identity, 2),
      do: type.identity(kind, element)
  end

  # -- leaves ------------------------------------------------------------------------------

  # Every path the walk does not descend into: it descends through a node, a name map's
  # entries and a list's elements, and stops at every other value (spec/02 §6.3).
  @doc false
  @spec leaves(module(), map() | nil, term(), list()) :: [list()]
  def leaves(type, %{merge: merge} = spec, value, path) when merge in [:union, :deep] do
    if node_map?(value) do
      entry = %{merge: :override, node: spec.element, element: nil}
      Enum.flat_map(value, fn {k, e} -> leaves(type, entry, e, path ++ [k]) end)
    else
      [path]
    end
  end

  def leaves(type, %{merge: :concat} = spec, value, path) when is_list(value) do
    entry = %{merge: :override, node: spec.element, element: nil}

    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {e, i} -> leaves(type, entry, e, path ++ [i]) end)
  end

  def leaves(type, %{merge: :override, node: kind}, value, path) when kind != nil do
    if node_map?(value) do
      Enum.flat_map(value, fn {k, e} ->
        leaves(type, Compose.spec(type, kind, k), e, path ++ [k])
      end)
    else
      [path]
    end
  end

  def leaves(_type, _spec, _value, path), do: [path]

  defp at(value, []), do: value
  defp at(value, [k | rest]) when is_list(value), do: at(Enum.at(value, k), rest)
  defp at(value, [k | rest]) when is_map(value), do: at(Map.fetch!(value, k), rest)

  defp node_map?(v), do: is_map(v) and not is_struct(v)
end
