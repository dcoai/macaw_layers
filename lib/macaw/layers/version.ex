defmodule Macaw.Layers.Version do
  @moduledoc """
  One version line per document type, and stepwise migration (spec/01 §4).

  A document type implements this behavior: its current version, and one pure migration
  step per version. A document carries its version as the stamp `"$version"`, a string key
  at the top of its map, in the map form and the JSON form alike. Two types' lines are
  independent: a new step for one moves no other.

      defmodule MyApp.Layout do
        @behaviour Macaw.Layers.Version

        @impl true
        def current, do: 2

        # 1 -> 2: `cols` became `columns`.
        @impl true
        def step(%{"cols" => cols} = doc, 1),
          do: {:ok, doc |> Map.delete("cols") |> Map.put("columns", cols)}

        def step(doc, 1), do: {:ok, doc}
      end

      Macaw.Layers.Version.migrate(%{"$version" => 1, "cols" => 3}, MyApp.Layout)
      #=> {:ok, %{"$version" => 2, "columns" => 3}}

  The generic part of visualize's `Visualize.Chart.Migration` (`current/0`, `readable/1`,
  `migrate/1`), with the line per type rather than one shared by every type.
  """

  alias Macaw.Layers.Fault

  @stamp "$version"

  @doc "The type's current version: a positive integer, starting at 1."
  @callback current() :: pos_integer()

  @doc """
  The document at `from` migrated to `from + 1`, purely: no I/O, no clock, no process.
  The kernel writes the new stamp; a step need not.
  """
  @callback step(document :: map(), from :: pos_integer()) ::
              {:ok, map()} | {:error, [Fault.t(), ...]}

  @doc "The stamp's key, `\"$version\"`."
  @spec stamp() :: String.t()
  def stamp, do: @stamp

  @doc """
  The document's version, read before anything else of it: `{:ok, version}`, the current
  one when the document has no stamp, or the fault that refuses it.

  A stamp above the type's current version is `{[], {:newer_schema, needs, this}}`, and a
  stamp that is not a positive integer is `{["$version"], {:type, :pos_integer}}`.
  """
  @spec check(map(), module()) :: {:ok, pos_integer()} | {:error, [Fault.t(), ...]}
  def check(document, type) when is_map(document) and is_atom(type) do
    current = type.current()

    case Map.fetch(document, @stamp) do
      :error -> {:ok, current}
      {:ok, v} when is_integer(v) and v > current -> {:error, [{[], {:newer_schema, v, current}}]}
      {:ok, v} when is_integer(v) and v >= 1 -> {:ok, v}
      {:ok, _other} -> {:error, [{[@stamp], {:type, :pos_integer}}]}
    end
  end

  @doc """
  The document at the type's current version, carrying the current stamp.

  A document with no stamp reads as current. An older one is migrated one step at a time,
  each `c:step/2` in turn; a step's faults stop the migration and are returned. A newer or
  malformed stamp is refused by `check/2` before any step runs.
  """
  @spec migrate(map(), module()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def migrate(document, type) when is_map(document) and is_atom(type) do
    with {:ok, from} <- check(document, type) do
      steps(Map.put(document, @stamp, from), from, type.current(), type)
    end
  end

  defp steps(document, current, current, _type), do: {:ok, document}

  defp steps(document, from, current, type) do
    case type.step(document, from) do
      {:ok, next} when is_map(next) ->
        steps(Map.put(next, @stamp, from + 1), from + 1, current, type)

      {:error, [_ | _] = faults} ->
        {:error, Fault.sort(faults)}
    end
  end
end
