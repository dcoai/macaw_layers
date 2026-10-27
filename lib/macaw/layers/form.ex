defmodule Macaw.Layers.Form do
  @moduledoc """
  A document's map form and JSON form, exact inverses for valid values (spec/01 §6).

  The **value** is the document as Elixir holds it: atom keys where the type has a key,
  string names elsewhere, atoms, times. Its **map form** is JSON-ready: string keys, and a
  tag (`Macaw.Layers.Tags`) for every value JSON can't express. Its **JSON form** is that
  map encoded. For a valid value:

      from_map(to_map(value)) == {:ok, value}
      to_map(from_map(map))   == {:ok, map}    # for a map to_map/2 wrote

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
  """

  alias Macaw.Layers.{Document, Fault, Tags, Vocabulary}

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
  @optional_callbacks encode_value: 1, decode_value: 2

  @doc "The value's map form: `{:ok, map}`, or every value and key without one, by path."
  @spec to_map(map(), module()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def to_map(value, type) when is_map(value) and not is_struct(value) do
    case encode(value, [], type, true) do
      {map, []} -> {:ok, map}
      {_map, faults} -> {:error, Fault.sort(faults)}
    end
  end

  def to_map(_value, _type), do: {:error, [{[], {:type, :map}}]}

  @doc """
  One term's map form, for a type writing its own tag's payload (spec/01 §6): `{:ok, form}`,
  or every value and key without one, by path from the term.
  """
  @spec encode_term(term(), module()) :: {:ok, term()} | {:error, [Fault.t(), ...]}
  def encode_term(term, type) do
    case encode(term, [], type, false) do
      {form, []} -> {:ok, form}
      {_form, faults} -> {:error, Fault.sort(faults)}
    end
  end

  @doc "The value's JSON form."
  @spec to_json(map(), module()) :: {:ok, binary()} | {:error, [Fault.t(), ...]}
  def to_json(value, type) do
    with {:ok, map} <- to_map(value, type), do: {:ok, JSON.encode!(map)}
  end

  @doc """
  The value a map form holds: its tags held to the type's table, its keys read against the
  type's keys, its `$atom`s against the type's atoms; `{:ok, value}` or every fault.
  """
  @spec from_map(map(), module()) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def from_map(map, type) when is_map(map) and not is_struct(map) do
    with {:ok, map} <- Tags.read(map, type.tags()) do
      case decode(map, [], type, true) do
        {value, []} -> {:ok, value}
        {_value, faults} -> {:error, Fault.sort(faults)}
      end
    end
  end

  def from_map(_map, _type), do: {:error, [{[], {:type, :map}}]}

  @doc """
  The value a JSON document holds, read through every gate (`Macaw.Layers.Document.read/3`)
  and then from its map form. `type` implements this behavior, `Macaw.Layers.Version` and
  `Macaw.Layers.Document`.
  """
  @spec from_json(binary(), module(), [Document.option()]) ::
          {:ok, map()} | {:error, [Fault.t(), ...]}
  def from_json(json, type, opts \\ []) when is_binary(json) do
    with {:ok, map} <- Document.read(json, type, opts), do: from_map(map, type)
  end

  # -- encode ---------------------------------------------------------------------------

  defp encode(term, path, type, root?) do
    case own(type, term) do
      {:ok, json} -> {json, []}
      :default -> term(term, path, type, root?)
    end
  end

  defp own(type, term) do
    if function_exported?(type, :encode_value, 1), do: type.encode_value(term), else: :default
  end

  defp term(v, _path, _type, _root?)
       when is_nil(v) or is_boolean(v) or is_number(v) or is_binary(v),
       do: {v, []}

  defp term(v, _path, _type, _root?) when is_atom(v), do: {%{"$atom" => Atom.to_string(v)}, []}

  defp term(%DateTime{time_zone: "Etc/UTC"} = t, _path, _type, _root?),
    do: {%{"$time" => DateTime.to_iso8601(t)}, []}

  defp term(v, path, type, _root?) when is_list(v) do
    {items, faults} =
      v
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> encode(e, path ++ [i], type, false) end)
      |> Enum.unzip()

    {items, Enum.concat(faults)}
  end

  defp term(v, path, type, root?) when is_map(v) and not is_struct(v) do
    keys = type.keys()

    {pairs, faults} =
      v
      |> Enum.map(fn {k, e} ->
        {json_key, key_faults} = key(k, path, keys, root?)
        {e, faults} = encode(e, path ++ [k], type, false)
        {{json_key, e}, key_faults ++ faults}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(faults)}
  end

  defp term(v, path, _type, _root?), do: {v, [{path, {:type, :term}}]}

  # An atom key is one the type reads; a string key is a name, which must not be spelled
  # like one of the type's keys (it would read back as the key), escaped when it starts
  # with `$`. The stamp at the root is not data.
  defp key(@stamp, _path, _keys, true), do: {@stamp, []}

  defp key(k, path, keys, _root?) when is_atom(k) and not is_nil(k) and not is_boolean(k) do
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
  defp decode(%{@stamp => _} = map, path, type, true) when map_size(map) == 1,
    do: data(map, path, type, true)

  defp decode(map, path, type, root?) when is_map(map) and map_size(map) == 1 do
    case Map.to_list(map) do
      [{"$$" <> _, _}] -> data(map, path, type, root?)
      [{"$" <> _ = tag, payload}] -> tagged(tag, payload, path, type)
      _ -> data(map, path, type, root?)
    end
  end

  defp decode(map, path, type, root?) when is_map(map), do: data(map, path, type, root?)

  defp decode(list, path, type, _root?) when is_list(list) do
    {items, faults} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> decode(e, path ++ [i], type, false) end)
      |> Enum.unzip()

    {items, Enum.concat(faults)}
  end

  defp decode(leaf, _path, _type, _root?), do: {leaf, []}

  defp tagged("$atom", spelling, path, type) do
    atoms = type.atoms()

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

  defp tagged(tag, payload, path, type) do
    {payload, faults} = decode(payload, path ++ [tag], type, false)

    cond do
      faults != [] ->
        {payload, faults}

      function_exported?(type, :decode_value, 2) ->
        case type.decode_value(tag, payload) do
          {:ok, value} -> {value, []}
          :default -> {payload, [{path, {:unknown_tag, tag}}]}
        end

      true ->
        {payload, [{path, {:unknown_tag, tag}}]}
    end
  end

  defp data(map, path, type, root?) do
    keys = type.keys()

    {pairs, faults} =
      map
      |> Enum.map(fn {k, e} ->
        k = read_key(k, keys, root?)
        {e, faults} = decode(e, path ++ [k], type, false)
        {{k, e}, faults}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(faults)}
  end

  defp read_key(@stamp, _keys, true), do: @stamp

  defp read_key(k, keys, _root?) do
    case Vocabulary.fetch(keys, k) do
      {:ok, atom} -> atom
      :error -> Tags.unescape(k)
    end
  end
end
