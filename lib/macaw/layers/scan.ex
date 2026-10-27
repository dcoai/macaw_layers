defmodule Macaw.Layers.Scan do
  @moduledoc """
  The `depth` and `items` limits checked on encoded JSON, before it is decoded
  (spec/01 §5, gate 2).

  A decoder that builds the whole value first has already paid for it when a limit is
  found: a document nested a million deep, or holding a million entries, is in memory
  before anything refuses it. The scan walks the bytes instead, tracking strings and their
  escapes, the nesting and the entries of each object and array, and **stops at the first
  limit it passes.** It builds no value: what it holds is one frame per open object or
  array, never more than the depth limit, and the key of each open object, so the fault
  can name its path.

  The scan is not a validator. It reads well-formed JSON exactly, and on malformed input it
  never fails: whatever it can't make sense of, it leaves to the decoder, which reports it.
  A key that appears twice in one object is counted twice, as the document holds it twice.
  """

  alias Macaw.Layers.{Fault, Limits}

  @doc """
  `:ok`, or the first `depth` or `items` limit the encoded document passes, at its path.

  An object or array over the items limit is reported once it holds one entry more than
  the limit, as `{path, {:limit, :items, max, max + 1}}`; a container beyond the depth
  limit as `{path, {:limit, :depth, max, max + 1}}`.
  """
  @spec scan(binary(), Limits.t()) :: :ok | {:error, Fault.t()}
  def scan(json, %{depth: _, items: _} = limits) when is_binary(json),
    do: walk(json, [], 0, limits)

  # A frame is an open container: `{:array, entries, expecting_value?}` or
  # `{:object, entries, current_key, expecting_key?}`. The innermost is the list's head.

  defp walk(<<>>, _stack, _depth, _limits), do: :ok

  defp walk(<<c, rest::binary>>, stack, depth, limits) when c in ~c" \t\r\n:",
    do: walk(rest, stack, depth, limits)

  defp walk(<<?", rest::binary>>, stack, depth, limits) do
    len = string_length(rest, 0)

    case rest do
      <<raw::binary-size(^len), ?", after_string::binary>> ->
        case string(stack, raw, limits) do
          {:ok, stack} -> walk(after_string, stack, depth, limits)
          {:error, _} = fault -> fault
        end

      # Unterminated: the decoder's to report.
      _ ->
        :ok
    end
  end

  defp walk(<<c, rest::binary>>, stack, depth, limits) when c in ~c"{[" do
    with {:ok, stack} <- value(stack, limits) do
      if depth + 1 > limits.depth do
        {:error, {path(stack), {:limit, :depth, limits.depth, depth + 1}}}
      else
        frame = if c == ?{, do: {:object, 0, nil, true}, else: {:array, 0, true}
        walk(rest, [frame | stack], depth + 1, limits)
      end
    end
  end

  defp walk(<<c, rest::binary>>, [_ | stack], depth, limits) when c in ~c"}]",
    do: walk(rest, stack, depth - 1, limits)

  # A closer with nothing open: the decoder's to report.
  defp walk(<<c, _rest::binary>>, [], _depth, _limits) when c in ~c"}]", do: :ok

  defp walk(<<?,, rest::binary>>, [{:array, n, _} | up], depth, limits),
    do: walk(rest, [{:array, n, true} | up], depth, limits)

  defp walk(<<?,, rest::binary>>, [{:object, n, key, _} | up], depth, limits),
    do: walk(rest, [{:object, n, key, true} | up], depth, limits)

  defp walk(<<?,, rest::binary>>, [], depth, limits), do: walk(rest, [], depth, limits)

  # A number, `true`, `false` or `null`: one value, then its bytes.
  defp walk(<<_c, rest::binary>>, stack, depth, limits) do
    with {:ok, stack} <- value(stack, limits) do
      walk(scalar(rest), stack, depth, limits)
    end
  end

  # A string is a key where an object expects one, else a value.
  defp string([{:object, n, _key, true} | up], raw, limits) do
    if n + 1 > limits.items do
      {:error, {path(up), {:limit, :items, limits.items, n + 1}}}
    else
      {:ok, [{:object, n + 1, key(raw), false} | up]}
    end
  end

  defp string(stack, _raw, limits), do: value(stack, limits)

  # A value counts as an entry of an array that expects one.
  defp value([{:array, n, true} | up], limits) do
    if n + 1 > limits.items do
      {:error, {path(up), {:limit, :items, limits.items, n + 1}}}
    else
      {:ok, [{:array, n + 1, false} | up]}
    end
  end

  defp value(stack, _limits), do: {:ok, stack}

  # The path to the innermost open container's current entry: an array's index, an
  # object's key, from the root.
  defp path(stack) do
    stack
    |> Enum.reverse()
    |> Enum.map(fn
      {:array, n, _} -> n - 1
      {:object, _n, key, _} -> key
    end)
  end

  # The bytes of a string up to its closing quote, escapes skipped.
  defp string_length(<<?\\, _escaped, rest::binary>>, len), do: string_length(rest, len + 2)
  defp string_length(<<?", _rest::binary>>, len), do: len
  defp string_length(<<_c, rest::binary>>, len), do: string_length(rest, len + 1)
  defp string_length(<<>>, len), do: len + 1

  # A key as the document spells it, its escapes read; as written when they don't read.
  defp key(raw) do
    case JSON.decode(<<?", raw::binary, ?">>) do
      {:ok, key} when is_binary(key) -> key
      _ -> raw
    end
  end

  defp scalar(<<c, rest::binary>>) when c in ?0..?9 or c in ?a..?z or c in ?A..?Z or c in ~c"+-.",
    do: scalar(rest)

  defp scalar(rest), do: rest
end
