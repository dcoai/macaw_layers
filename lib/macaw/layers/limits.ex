defmodule Macaw.Layers.Limits do
  @moduledoc """
  Sanity limits on a document read from elsewhere (spec/01 §5).

  | Limit | Default | Bounds |
  |---|---|---|
  | `bytes` | `8_000_000` | the encoded document's size |
  | `depth` | `64` | how deeply objects and arrays nest; the document itself is depth 1 |
  | `items` | `100_000` | the entries any one object or array holds |

  They bound what reading a document can be made to cost. **A host may tighten every
  limit,** never loosen one: a host loading untrusted input knows its inputs and lowers the
  numbers at its layer, and a limit it does not name keeps its default.

  A fault is `{path, {:limit, name, max, given}}`, worded by `Macaw.Layers.Fault.format/2`.

  The walk over a decoded term is the generic part of visualize's
  `Visualize.Chart.Limits.structure/2`.
  """

  alias Macaw.Layers.Fault

  @defaults %{bytes: 8_000_000, depth: 64, items: 100_000}

  @typedoc "A limit's name."
  @type name :: :bytes | :depth | :items

  @typedoc "The limits a reader applies, one positive integer per name."
  @type t :: %{name() => pos_integer()}

  @doc "The system's sanity values."
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc """
  The limits a reader applies: `given` over `defaults/0`.

  Raises `ArgumentError` for a name that is not a limit, a value that is not a positive
  integer, or one above the default: a host can't loosen a sanity limit by mistake.

      iex> Macaw.Layers.Limits.new(items: 10).items
      10
  """
  @spec new(keyword() | map()) :: t()
  def new(given) when is_list(given) or is_map(given) do
    Enum.reduce(given, @defaults, fn
      {name, max}, acc when is_map_key(@defaults, name) and is_integer(max) and max > 0 ->
        if max > @defaults[name] do
          raise ArgumentError,
                "limit #{name} may be tightened, not loosened: " <>
                  "#{max} is above the default #{@defaults[name]}"
        end

        Map.put(acc, name, max)

      {name, max}, _acc when is_map_key(@defaults, name) ->
        raise ArgumentError, "limit #{name} must be a positive integer, got: #{inspect(max)}"

      {name, _max}, _acc ->
        raise ArgumentError,
              "not a limit: #{inspect(name)}; the limits are #{inspect(Map.keys(@defaults))}"
    end)
  end

  @doc """
  Every `depth` and `items` fault of a decoded term, ordered by path.

  The term itself is depth 1. A struct is a leaf. Past the depth limit a branch is reported
  once, at the first map or list beyond it, and not walked further. A map or list over the
  items limit is reported at its own path, with the number of entries it holds.
  """
  @spec structure(term(), t()) :: [Fault.t()]
  def structure(term, limits), do: term |> walk([], 1, limits) |> Fault.sort()

  defp walk(%_{}, _path, _depth, _limits), do: []

  defp walk(term, path, depth, %{depth: max})
       when (is_map(term) or is_list(term)) and depth > max,
       do: [{path, {:limit, :depth, max, depth}}]

  defp walk(term, path, depth, limits) when is_map(term) do
    items(map_size(term), path, limits) ++
      Enum.flat_map(term, fn {k, v} -> walk(v, path ++ [k], depth + 1, limits) end)
  end

  defp walk(term, path, depth, limits) when is_list(term) do
    items(length(term), path, limits) ++
      (term
       |> Enum.with_index()
       |> Enum.flat_map(fn {v, i} -> walk(v, path ++ [i], depth + 1, limits) end))
  end

  defp walk(_leaf, _path, _depth, _limits), do: []

  defp items(n, path, %{items: max}) when n > max, do: [{path, {:limit, :items, max, n}}]
  defp items(_n, _path, _limits), do: []
end
