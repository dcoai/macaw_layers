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

  @doc """
  The canonical digest of a document's map form (`Macaw.Layers.Form.to_map/2`): 64
  lowercase hex characters, the SHA-256 of its canonical encoding (spec/01 §7).

  The encoding is JSON with objects' keys sorted bytewise, no insignificant whitespace,
  each string as `JSON` encodes it, an integer in decimal, and a float in its shortest
  spelling that reads back as the same float. Reordering keys, at any depth, does not
  change the digest; a document and its JSON round trip have the same one. The encoding is
  part of the kernel's contract: changing it changes every digest, so it changes only with
  a new major version.

  Raises `ArgumentError` for a term that is not a map form: an atom key, a tuple, any
  value JSON has no form for. Write the value's map form first.

      iex> Macaw.Layers.Document.digest(%{"b" => 1, "a" => [true, nil]}) ==
      ...>   Macaw.Layers.Document.digest(%{"a" => [true, nil], "b" => 1})
      true
  """
  @spec digest(map()) :: String.t()
  def digest(map) when is_map(map) and not is_struct(map) do
    :sha256
    |> :crypto.hash(canonical(map))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) and not is_struct(map) do
    pairs =
      map
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {k, v}
        {k, _v} -> raise ArgumentError, "a map form's keys are strings, got: #{inspect(k)}"
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, canonical(v)] end)

    [?{, Enum.intersperse(pairs, ?,), ?}]
  end

  defp canonical(list) when is_list(list),
    do: [?[, list |> Enum.map(&canonical/1) |> Enum.intersperse(?,), ?]]

  defp canonical(s) when is_binary(s), do: JSON.encode!(s)
  defp canonical(i) when is_integer(i), do: Integer.to_string(i)
  defp canonical(f) when is_float(f), do: :erlang.float_to_binary(f, [:short])
  defp canonical(true), do: "true"
  defp canonical(false), do: "false"
  defp canonical(nil), do: "null"

  defp canonical(other),
    do:
      raise(ArgumentError, "not a map form's value: #{inspect(other)}; write the map form first")
end
