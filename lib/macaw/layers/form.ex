defmodule Macaw.Layers.Form do
  @moduledoc """
  The JSON adapter (spec/01 §5, §6): a document's map form and JSON form, and reading a JSON
  document through the gates to its value.

  The **value** is the document as Elixir holds it: atom keys where the type has a key,
  string names elsewhere, atoms, times. It is the one true form: the type judges it
  (`Macaw.Layers.Document.check/2`), and it is what is built, stored and compared. Its
  **map form** is JSON-ready: string keys, and a tag (`Macaw.Layers.Tags`) for every value
  JSON can't express. Its **JSON form** is that map encoded. Both are representations, made
  here at the edge.

  **The codec**, `to_map/2` and `from_map/2`, converts between the value and the map form,
  exact inverses with no gates and no validation. For a value with a form:

      from_map(to_map(value)) == {:ok, value}
      to_map(from_map(map))   == {:ok, map}    # for a map to_map/2 wrote

  **The adapter** reads an encoding that comes from elsewhere: `gates/3` takes a JSON
  document, or its decoded map form, through the gates (the bytes, the scan, the version,
  the migration, the recount) to the map form at the type's current version, and `read/3`
  then reads the value from it and judges the value by its type. `to_json/2` writes the
  value's JSON form, stamped with the type's version. A value with no form fails here, at
  its path, never where it was built.

  A document type implements this behavior: its tag table, the keys it reads as atoms, and
  the atoms a `$atom` may spell, each a closed table (`Macaw.Layers.Vocabulary`), so no
  atom is ever made from a document. A type with values of its own (a struct, a tuple)
  writes and reads them through `c:encode_value/1` and `c:decode_value/2`, under its own
  live tags.

  The kernel's terms:

  | Value | Map form |
  |---|---|
  | `nil`, a boolean, a number, a string | as it is |
  | another atom | `{"$atom": "spelling"}`, read back through `c:atoms/0` |
  | a `DateTime` in `Etc/UTC` | `{"$time": "ISO 8601"}` |
  | a list | a list |
  | a map | an object: an atom key by its spelling, a string key as it is, escaped when it starts with `$` |

  A function, a PID, a reference, a port, a tuple or a struct the type does not write has
  no form: it is refused at its path as `{:type, :term}`.

  **A name map** is a map whose keys are names, never the type's keys (a fragment type's
  `:union` and `:deep` keys hold one, spec/02 §9). A type says where its name maps are by
  `c:name_map?/1`; at one, a string key is written and read as the name it is, escaped
  when it starts with `$`, whatever its spelling, and an atom key is `{:type, :name}`,
  since names are strings. Every other map is a node, keyed as the table says. A type
  without `c:name_map?/1` has no name maps. Below a tag, a map's place is its place in
  the payload: `{:tag, tag}` and then the path within the payload, which a type writing a
  payload part that sits at the type's positions (a use site's local fragment) gives
  `encode_term/3` as `at`.
  """

  alias Macaw.Layers.{Callback, Document, Fault, Limits, Scan, Tags, Version, Vocabulary}

  @stamp "$version"

  @doc "The type's tag table: a module that uses `Macaw.Layers.Tags`."
  @callback tags() :: module()
  @doc "The keys the type reads as atoms, by spelling."
  @callback keys() :: Vocabulary.table()
  @doc "The atoms a `$atom` may spell in this type's documents."
  @callback atoms() :: Vocabulary.table()
  @doc "A value of the type's own, in its map form, or `:default` for the kernel's rules."
  @callback encode_value(term()) :: {:ok, term()} | :default
  @doc """
  The value of one of the type's own live tags, its payload already read, or `:default`
  when the tag or payload is not one it reads.
  """
  @callback decode_value(tag :: String.t(), payload :: term()) :: {:ok, term()} | :default
  @doc """
  Whether the map at `path` is a name map: its keys are names, never the type's keys.
  `path` is from the document's root, as the value holds it: atom keys, string names and
  list indexes. Below a tag it is `{:tag, tag}` followed by the path within the tag's
  payload, as it is read. A fragment type answers with `Macaw.Layers.Fragment.name_map?/2`.
  """
  @callback name_map?(path :: [term()]) :: boolean()
  @optional_callbacks encode_value: 1, decode_value: 2, name_map?: 1

  @typedoc """
  Words a reader takes beyond the type's own tables, merged over them: `keys`, read as
  atom keys, and `atoms`, the atoms a `$atom` may spell. Lists of atoms, given by code
  (an adopter's registered words), never by a document.
  """
  @type vocabulary :: %{optional(:keys) => [atom()], optional(:atoms) => [atom()]}

  @typedoc "`gates/3`'s and `read/3`'s options; the codec takes `vocabulary:`."
  @type option :: {:limits, keyword() | map()} | {:vocabulary, vocabulary()}

  @doc """
  The value's map form: `{:ok, map}`, or every value and key without one, by path.
  `vocabulary:` the words the type's keys are taken with (see `read/3`).
  """
  @spec to_map(map(), module(), [option()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def to_map(value, type, opts \\ [])

  def to_map(value, type, opts) when is_map(value) and not is_struct(value) do
    case encode(value, [], reader(type, opts), names(type), true) do
      {map, []} -> {:ok, map}
      {_map, faults} -> {:error, Fault.sort(faults)}
    end
  end

  def to_map(_value, _type, _opts), do: {:error, [{[], {:type, :map}}]}

  @doc """
  One term's map form, for a type writing its own tag's payload (spec/01 §6): `{:ok, form}`,
  or every value and key without one, by path from the term.

  `at` is the term's place, as `c:name_map?/1` is asked it below a tag: `{:tag, tag}` and
  the path of the term within the payload (`[{:tag, "$use"}, "local"]`), so its maps are
  written as the reader reads them there. `nil`, the default, is no place: every map in
  the term is a node.
  """
  @spec encode_term(term(), module(), [term()] | nil) ::
          {:ok, term()} | {:error, [Fault.t(), ...]}
  def encode_term(term, type, at \\ nil) do
    names = if at == nil, do: &nodes/1, else: placed(names(type), at)

    case encode(term, [], reader(type, []), names, false) do
      {form, []} -> {:ok, form}
      {_form, faults} -> {:error, Fault.sort(faults)}
    end
  end

  @doc """
  The value a map form holds: its tags held to the type's table, its keys read against the
  type's keys, its `$atom`s against the type's atoms, each with the `vocabulary:` given
  (see `read/3`); `{:ok, value}` or every fault.
  """
  @spec from_map(map(), module(), [option()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def from_map(map, type, opts \\ [])

  def from_map(map, type, opts) when is_map(map) and not is_struct(map) do
    with {:ok, map} <- Tags.read(map, type.tags()) do
      case decode(map, [], reader(type, opts), names(type), true) do
        {value, []} -> {:ok, value}
        {_value, faults} -> {:error, Fault.sort(faults)}
      end
    end
  end

  def from_map(_map, _type, _opts), do: {:error, [{[], {:type, :map}}]}

  @doc """
  The value's JSON form, stamped `"$version"` with the type's current version where the
  type has a version line (`c:Macaw.Layers.Version.current/0`): `{:ok, json}`, or every
  value and key without a form, by path. The value is not judged here: that is
  `Macaw.Layers.Document.check/2`. `vocabulary:` as `to_map/3` takes it.
  """
  @spec to_json(map(), module(), [option()]) :: {:ok, binary()} | {:error, [Fault.t(), ...]}
  def to_json(value, type, opts \\ []) do
    with {:ok, map} <- to_map(value, type, opts), do: {:ok, JSON.encode!(stamp(map, type))}
  end

  defp stamp(map, type) do
    if Callback.exported?(type, :current, 0),
      do: Map.put(map, @stamp, type.current()),
      else: map
  end

  @doc """
  A document from elsewhere through the gates, in order (spec/01 §5): `{:ok, map}`, its
  map form at the type's current version, stamp included, or every fault of the first gate
  that refuses it.

  1. **bytes**: a JSON document longer than the `bytes` limit is refused;
  2. **decode** with the `depth` and `items` limits, by `Macaw.Layers.Scan`, which stops at
     a limit before any value is built; only then is it decoded, with Elixir's `JSON`, and
     its root must be an object. A map form given directly skips the bytes and is walked
     for `depth` and `items` instead (`Macaw.Layers.Limits.structure/2`);
  3. **version**: a newer stamp is refused by name before anything else is read;
  4. **migrate**, step by step;
  5. **recount** `depth` and `items`, since a migration can grow a document.

  `type` implements `Macaw.Layers.Version`. `limits:` tightens the limits, or raises one by
  name, as `Macaw.Layers.Limits.new/1` takes them. Nothing in the document is evaluated,
  and its value is not judged: that is `read/3`.
  """
  @spec gates(binary() | map(), module(), [option()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def gates(input, type, opts \\ []) when is_atom(type) do
    limits = Limits.new(Keyword.get(opts, :limits, []))

    with {:ok, map} <- decode_input(input, limits),
         {:ok, map} <- Version.migrate(map, type) do
      recount(map, limits)
    end
  end

  @doc """
  The value a document from elsewhere holds: through `gates/3`, then read from its map form
  (`from_map/2`, the stamp dropped), then judged by its type
  (`Macaw.Layers.Document.check/2`); `{:ok, value}`, or the faults of the first step that
  refuses it.

  `input` is a JSON document, a binary, or its decoded map form. `type` implements this
  behavior, `Macaw.Layers.Version` and `Macaw.Layers.Document`. `limits:` as `gates/3`
  takes them.

  **The vocabulary is the reader's.** The words a document may spell as atoms are the
  type's tables (`c:keys/0`, `c:atoms/0`) and, with `vocabulary: %{keys: [...], atoms:
  [...]}`, the words given there, merged over them: an adopter's registered words, given
  by code. No atom is made from the document beyond those tables. A key outside them is
  read as its string, and a `$atom` outside them is `{:enum, atoms}` at its path.
  """
  @spec read(binary() | map(), module(), [option()]) :: {:ok, term()} | {:error, [Fault.t(), ...]}
  def read(input, type, opts \\ []) when is_atom(type) do
    with {:ok, map} <- gates(input, type, opts),
         {:ok, value} <- from_map(Map.delete(map, @stamp), type, opts) do
      Document.check(value, type)
    end
  end

  # The type and the tables it reads with: its own, the `vocabulary:` merged over them.
  defp reader(type, opts) do
    words = Keyword.get(opts, :vocabulary, %{})

    if not vocabulary?(words),
      do:
        raise(
          ArgumentError,
          "vocabulary: is %{keys: [atom], atoms: [atom]}, got #{inspect(words)}"
        )

    %{
      type: type,
      keys: Map.merge(type.keys(), Vocabulary.table(Map.get(words, :keys, []))),
      atoms: Map.merge(type.atoms(), Vocabulary.table(Map.get(words, :atoms, [])))
    }
  end

  defp vocabulary?(%{} = words) when not is_struct(words) do
    Enum.all?(words, fn {k, v} ->
      k in [:keys, :atoms] and is_list(v) and
        Enum.all?(v, &(is_atom(&1) and &1 not in [nil, true, false]))
    end)
  end

  defp vocabulary?(_other), do: false

  # -- the gates ------------------------------------------------------------------------

  defp decode_input(json, limits) when is_binary(json) do
    with :ok <- bytes(json, limits),
         :ok <- scan(json, limits),
         {:ok, term} <- json_decode(json) do
      object(term)
    end
  end

  defp decode_input(map, limits) when is_map(map) and not is_struct(map) do
    case Limits.structure(map, limits) do
      [] -> {:ok, map}
      faults -> {:error, faults}
    end
  end

  defp decode_input(_other, _limits), do: {:error, [{[], {:type, :map}}]}

  defp bytes(json, %{bytes: max}) when byte_size(json) > max,
    do: {:error, [{[], {:limit, :bytes, max, byte_size(json)}}]}

  defp bytes(_json, _limits), do: :ok

  defp scan(json, limits) do
    case Scan.scan(json, limits) do
      :ok -> :ok
      {:error, fault} -> {:error, [fault]}
    end
  end

  defp json_decode(json) do
    case JSON.decode(json) do
      {:ok, term} -> {:ok, term}
      {:error, reason} -> {:error, [{[], {:json, json_words(reason)}}]}
    end
  end

  # A document is an object at its root.
  defp object(map) when is_map(map), do: {:ok, map}
  defp object(_other), do: {:error, [{[], {:type, :map}}]}

  # A migration can grow a document, so the migrated map form is counted again.
  defp recount(map, limits) do
    case Limits.structure(map, limits) do
      [] -> {:ok, map}
      faults -> {:error, faults}
    end
  end

  # Elixir's `JSON` reasons, as a person reads them.
  defp json_words({:unexpected_end, offset}),
    do: "it ends at byte #{offset}, before the value does"

  defp json_words({:invalid_byte, offset, byte}),
    do: "unexpected byte #{inspect(<<byte>>)} at byte #{offset}"

  defp json_words({:unexpected_sequence, offset, bytes}),
    do: "unexpected #{inspect(bytes)} at byte #{offset}"

  defp json_words(other), do: inspect(other)

  # -- name maps ------------------------------------------------------------------------

  # Whether the map at a path is a name map: the type's word where it gives one, else no
  # map is.
  defp names(type) do
    if Callback.exported?(type, :name_map?, 1), do: &type.name_map?/1, else: &nodes/1
  end

  defp nodes(_path), do: false

  # A term's maps asked at their place: `at`, then their path within the term.
  defp placed(names, at), do: fn path -> names.(at ++ path) end

  # -- encode ---------------------------------------------------------------------------

  defp encode(term, path, type, names, root?) do
    case own(type, term) do
      {:ok, json} -> {json, []}
      :default -> term(term, path, type, names, root?)
    end
  end

  defp own(%{type: type}, term) do
    if Callback.exported?(type, :encode_value, 1), do: type.encode_value(term), else: :default
  end

  defp term(v, _path, _type, _names, _root?)
       when is_nil(v) or is_boolean(v) or is_number(v) or is_binary(v),
       do: {v, []}

  defp term(v, _path, _type, _names, _root?) when is_atom(v),
    do: {%{"$atom" => Atom.to_string(v)}, []}

  defp term(%DateTime{time_zone: "Etc/UTC"} = t, _path, _type, _names, _root?),
    do: {%{"$time" => DateTime.to_iso8601(t)}, []}

  defp term(v, path, type, names, _root?) when is_list(v) do
    {items, faults} =
      v
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> encode(e, path ++ [i], type, names, false) end)
      |> Enum.unzip()

    {items, Enum.concat(faults)}
  end

  defp term(v, path, type, names, root?) when is_map(v) and not is_struct(v) do
    keys = if names.(path), do: :names, else: type.keys

    {pairs, faults} =
      v
      |> Enum.map(fn {k, e} ->
        {json_key, key_faults} = key(k, path, keys, root?)
        {e, faults} = encode(e, path ++ [k], type, names, false)
        {{json_key, e}, key_faults ++ faults}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(faults)}
  end

  defp term(v, path, _type, _names, _root?), do: {v, [{path, {:type, :term}}]}

  # In a name map a key is a name, a string, escaped when it starts with `$`. In a node an
  # atom key is one the type reads; a string key is a name, which must not be spelled like
  # one of the type's keys (it would read back as the key), escaped when it starts with
  # `$`. The stamp at the root is not data.
  defp key(@stamp, _path, _keys, true), do: {@stamp, []}

  defp key(k, _path, :names, _root?) when is_binary(k), do: {Tags.escape(k), []}

  defp key(k, path, keys, _root?)
       when is_atom(k) and not is_nil(k) and not is_boolean(k) and keys != :names do
    spelling = Atom.to_string(k)

    case Vocabulary.fetch(keys, spelling) do
      {:ok, ^k} -> {spelling, []}
      _ -> {spelling, [{path ++ [k], :unknown_key}]}
    end
  end

  defp key(k, path, keys, _root?) when is_binary(k) do
    case Vocabulary.fetch(keys, k) do
      {:ok, _} -> {k, [{path ++ [k], :key_spelling}]}
      :error -> {Tags.escape(k), []}
    end
  end

  defp key(k, path, _keys, _root?), do: {k, [{path ++ [k], {:type, :name}}]}

  # -- decode ---------------------------------------------------------------------------

  # The root's stamp alone is data, not the `$version` tag.
  defp decode(%{@stamp => _} = map, path, type, names, true) when map_size(map) == 1,
    do: data(map, path, type, names, true)

  defp decode(map, path, type, names, root?) when is_map(map) and map_size(map) == 1 do
    case Map.to_list(map) do
      [{"$$" <> _, _}] -> data(map, path, type, names, root?)
      [{"$" <> _ = tag, payload}] -> tagged(tag, payload, path, type)
      _ -> data(map, path, type, names, root?)
    end
  end

  defp decode(map, path, type, names, root?) when is_map(map),
    do: data(map, path, type, names, root?)

  defp decode(list, path, type, names, _root?) when is_list(list) do
    {items, faults} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> decode(e, path ++ [i], type, names, false) end)
      |> Enum.unzip()

    {items, Enum.concat(faults)}
  end

  defp decode(leaf, _path, _type, _names, _root?), do: {leaf, []}

  defp tagged("$atom", spelling, path, type) do
    atoms = type.atoms

    case Vocabulary.fetch(atoms, spelling) do
      {:ok, atom} -> {atom, []}
      :error -> {spelling, [{path, {:enum, atoms |> Map.values() |> Enum.sort()}}]}
    end
  end

  defp tagged("$time", iso, path, _type) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, time, 0} -> {time, []}
      _ -> {iso, [{path, {:type, :time}}]}
    end
  end

  defp tagged("$time", other, path, _type), do: {other, [{path, {:type, :time}}]}

  # A payload's maps are asked at their place in it: `{:tag, tag}`, then their path below
  # the tag, as `encode_term/3` writes them.
  defp tagged(tag, payload, path, type) do
    below = length(path) + 1
    at = placed(names(type.type), [{:tag, tag}])
    names = fn path -> at.(Enum.drop(path, below)) end
    {payload, faults} = decode(payload, path ++ [tag], type, names, false)

    cond do
      faults != [] ->
        {payload, faults}

      Callback.exported?(type.type, :decode_value, 2) ->
        case type.type.decode_value(tag, payload) do
          {:ok, value} -> {value, []}
          :default -> {payload, [{path, {:unknown_tag, tag}}]}
        end

      true ->
        {payload, [{path, {:unknown_tag, tag}}]}
    end
  end

  defp data(map, path, type, names, root?) do
    keys = if names.(path), do: :names, else: type.keys

    {pairs, faults} =
      map
      |> Enum.map(fn {k, e} ->
        k = read_key(k, keys, root?)
        {e, faults} = decode(e, path ++ [k], type, names, false)
        {{k, e}, faults}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(faults)}
  end

  # A name map's key is the name, never the type's key of the same spelling.
  defp read_key(@stamp, _keys, true), do: @stamp
  defp read_key(k, :names, _root?), do: Tags.unescape(k)

  defp read_key(k, keys, _root?) do
    case Vocabulary.fetch(keys, k) do
      {:ok, atom} -> atom
      :error -> Tags.unescape(k)
    end
  end
end
