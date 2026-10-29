defmodule Macaw.Layers.Document do
  @moduledoc """
  A document type's validity, judged on its value (spec/01 §5).

  A document type implements this behavior: `c:validate/1`, which judges the type's
  **value**, the terms Elixir holds (atom keys where the type has a key, string names
  elsewhere, atoms, times, the type's own structs), never a representation of it. `check/2`
  is how any value is judged, whether built in Elixir or read from an encoding:

      {:ok, value} = Macaw.Layers.Document.check(value, MyApp.Page)

  The kernel knows no encoding here. Reading one is an adapter's: `Macaw.Layers.Form` is the
  JSON adapter, whose `read/3` takes a JSON document through the gates (the bytes, the
  scan, the version, the migration, the recount), reads its value from the map form, and
  then judges the value by `check/2`. The limits bound what reading an encoding costs, so
  they are the adapter's; a value is judged with none.
  """

  alias Macaw.Layers.Fault

  @doc """
  `:ok`, or every fault of the type's value. Unknown keys are refused by name (see
  `unknown_keys/3`).
  """
  @callback validate(value :: term()) :: :ok | {:error, [Fault.t(), ...]}

  @doc """
  The value judged by its type's `c:validate/1`: `{:ok, value}`, or every fault, ordered by
  path. No encoding is involved: a value holding a term no adapter can write is judged as
  the type's own rules say, and fails only at that adapter.
  """
  @spec check(term(), module()) :: {:ok, term()} | {:error, [Fault.t(), ...]}
  def check(value, type) when is_atom(type) do
    case type.validate(value) do
      :ok -> {:ok, value}
      {:error, [_ | _] = faults} -> {:error, Fault.sort(faults)}
    end
  end

  @doc """
  The faults of `map`'s keys that are not among `known`, each at its own key under `path`:
  `{path ++ [key], :unknown_key}`, ordered by path.

  `known` is the type's keys as its value holds them, atoms in a value. A key the type
  knows stays the type's to read; one it does not is refused by name, never dropped. A key
  a reader kept at its own spelling, a string, is named as it was written.

      iex> Macaw.Layers.Document.unknown_keys(%{:title => "t", "ttle" => "x"}, [:title], [:page])
      [{[:page, "ttle"], :unknown_key}]
  """
  @spec unknown_keys(map(), [term()], Fault.path()) :: [Fault.t()]
  def unknown_keys(map, known, path \\ []) when is_map(map) and is_list(known) do
    map
    |> Map.keys()
    |> Enum.reject(&(&1 in known))
    |> Enum.map(&{path ++ [&1], :unknown_key})
    |> Fault.sort()
  end

  # The canonical encoding's version byte (spec/01 §7).
  @encoding 1

  @doc """
  The canonical digest of a value (spec/01 §7): 64 lowercase hex characters, the SHA-256
  of the value's canonical encoding. The encoding is of the term itself, never of a
  representation of it, so a value has one digest however it is written or read back.

  The encoding is a version byte, then the term, each part tagged by its type and
  self-delimiting:

  | Term | Encoding |
  |---|---|
  | an atom (`nil`, `true` and `false` too) | `a`, its name's byte size, its name in UTF-8 |
  | a binary | `b`, its byte size, its bytes |
  | a bitstring of another size | `s`, its bit size, its bits padded with zeros to a byte |
  | an integer | `i`, the byte size of its decimal spelling, that spelling |
  | a float | `f`, its IEEE 754 64-bit form |
  | a list | `l`, its length, each element |
  | a tuple | `t`, its size, each element |
  | a map | `m`, its size, each key's encoding then its value's, in the bytewise order of the keys' encodings |

  Sizes are 64-bit, and every number is big-endian. So key order never matters, and
  different terms have different encodings: `1` and `1.0`, `0.0` and `-0.0` (as under
  `===`), `:a` and `"a"`, `{:a}` and `[:a]` all differ. A struct is its map, `__struct__`
  and all, so a `DateTime` carries its zone and precision, and a struct differs from its
  bare map.

  The encoding is part of the kernel's contract: changing it changes every digest, so it
  changes only with a new major version.

  Raises `ArgumentError` for a term that is not data: a function, a PID, a reference, a
  port or an improper list.

      iex> Macaw.Layers.Document.digest(%{b: 1, a: [true, nil]}) ==
      ...>   Macaw.Layers.Document.digest(%{a: [true, nil], b: 1})
      true

      iex> Macaw.Layers.Document.digest(%{v: 1}) == Macaw.Layers.Document.digest(%{v: 1.0})
      false
  """
  @spec digest(term()) :: String.t()
  def digest(value) do
    :sha256
    |> :crypto.hash([@encoding | encode(value)])
    |> Base.encode16(case: :lower)
  end

  defp encode(atom) when is_atom(atom), do: sized(?a, Atom.to_string(atom))
  defp encode(binary) when is_binary(binary), do: sized(?b, binary)
  defp encode(int) when is_integer(int), do: sized(?i, Integer.to_string(int))
  defp encode(float) when is_float(float), do: [?f | <<float::float-64>>]

  defp encode(bits) when is_bitstring(bits) do
    size = bit_size(bits)
    [?s, <<size::64>>, <<bits::bitstring, 0::size(8 - rem(size, 8))>>]
  end

  defp encode(list) when is_list(list),
    do: [?l, <<length_of(list, list, 0)::64>> | elements(list)]

  defp encode(tuple) when is_tuple(tuple),
    do: [?t, <<tuple_size(tuple)::64>> | tuple |> Tuple.to_list() |> elements()]

  defp encode(map) when is_map(map) do
    entries =
      map
      |> :maps.to_list()
      |> Enum.map(fn {k, v} -> {IO.iodata_to_binary(encode(k)), v} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [k | encode(v)] end)

    [?m, <<map_size(map)::64>> | entries]
  end

  defp encode(other), do: not_data(other)

  defp sized(tag, bytes), do: [tag, <<byte_size(bytes)::64>> | bytes]

  defp elements(list), do: Enum.map(list, &encode/1)

  # A proper list's length; an improper tail is not data.
  defp length_of([_ | tail], list, n), do: length_of(tail, list, n + 1)
  defp length_of([], _list, n), do: n
  defp length_of(_tail, list, _n), do: not_data(list)

  defp not_data(term),
    do: raise(ArgumentError, "not data, so it has no digest: #{inspect(term)}")
end
