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

  A bundle is a term, judged as one by `check/2` however it was made: this module is a
  `Macaw.Layers.Document`, whose `validate/1` judges the envelope, and `check/2` adds each
  entry's kind against the store's types. Its map and JSON forms are made at the edge:
  `to_map/2` and `to_json/2` write them, and `from_map/3` and `from_json/3` read one
  through the JSON adapter's gates (`Macaw.Layers.Form.gates/3`, spec/01 §5) with the
  bundle's own version line (this module is a `Macaw.Layers.Version`), decode the envelope,
  read each entry's fragment by its own type, at the type's own version where the type has
  a line, and then check the term.

  Ported from visualize's `Visualize.Chart.Builder.Bundle` and its codec, without boards.
  """

  @behaviour Macaw.Layers.Version
  @behaviour Macaw.Layers.Document

  alias Macaw.Layers.{Callback, Document, Fault, Form, Fragment, Store, Version}

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
  form, by path. `vocabularies:` as `from_map/3` takes them.
  """
  @spec to_map(t(), [module()], keyword()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def to_map(
        %__MODULE__{provenance: provenance, entries: entries, snapshot: snapshot},
        types,
        opts \\ []
      ) do
    words = vocabularies(opts, types)

    {written, faults} =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, i} -> write_entry(entry, i, types, words) end)
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

  @doc "The bundle's JSON form. `vocabularies:` as `from_map/3` takes them."
  @spec to_json(t(), [module()], keyword()) :: {:ok, String.t()} | {:error, [Fault.t(), ...]}
  def to_json(bundle, types, opts \\ []) do
    with {:ok, map} <- to_map(bundle, types, opts), do: {:ok, JSON.encode!(map)}
  end

  # Each type's vocabulary (`Macaw.Layers.Form.read/3`'s `vocabulary:`), by type: a type
  # the store does not have is a mistake in the caller's code, so it raises.
  defp vocabularies(opts, types) do
    words = Keyword.get(opts, :vocabularies, %{})

    if not (is_map(words) and not is_struct(words) and
              Enum.all?(Map.keys(words), &(&1 in types))),
       do:
         raise(
           ArgumentError,
           "vocabularies: is a map from types of #{inspect(types)} to vocabularies, " <>
             "got #{inspect(words)}"
         )

    words
  end

  defp vocabulary(words, type), do: [vocabulary: Map.get(words, type, %{})]

  defp write_store(store) when is_binary(store), do: {store, []}

  defp write_store(store) when is_atom(store) and store not in [nil, true, false],
    do: {Atom.to_string(store), []}

  defp write_store(store), do: {store, [{[:provenance, :store], {:type, :string}}]}

  defp write_entry(%{id: {kind, _n} = id, name: name, fragment: fragment}, i, types, words) do
    case Store.type_of(types, kind) do
      nil ->
        {%{}, [{[:entries, i, :id], {:type, :id}}]}

      type ->
        case Form.to_map(fragment, type, vocabulary(words, type)) do
          {:ok, form} ->
            {%{"id" => Store.encode_id(id), "name" => name, "fragment" => stamp(form, type)}, []}

          {:error, faults} ->
            {%{},
             Enum.map(faults, fn {path, reason} -> {[:entries, i, :fragment | path], reason} end)}
        end
    end
  end

  defp stamp(form, type) do
    if Callback.exported?(type, :current, 0),
      do: Map.put(form, Version.stamp(), type.current()),
      else: form
  end

  # -- reading -----------------------------------------------------------------------------

  @doc """
  The bundle a map form holds (§3.2): through the JSON adapter's gates with this module's
  version line (`Macaw.Layers.Form.gates/3`: the limits, the stamp, the migration, the
  recount), then the envelope's own decode of the map form, then each entry's fragment read
  by the type its id names, at the type's own version, and then the bundle judged as a term
  (`check/2`): `{:ok, bundle}`, or the faults of the first step that refuses it, by path.
  `types` are a store's; `limits:` as `Macaw.Layers.Form.gates/3` takes them.
  `vocabularies: %{type => vocabulary}` gives each type the words its entries are read
  with, as `Macaw.Layers.Form.read/3`'s `vocabulary:` (an adopter's registered words), so
  an entry reads as a document of its type would standalone; a type not in `types` raises.
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
    words = vocabularies(opts, types)

    with {:ok, form} <- Form.gates(input, __MODULE__, Keyword.take(opts, [:limits])),
         :ok <- faults(envelope(form)),
         {:ok, bundle} <- decode(form, types, words) do
      check(bundle, types)
    end
  end

  defp faults([]), do: :ok
  defp faults(faults), do: {:error, Fault.sort(faults)}

  # The envelope's map form, as only a map form can be wrong: a key the bundle does not
  # have, a part missing, a part that is not the map or list it holds, a store that is not
  # a string, a time that is not ISO 8601 in UTC, an id that is not a string. What a value
  # can be wrong in too (a name, a fragment, a version, the snapshot) is the term's check.
  defp envelope(form) do
    Document.unknown_keys(form, @top) ++
      required(form, ~w(provenance entries), []) ++
      part(form, "provenance", &provenance_form/1) ++
      part(form, "entries", &entries_form/1)
  end

  # A part the map form holds, judged; a missing one is `required/3`'s.
  defp part(form, key, judge) do
    case Map.fetch(form, key) do
      {:ok, value} -> judge.(value)
      :error -> []
    end
  end

  defp required(map, keys, path) do
    for key <- keys,
        not Map.has_key?(map, key),
        do: {path ++ [Map.fetch!(@paths, key)], :required}
  end

  defp provenance_form(provenance) when is_map(provenance) do
    Document.unknown_keys(provenance, @provenance, [:provenance]) ++
      required(provenance, @provenance, [:provenance]) ++
      case provenance do
        %{"store" => store} when not is_binary(store) ->
          [{[:provenance, :store], {:type, :string}}]

        _ ->
          []
      end ++
      case Map.fetch(provenance, "exported_at") do
        {:ok, iso} -> if utc_iso8601(iso), do: [], else: [exported_at_fault()]
        :error -> []
      end
  end

  defp provenance_form(_other), do: [{[:provenance], {:type, :map}}]

  defp utc_iso8601(iso) when is_binary(iso),
    do: match?({:ok, _time, 0}, DateTime.from_iso8601(iso))

  defp utc_iso8601(_other), do: false

  defp exported_at_fault, do: {[:provenance, :exported_at], {:type, :utc_datetime}}

  defp entries_form(entries) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {entry, i} when is_map(entry) ->
        Document.unknown_keys(entry, @entry, [:entries, i]) ++
          required(entry, @entry, [:entries, i]) ++
          if(is_binary(Map.get(entry, "id", "")),
            do: [],
            else: [{[:entries, i, :id], {:type, :id}}]
          )

      {_entry, i} ->
        [{[:entries, i], {:type, :map}}]
    end)
  end

  defp entries_form(_other), do: [{[:entries], {:type, :list}}]

  # The bundle a sound envelope holds: each id read against the types' kinds, so no atom is
  # made from a document's kind, and each fragment read by its type.
  defp decode(form, types, words) do
    kinds = Store.kinds(types)

    {entries, faults} =
      form["entries"]
      |> Enum.with_index()
      |> Enum.map(fn {entry, i} -> read_entry(entry, i, types, kinds, words) end)
      |> Enum.unzip()

    with :ok <- faults(Enum.concat(faults)) do
      provenance = form["provenance"]
      {:ok, exported_at, 0} = DateTime.from_iso8601(provenance["exported_at"])

      {:ok,
       %__MODULE__{
         provenance: %{
           store: provenance["store"],
           exported_at: exported_at,
           version: provenance["version"]
         },
         entries: entries,
         snapshot: form["snapshot"]
       }}
    end
  end

  defp read_entry(%{"id" => spelled, "name" => name, "fragment" => form}, i, types, kinds, words) do
    case Store.decode_id(kinds, spelled) do
      :error ->
        {%{id: nil, name: name, fragment: form}, [{[:entries, i, :id], {:type, :id}}]}

      {:ok, {kind, _n} = id} ->
        type = Store.type_of(types, kind)

        case read_fragment(form, type, vocabulary(words, type)) do
          {:ok, fragment} ->
            {%{id: id, name: name, fragment: fragment}, []}

          {:error, faults} ->
            {%{id: id, name: name, fragment: form},
             Enum.map(faults, fn {path, reason} -> {[:entries, i, :fragment | path], reason} end)}
        end
    end
  end

  # A fragment that is not a map is no form of its type; it is kept as it is, for the
  # term's check to refuse.
  defp read_fragment(form, type, opts) when is_map(form) do
    with {:ok, form} <- migrate(form, type), do: Form.from_map(form, type, opts)
  end

  defp read_fragment(other, _type, _opts), do: {:ok, other}

  # A fragment carries its type's stamp where the type has a version line, and migrates as
  # a document of the type does; the stamp is the line's, not data.
  defp migrate(form, type) do
    if Callback.exported?(type, :current, 0) do
      with {:ok, form} <- Version.migrate(form, type),
           do: {:ok, Map.delete(form, Version.stamp())}
    else
      {:ok, form}
    end
  end

  # -- the term ----------------------------------------------------------------------------

  @doc """
  The bundle judged as a term (§3.2), however it was made: its envelope by `validate/1`
  (`Macaw.Layers.Document.check/2`), and each entry's kind against the type its id names,
  `types` given as a store's: an id of a kind none of them has is `{:type, :id}`, a
  fragment that derives to no kind `:no_kind`, and one that derives to another kind than
  its id's `{:kind, id_kind, derived}`. `{:ok, bundle}`, or every fault, ordered by path.

  This is how a bundle built in Elixir is judged; no form is written or read, so a value
  only an encoding can't hold fails at that encoding (`to_map/2`), not here.
  """
  @spec check(t(), [module()]) :: {:ok, t()} | {:error, [Fault.t(), ...]}
  def check(%__MODULE__{} = bundle, types) when is_list(types) do
    envelope =
      case Document.check(bundle, __MODULE__) do
        {:ok, _bundle} -> []
        {:error, faults} -> faults
      end

    case envelope ++ kinds(bundle.entries, types) do
      [] -> {:ok, bundle}
      faults -> {:error, Fault.sort(faults)}
    end
  end

  # Each well-formed entry's kind; a malformed one is the envelope's fault.
  defp kinds(entries, types) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%{id: {kind, _n} = id, fragment: fragment}, i} when is_map(fragment) ->
        if id?(id) and not is_struct(fragment), do: kind(kind, fragment, i, types), else: []

      _other ->
        []
    end)
  end

  defp kinds(_entries, _types), do: []

  defp kind(kind, fragment, i, types) do
    if Store.type_of(types, kind) == nil do
      [{[:entries, i, :id], {:type, :id}}]
    else
      case Store.kind(types, fragment) do
        {_type, ^kind} -> []
        {_type, derived} -> [{[:entries, i, :fragment], {:kind, kind, derived}}]
        nil -> [{[:entries, i, :fragment], :no_kind}]
      end
    end
  end

  @doc false
  # The envelope as a term, every fault by path; the entries' kinds are `check/2`'s, which
  # knows the store's types.
  @impl Document
  def validate(%__MODULE__{provenance: provenance, entries: entries, snapshot: snapshot}) do
    faults = provenance(provenance) ++ entries(entries) ++ snapshot(snapshot)

    case faults do
      [] -> :ok
      faults -> {:error, Fault.sort(faults)}
    end
  end

  defp provenance(nil), do: [{[:provenance], :required}]

  defp provenance(provenance) when is_map(provenance) and not is_struct(provenance) do
    Document.unknown_keys(provenance, [:store, :exported_at, :version], [:provenance]) ++
      for(
        key <- [:store, :exported_at, :version],
        not Map.has_key?(provenance, key),
        do: {[:provenance, key], :required}
      ) ++
      Enum.flat_map(provenance, &provenance_part/1)
  end

  defp provenance(_other), do: [{[:provenance], {:type, :map}}]

  defp provenance_part({:store, store}) when is_binary(store), do: []

  defp provenance_part({:store, store}) when is_atom(store) and store not in [nil, true, false],
    do: []

  defp provenance_part({:store, _store}), do: [{[:provenance, :store], {:type, :string}}]
  defp provenance_part({:exported_at, %DateTime{time_zone: "Etc/UTC"}}), do: []
  defp provenance_part({:exported_at, _other}), do: [exported_at_fault()]
  defp provenance_part({:version, n}) when is_integer(n) and n > 0, do: []
  defp provenance_part({:version, _n}), do: [{[:provenance, :version], {:type, :pos_integer}}]
  defp provenance_part(_unknown), do: []

  defp entries(entries) when is_list(entries) do
    indexed = Enum.with_index(entries)

    Enum.flat_map(indexed, fn
      {entry, i} when is_map(entry) and not is_struct(entry) ->
        Document.unknown_keys(entry, [:id, :name, :fragment], [:entries, i]) ++
          for(
            key <- [:id, :name, :fragment],
            not Map.has_key?(entry, key),
            do: {[:entries, i, key], :required}
          ) ++
          Enum.flat_map(entry, &entry_part(&1, i))

      {_entry, i} ->
        [{[:entries, i], {:type, :map}}]
    end) ++ duplicates(indexed)
  end

  defp entries(_other), do: [{[:entries], {:type, :list}}]

  defp entry_part({:id, id}, i),
    do: if(id?(id), do: [], else: [{[:entries, i, :id], {:type, :id}}])

  defp entry_part({:name, name}, _i) when is_binary(name), do: []
  defp entry_part({:name, _name}, i), do: [{[:entries, i, :name], {:type, :string}}]

  defp entry_part({:fragment, fragment}, _i) when is_map(fragment) and not is_struct(fragment),
    do: []

  defp entry_part({:fragment, _fragment}, i), do: [{[:entries, i, :fragment], {:type, :map}}]
  defp entry_part(_unknown, _i), do: []

  defp id?({kind, n}),
    do: is_atom(kind) and kind not in [nil, true, false] and is_integer(n) and n > 0

  defp id?(_other), do: false

  # Every id carried again after its first entry.
  defp duplicates(indexed) do
    indexed
    |> Enum.reduce({[], MapSet.new()}, fn
      {%{id: id}, i}, {faults, seen} when is_tuple(id) ->
        if id?(id) and id in seen,
          do: {[{[:entries, i, :id], {:duplicate, id}} | faults], seen},
          else: {faults, MapSet.put(seen, id)}

      _other, acc ->
        acc
    end)
    |> elem(0)
  end

  defp snapshot(snapshot) when is_nil(snapshot) or (is_map(snapshot) and not is_struct(snapshot)),
    do: []

  defp snapshot(_other), do: [{[:snapshot], {:type, :map}}]
end
