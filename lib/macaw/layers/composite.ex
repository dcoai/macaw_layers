defmodule Macaw.Layers.Composite do
  @moduledoc """
  Composites (spec/02 §8): a fragment whose content is a list of use sites and its own
  variable declarations, stored as structure and flattened at deployment.

      %{composite: %{uses: [%Use{…}, …], vars: %{"color_1" => %{default: …}}}}

  `flatten/3` resolves every site recursively — `ref → local → mask → bind` — through a
  fetch, places each by its kind through the type's `place/3`, and stacks the placed
  layers: a whole document with no ids and no uses. Composites nest; one that reaches
  itself is refused at the site that closed the loop. A reference the store no longer
  holds shows through and is reported.

  Ported from visualize's `Visualize.Chart.Composite` and `Refs`, the placement and the
  inlining of ids made the type's.
  """

  alias Macaw.Layers.{Callback, Fragment, Use}

  @typedoc """
  What `flatten/3` reports: every reference that showed through, `{id, at}`, `at` the use
  id of the site that named it or the path of a reference inside the document, and every
  name-keyed site with no key, by its use id.
  """
  @type report :: %{missing: [{Fragment.id(), term()}], keyless: [{:use, pos_integer()}]}

  @doc "Whether a fragment is one key, `composite`, holding uses."
  @spec composite?(term()) :: boolean()
  def composite?(%{composite: %{uses: uses}} = fragment)
      when map_size(fragment) == 1 and is_list(uses),
      do: true

  def composite?(_fragment), do: false

  @doc """
  A composite flattened through `fetch` (spec/02 §8.1): `{:ok, document, report}`, or
  `{:error, {:cycle, chain}}`, `chain` the ids from the outer composite to the repeated
  one. A fragment that is not a composite flattens to itself. Once the sites are placed,
  the ids left at reference sites inside the document are resolved by the type's
  `inline/2`, where it has one.
  """
  @spec flatten(module(), map(), (Fragment.id() -> {:ok, map()} | :error)) ::
          {:ok, map(), report()} | {:error, {:cycle, [Fragment.id()]}}
  def flatten(type, fragment, fetch) do
    with {:ok, flat, report} <- flatten(type, fragment, fetch, []) do
      if Callback.exported?(type, :inline, 2) do
        {inlined, unresolved} = type.inline(flat, fetch)
        {:ok, inlined, %{report | missing: report.missing ++ unresolved}}
      else
        {:ok, flat, report}
      end
    end
  end

  defp flatten(type, %{composite: %{uses: uses} = composite} = fragment, fetch, trail)
       when map_size(fragment) == 1 and is_list(uses) do
    base = vars_layer(type, Map.get(composite, :vars, %{}))

    uses
    |> Enum.reduce_while({:ok, [], []}, fn use, {:ok, resolved, missing} ->
      case layer(type, use, fetch, trail) do
        {:ok, contribution, more} ->
          {:cont, {:ok, [{use, contribution} | resolved], missing ++ more}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved, missing} ->
        {layers, keyless} = resolved |> Enum.reverse() |> placed(type)
        {:ok, Fragment.stack(type, base ++ layers), %{missing: missing, keyless: keyless}}

      {:error, _} = error ->
        error
    end
  end

  defp flatten(_type, fragment, _fetch, _trail) when is_map(fragment),
    do: {:ok, fragment, %{missing: [], keyless: []}}

  # The composite's own vars are the lowest layer, under the type's own `vars` key, when
  # the type declares one and the composite has any.
  defp vars_layer(type, vars) when is_map(vars) and map_size(vars) > 0 do
    if type.key(type.root(), :vars) != nil, do: [%{vars: vars}], else: []
  end

  defp vars_layer(_type, _vars), do: []

  # One site as its contribution. A referenced body may itself be a composite, flattened
  # first through the trail, so a chain that returns to an id is a cycle. An inline
  # composite flattens in place.
  defp layer(type, %Use{ref: nil, local: local} = use, fetch, trail) do
    if composite?(local) do
      with {:ok, flat, %{missing: nested}} <- flatten(type, local, fetch, trail),
           do: {:ok, Use.over(type, %{use | local: %{}}, flat), nested}
    else
      {:ok, Use.over(type, use, %{}), []}
    end
  end

  defp layer(type, %Use{ref: ref} = use, fetch, trail) do
    if ref in trail do
      {:error, {:cycle, Enum.reverse([ref | trail])}}
    else
      case fetch.(ref) do
        :error ->
          {:ok, Use.over(type, use, %{}), [{ref, use.id}]}

        {:ok, body} ->
          with {:ok, flat, %{missing: nested}} <- flatten(type, body, fetch, [ref | trail]),
               do: {:ok, Use.over(type, use, flat), nested}
      end
    end
  end

  # A composer of one name-keyed kind — every site that kind, wrapped, and every one
  # keyless — stacks its bodies as bodies: its result is a fragment of that kind for the
  # site that holds it to place. Anything else places every site by its kind.
  defp placed(resolved, type) do
    placements = Enum.map(resolved, fn {use, c} -> {use, c, place(type, c, use.key)} end)

    if composer?(type, placements) do
      {Enum.map(placements, &elem(&1, 1)), []}
    else
      Enum.reduce(placements, {[], []}, fn
        {_use, _c, {:ok, layer}}, {layers, keyless} -> {layers ++ [layer], keyless}
        {use, _c, :keyless}, {layers, keyless} -> {layers, keyless ++ [use.id]}
      end)
    end
  end

  defp composer?(type, placements) do
    kinds = placements |> Enum.map(fn {_use, c, _p} -> wrapped_kind(type, c) end) |> Enum.uniq()
    match?([kind] when kind != nil, kinds) and Enum.all?(placements, &(elem(&1, 2) == :keyless))
  end

  defp wrapped_kind(type, contribution) do
    case Map.to_list(contribution) do
      [{key, body}] when is_map(body) -> type.wrapper(key)
      _other -> nil
    end
  end

  @doc """
  One site's contribution as the layer that declares it where a whole document keeps its
  kind (spec/02 §8.2), through the type's `place/3`, or `:keyless`. A contribution of no
  kind (a whole document, an empty site) is its own layer.
  """
  @spec place(module(), map(), String.t() | nil) :: {:ok, map()} | :keyless
  def place(type, contribution, key) do
    case Fragment.kind(type, contribution) do
      nil -> {:ok, contribution}
      kind -> type.place(kind, contribution, key)
    end
  end

  @doc """
  A whole document as a composite of inline sites, one kind each, through the type's
  `decompose/1` (spec/02 §8.2): flattening it is the document again.
  """
  @spec decompose(module(), map()) :: map()
  def decompose(type, document) when is_map(document),
    do: %{composite: %{uses: type.decompose(document)}}
end
