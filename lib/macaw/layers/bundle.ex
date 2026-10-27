defmodule Macaw.Layers.Bundle do
  @moduledoc """
  A portable set of documents (spec/03 §3): the transitive closure of what a page needs,
  with where it came from, in a map form and a JSON form so it can leave the node it was
  made on, and imported into another store as a relocation (`Macaw.Layers.Store.relocate/3`).

      %Macaw.Layers.Bundle{
        provenance: %{store: "metresis", exported_at: ~U[2026-10-20 09:30:00.000000Z], version: 1},
        entries: [%{id: {:style, 11}, name: "Styles:thick", fragment: %{style: %{width: 3}}}],
        snapshot: nil
      }

  A bundle is read through the kernel's gates (spec/01 §5) with its own version line:
  this module is a `Macaw.Layers.Version` and a `Macaw.Layers.Document`, whose `validate/1`
  judges the envelope; each entry's fragment is then read by its own type, at the type's
  own version where the type has a line.

  Ported from visualize's `Visualize.Chart.Builder.Bundle` and its codec, without boards.
  """

  @behaviour Macaw.Layers.Version
  @behaviour Macaw.Layers.Document

  alias Macaw.Layers.{Document, Fault, Form, Fragment, Store, Version}

  defstruct provenance: nil, entries: [], snapshot: nil

  @typedoc "Where a bundle came from, when, and the bundle version it was exported at."
  @type provenance :: %{
          store: String.t() | atom(),
          exported_at: DateTime.t(),
          version: pos_integer()
        }

  @type t :: %__MODULE__{
          provenance: provenance(),
          entries: [Store.entry()],
          snapshot: map() | nil
        }

  @top ~w($version provenance entries snapshot)
  @provenance ~w(store exported_at version)
  @entry ~w(id name fragment)
  # A known key's place in a fault's path, by its spelling.
  @paths %{
    "provenance" => :provenance,
    "entries" => :entries,
    "store" => :store,
    "exported_at" => :exported_at,
    "version" => :version,
    "id" => :id,
    "name" => :name,
    "fragment" => :fragment
  }

  # -- the version line --------------------------------------------------------------------

  @impl Version
  def current, do: 1

  # The line is at its first version, so no step exists yet.
  @impl Version
  def step(document, _from), do: {:ok, document}

  # -- export ------------------------------------------------------------------------------

  @doc """
  The closure of `ids` through a store (§3.1): each entry, and every entry it refers to
  (`Macaw.Layers.Fragment.refs/2`, use sites included), transitively, each once, in
  dependency order. An id the store no longer holds is skipped. `source` is the host's
  name for the store, written in the provenance.
  """
  @spec export(Store.assign(), Store.id() | [Store.id()], String.t() | atom()) :: t()
  def export(store, ids, source) when is_binary(source) or is_atom(source) do
    types = Store.types(store)

    entries =
      ids
      |> List.wrap()
      |> Enum.reduce({[], MapSet.new()}, &close(store, types, &1, &2))
      |> elem(0)
      |> Enum.reverse()

    %__MODULE__{
      provenance: %{store: source, exported_at: DateTime.utc_now(), version: current()},
      entries: entries
    }
  end

  defp close(store, types, {kind, _n} = id, {entries, seen}) do
    if id in seen do
      {entries, seen}
    else
      seen = MapSet.put(seen, id)

      case Store.get(store, id) do
        {:ok, entry} ->
          {entries, seen} =
            types
            |> Store.type_of(kind)
            |> Fragment.refs(entry.fragment)
            |> Enum.reduce({entries, seen}, &close(store, types, &1, &2))

          {[%{id: id, name: entry.name, fragment: entry.fragment} | entries], seen}

        {:error, _reason} ->
          {entries, seen}
      end
    end
  end

  # -- writing -----------------------------------------------------------------------------

  @doc """
  The bundle's map form (§3.2), each entry's fragment in its type's map form, stamped with
  the type's version where the type has a line: `{:ok, map}`, or every value without a
  form, by path.
  """
  @spec to_map(t(), [module()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def to_map(%__MODULE__{provenance: provenance, entries: entries, snapshot: snapshot}, types) do
    {written, faults} =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, i} -> write_entry(entry, i, types) end)
      |> Enum.unzip()

    {store, store_faults} = write_store(provenance.store)

    map = %{
      "$version" => current(),
      "provenance" => %{
        "store" => store,
        "exported_at" => DateTime.to_iso8601(provenance.exported_at),
        "version" => provenance.version
      },
      "entries" => written,
      "snapshot" => snapshot
    }

    case store_faults ++ Enum.concat(faults) do
      [] -> {:ok, map}
      faults -> {:error, Fault.sort(faults)}
    end
  end

  @doc "The bundle's JSON form."
  @spec to_json(t(), [module()]) :: {:ok, String.t()} | {:error, [Fault.t(), ...]}
  def to_json(bundle, types) do
    with {:ok, map} <- to_map(bundle, types), do: {:ok, JSON.encode!(map)}
  end

  defp write_store(store) when is_binary(store), do: {store, []}

  defp write_store(store) when is_atom(store) and store not in [nil, true, false],
    do: {Atom.to_string(store), []}

  defp write_store(store), do: {store, [{[:provenance, :store], {:type, :string}}]}

  defp write_entry(%{id: {kind, _n} = id, name: name, fragment: fragment}, i, types) do
    case Store.type_of(types, kind) do
      nil ->
        {%{}, [{[:entries, i, :id], {:type, :id}}]}

      type ->
        case Form.to_map(fragment, type) do
          {:ok, form} ->
            {%{"id" => Store.encode_id(id), "name" => name, "fragment" => stamp(form, type)}, []}

          {:error, faults} ->
            {%{},
             Enum.map(faults, fn {path, reason} -> {[:entries, i, :fragment | path], reason} end)}
        end
    end
  end

  defp stamp(form, type) do
    if Fragment.callback?(type, :current, 0),
      do: Map.put(form, Version.stamp(), type.current()),
      else: form
  end

  # -- reading -----------------------------------------------------------------------------

  @doc """
  The bundle a map form holds (§3.2), read through the kernel's gates with this module's
  version line — the stamp, the limits, then the envelope — and then each entry's fragment
  through the type its id names, given as a store's: `{:ok, bundle}` or every fault by path.
  `limits:` as `Macaw.Layers.Document.read/3` takes them.
  """
  @spec from_map(term(), [module()], keyword()) :: {:ok, t()} | {:error, [Fault.t(), ...]}
  def from_map(map, types, opts \\ [])

  def from_map(map, types, opts) when is_map(map) and not is_struct(map),
    do: read(map, types, opts)

  def from_map(_other, _types, _opts), do: {:error, [{[], {:type, :map}}]}

  @doc "The bundle a JSON document holds, as `from_map/3` reads it, every gate first."
  @spec from_json(String.t(), [module()], keyword()) :: {:ok, t()} | {:error, [Fault.t(), ...]}
  def from_json(json, types, opts \\ []) when is_binary(json), do: read(json, types, opts)

  defp read(input, types, opts) do
    with {:ok, document} <- Document.read(input, __MODULE__, opts) do
      kinds = Store.kinds(types)

      {entries, faults} =
        document["entries"]
        |> Enum.with_index()
        |> Enum.map_reduce({[], MapSet.new()}, fn {entry, i}, {faults, seen} ->
          {read, more} = read_entry(entry, i, types, kinds, seen)
          {read, {faults ++ more, MapSet.put(seen, read.id)}}
        end)

      case elem(faults, 0) do
        [] -> {:ok, bundle(document, entries)}
        faults -> {:error, Fault.sort(faults)}
      end
    end
  end

  defp bundle(document, entries) do
    provenance = document["provenance"]
    {:ok, exported_at, 0} = DateTime.from_iso8601(provenance["exported_at"])

    %__MODULE__{
      provenance: %{
        store: provenance["store"],
        exported_at: exported_at,
        version: provenance["version"]
      },
      entries: entries,
      snapshot: document["snapshot"]
    }
  end

  defp read_entry(%{"id" => spelled, "name" => name, "fragment" => form}, i, types, kinds, seen) do
    case Store.decode_id(kinds, spelled) do
      :error ->
        {%{id: nil, name: name, fragment: form}, [{[:entries, i, :id], {:type, :id}}]}

      {:ok, id} ->
        duplicate = if id in seen, do: [{[:entries, i, :id], {:duplicate, id}}], else: []
        {fragment, faults} = read_fragment(form, id, Store.type_of(types, elem(id, 0)), types)

        faults =
          Enum.map(faults, fn {path, reason} -> {[:entries, i, :fragment | path], reason} end)

        {%{id: id, name: name, fragment: fragment}, duplicate ++ faults}
    end
  end

  defp read_fragment(form, {kind, _n}, type, types) do
    with {:ok, form} <- migrate(form, type),
         {:ok, fragment} <- Form.from_map(form, type) do
      case Store.kind(types, fragment) do
        {_type, ^kind} -> {fragment, []}
        {_type, derived} -> {fragment, [{[], {:kind, kind, derived}}]}
        nil -> {fragment, [{[], :no_kind}]}
      end
    else
      {:error, faults} -> {form, faults}
    end
  end

  # A fragment carries its type's stamp where the type has a version line, and migrates as
  # a document of the type does; the stamp is the line's, not data.
  defp migrate(form, type) do
    if Fragment.callback?(type, :current, 0) do
      with {:ok, form} <- Version.migrate(form, type),
           do: {:ok, Map.delete(form, Version.stamp())}
    else
      {:ok, form}
    end
  end

  # -- the envelope ------------------------------------------------------------------------

  @doc false
  # The envelope at the current version, every fault by path; the fragments are read after
  # it, by their own types.
  @impl Document
  def validate(document) do
    faults =
      Document.unknown_keys(document, @top) ++
        required(document, ~w(provenance entries), []) ++
        provenance(document["provenance"]) ++
        entries(document["entries"]) ++
        snapshot(document["snapshot"])

    case faults do
      [] -> :ok
      faults -> {:error, Fault.sort(faults)}
    end
  end

  defp required(map, keys, path) do
    for key <- keys,
        not Map.has_key?(map, key),
        do: {path ++ [Map.fetch!(@paths, key)], :required}
  end

  defp provenance(nil), do: []

  defp provenance(provenance) when is_map(provenance) do
    Document.unknown_keys(provenance, @provenance, [:provenance]) ++
      required(provenance, @provenance, [:provenance]) ++
      store(provenance["store"]) ++
      exported_at(provenance["exported_at"]) ++
      version(provenance["version"])
  end

  defp provenance(_other), do: [{[:provenance], {:type, :map}}]

  defp store(nil), do: []
  defp store(store) when is_binary(store), do: []
  defp store(_store), do: [{[:provenance, :store], {:type, :string}}]

  defp exported_at(nil), do: []

  defp exported_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, _time, 0} -> []
      _ -> [{[:provenance, :exported_at], {:type, :utc_datetime}}]
    end
  end

  defp exported_at(_other), do: [{[:provenance, :exported_at], {:type, :utc_datetime}}]

  defp version(nil), do: []
  defp version(n) when is_integer(n) and n > 0, do: []
  defp version(_other), do: [{[:provenance, :version], {:type, :pos_integer}}]

  defp entries(nil), do: []

  defp entries(entries) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {entry, i} when is_map(entry) ->
        Document.unknown_keys(entry, @entry, [:entries, i]) ++
          required(entry, @entry, [:entries, i]) ++
          entry_parts(entry, i)

      {_entry, i} ->
        [{[:entries, i], {:type, :map}}]
    end)
  end

  defp entries(_other), do: [{[:entries], {:type, :list}}]

  defp entry_parts(entry, i) do
    name =
      if is_binary(Map.get(entry, "name", "")),
        do: [],
        else: [{[:entries, i, :name], {:type, :string}}]

    id =
      if is_binary(Map.get(entry, "id", "")), do: [], else: [{[:entries, i, :id], {:type, :id}}]

    fragment =
      if is_map(Map.get(entry, "fragment", %{})),
        do: [],
        else: [{[:entries, i, :fragment], {:type, :map}}]

    id ++ name ++ fragment
  end

  defp snapshot(snapshot) when is_nil(snapshot) or is_map(snapshot), do: []
  defp snapshot(_other), do: [{[:snapshot], {:type, :map}}]
end
