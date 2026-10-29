defmodule Macaw.Layers.Document do
  @moduledoc """
  Reading a document through the gates, in order (spec/01 §5).

  A document type implements this behavior and `Macaw.Layers.Version`: its version line
  and steps, and `c:validate/1`, which judges a document at the current version. Whatever
  the document came from (a file, a database, an object store), it is read the same way,
  by `read/3`, and nothing in it is evaluated:

  1. **bytes**: an encoded document longer than the `bytes` limit is refused;
  2. **decode** with the `depth` and `items` limits, by `Macaw.Layers.Scan`, which stops at
     a limit before any value is built; only then is it decoded, with Elixir's `JSON`;
  3. **version**: a newer stamp is refused by name before anything else is read;
  4. **migrate**, step by step;
  5. **validate**, and count `depth` and `items` again, since a migration can grow a
     document.

  Faults from one gate stop the gates after it. Within the last, the type's faults and the
  recount's are all reported, ordered by path.
  """

  alias Macaw.Layers.{Fault, Limits, Scan, Version}

  @doc """
  `:ok`, or every fault of a document at the type's current version. Unknown keys are
  refused by name (see `unknown_keys/3`).
  """
  @callback validate(document :: map()) :: :ok | {:error, [Fault.t(), ...]}

  @typedoc "`read/3`'s options."
  @type option :: {:limits, keyword() | map()}

  @doc """
  The document, read through every gate, at the type's current version: `{:ok, map}`, or
  every fault of the first gate that refuses it.

  `input` is the JSON form, a binary, or the map form, which skips the bytes gate and is
  walked for `depth` and `items` instead of scanned. `type` implements this behavior and
  `Macaw.Layers.Version`. `limits:` tightens the limits, as `Macaw.Layers.Limits.new/1`
  takes them.
  """
  @spec read(binary() | map(), module(), [option()]) :: {:ok, map()} | {:error, [Fault.t(), ...]}
  def read(input, type, opts \\ []) when is_atom(type) do
    limits = Limits.new(Keyword.get(opts, :limits, []))

    with {:ok, document} <- decode(input, limits),
         {:ok, document} <- Version.migrate(document, type) do
      validate(document, type, limits)
    end
  end

  defp decode(json, limits) when is_binary(json) do
    with :ok <- bytes(json, limits),
         :ok <- scan(json, limits),
         {:ok, term} <- json_decode(json) do
      object(term)
    end
  end

  defp decode(map, limits) when is_map(map) and not is_struct(map) do
    case Limits.structure(map, limits) do
      [] -> {:ok, map}
      faults -> {:error, faults}
    end
  end

  defp decode(_other, _limits), do: {:error, [{[], {:type, :map}}]}

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

  defp validate(document, type, limits) do
    faults =
      case type.validate(document) do
        :ok -> []
        {:error, [_ | _] = faults} -> faults
      end

    case faults ++ Limits.structure(document, limits) do
      [] -> {:ok, document}
      faults -> {:error, Fault.sort(faults)}
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

  @doc """
  The faults of `map`'s keys that are not among `known`, each at its own spelling under
  `path`: `{path ++ [key], :unknown_key}`, ordered by path.

  `known` is the type's keys as the document spells them, strings. A key the type knows
  stays the type's to read; one it does not is refused by name, never dropped.

      iex> Macaw.Layers.Document.unknown_keys(%{"title" => "t", "ttle" => "x"}, ["title"], [:page])
      [{[:page, "ttle"], :unknown_key}]
  """
  @spec unknown_keys(map(), [String.t()], Fault.path()) :: [Fault.t()]
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
