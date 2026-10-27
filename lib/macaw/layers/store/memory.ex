defmodule Macaw.Layers.Store.Memory do
  @moduledoc """
  The default store, held in memory (spec/03 §1.2): an `Agent` the host starts under its
  own supervisor, its context the agent.

      children = [{Macaw.Layers.Store.Memory, types: [MyApp.Layout], name: MyApp.Library}]
      Macaw.Layers.Store.put({Macaw.Layers.Store.Memory, MyApp.Library}, entry)

  Ids are issued from one sequence per kind that never repeats, a deleted id never
  reissued, so a stale id cannot resolve to something new and ids sort by creation. Its
  import is `Macaw.Layers.Store.relocate/3`, applied to a copy of its state and swapped in
  whole, so a failed import leaves nothing behind.
  """

  use Agent

  alias Macaw.Layers.Store

  @behaviour Store

  @doc """
  The store, started: `types:` the fragment types it holds (required; default closed, a
  type not listed is not storable, and two declaring one kind raise `ArgumentError`),
  `check:` the host's check over each imported entry, `name:` as `Agent` takes it.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts) do
    types = opts |> Keyword.fetch!(:types) |> Store.check_types!()
    state = %{types: types, check: Keyword.get(opts, :check), entries: %{}, issued: %{}}
    Agent.start_link(fn -> state end, Keyword.take(opts, [:name]))
  end

  @impl Store
  def types(agent), do: Agent.get(agent, & &1.types)

  @impl Store
  def list(agent) do
    summaries =
      Agent.get(agent, fn state ->
        for {id, entry} <- state.entries do
          {_type, kind} = Store.kind(state.types, entry.fragment)
          %{id: id, name: entry.name, kind: kind}
        end
      end)

    {:ok, Enum.sort_by(summaries, & &1.id)}
  end

  @impl Store
  def get(id, agent) do
    case Agent.get(agent, &Map.fetch(&1.entries, id)) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  @impl Store
  def put(entry, agent) do
    Agent.get_and_update(agent, fn state ->
      case write(entry, state) do
        {:ok, id, state} -> {{:ok, id}, state}
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end

  @impl Store
  def delete(id, agent), do: Agent.update(agent, &%{&1 | entries: Map.delete(&1.entries, id)})

  @impl Store
  def import(bundle, agent) do
    check = Agent.get(agent, & &1.check)

    Store.relocate({__MODULE__, agent}, bundle,
      check: check,
      transaction: fn run ->
        Agent.get_and_update(agent, fn state ->
          case run.(state, &write/2) do
            {:ok, imported, copy} -> {{:ok, imported}, copy}
            {:error, faults} -> {{:error, faults}, state}
          end
        end)
      end
    )
  end

  # One entry written to the state: a new id issued from its kind's sequence, or a held one
  # replaced. Its kind is the fragment's, so a held id of another kind is refused.
  defp write(%{id: id, name: name, fragment: fragment}, state)
       when is_binary(name) and is_map(fragment) do
    case {Store.kind(state.types, fragment), id} do
      {nil, _id} ->
        {:error, :no_kind}

      {{_type, kind}, nil} ->
        n = Map.get(state.issued, kind, 0) + 1
        id = {kind, n}
        entry = %{id: id, name: name, fragment: fragment}

        {:ok, id,
         %{
           state
           | entries: Map.put(state.entries, id, entry),
             issued: Map.put(state.issued, kind, n)
         }}

      {{_type, kind}, {kind, _n} = id} when is_map_key(state.entries, id) ->
        {:ok, id,
         %{state | entries: Map.put(state.entries, id, %{id: id, name: name, fragment: fragment})}}

      {{_type, kind}, {kind, _n}} ->
        {:error, :not_found}

      {{_type, kind}, {other, _n}} ->
        {:error, {:kind, other, kind}}
    end
  end
end
