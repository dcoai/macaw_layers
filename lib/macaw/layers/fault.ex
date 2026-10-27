defmodule Macaw.Layers.Fault do
  @moduledoc """
  A fault in a document, `{path, reason}`, and the one formatter that words it (spec/01 §3).

  The path runs from the document's root: atoms or strings for keys, non-negative integers
  for list positions. A key the document type does not know stays at its own spelling, a
  string. Every fault is reported, never just the first, ordered by path (`sort/1`).

  `format/2` words a fault as `path: words`. The kernel words its own reasons; any other is
  the document type's, given as `words:`:

      iex> Macaw.Layers.Fault.format({[:frames, "main", "wdth"], :unknown_key})
      "frames.main.wdth: is not a key of this node"
      iex> Macaw.Layers.Fault.format({[], {:newer_schema, 4, 3}}, root: "design")
      "design: needs schema v4, this is v3"

  The formatter is visualize's `Visualize.Chart.Validator.format/1` and the generic part of
  its wording, with the root's name and the type's own wording as options.
  """

  @typedoc "Where a fault is: keys and list positions from the document's root."
  @type path :: [atom() | String.t() | non_neg_integer()]

  @typedoc "A fault: where, and why."
  @type t :: {path(), reason :: term()}

  @typedoc "`format/2`'s options."
  @type option :: {:root, String.t()} | {:words, (term() -> String.t())}

  @doc "Faults ordered by path, keeping the given order of faults at one path."
  @spec sort([t()]) :: [t()]
  def sort(faults) when is_list(faults), do: Enum.sort_by(faults, &elem(&1, 0))

  @doc """
  A fault as `path: words`.

  Options:
  - `root:` the name of the empty path, `"document"` by default;
  - `words:` a function that words the reasons the kernel does not. Without one, such a
    reason is shown with `inspect/1`.
  """
  @spec format(t(), [option()]) :: String.t()
  def format({path, reason}, opts \\ []) do
    "#{format_path(path, opts)}: #{words(reason, Keyword.get(opts, :words, &inspect/1))}"
  end

  @doc """
  A path as a person reads it: keys joined by `.`, an index as `[i]`, and the empty path
  as the root's name.

      iex> Macaw.Layers.Fault.format_path([:marks, 0, :channels])
      "marks[0].channels"
      iex> Macaw.Layers.Fault.format_path([])
      "document"
  """
  @spec format_path(path(), [option()]) :: String.t()
  def format_path(path, opts \\ [])
  def format_path([], opts), do: Keyword.get(opts, :root, "document")

  def format_path(path, _opts) do
    Enum.reduce(path, "", fn
      i, acc when is_integer(i) -> "#{acc}[#{i}]"
      k, "" -> "#{k}"
      k, acc -> "#{acc}.#{k}"
    end)
  end

  # The kernel's reasons first, so each is worded one way whatever the document type; any
  # other reason, a compound type with a part the kernel does not word included, whole to
  # the type's function.
  defp words(reason, type_words) do
    case kernel_words(reason) do
      {:ok, words} -> words
      :error -> type_words.(reason)
    end
  end

  defp kernel_words(:required), do: {:ok, "is required"}
  defp kernel_words(:unknown_key), do: {:ok, "is not a key of this node"}

  defp kernel_words({:type, type}) do
    case type_words(type) do
      {:ok, words} -> {:ok, "must be #{words}"}
      :error -> :error
    end
  end

  defp kernel_words({:enum, allowed}) when is_list(allowed),
    do: {:ok, "must be one of #{list(allowed)}"}

  defp kernel_words({:newer_schema, needs, this}),
    do: {:ok, "needs schema v#{needs}, this is v#{this}"}

  defp kernel_words({:limit, :bytes, max, given}),
    do: {:ok, "is #{given} bytes; the limit bytes is #{max}"}

  defp kernel_words({:limit, :depth, max, given}),
    do: {:ok, "is nested #{given} deep; the limit depth is #{max}"}

  defp kernel_words({:limit, :items, max, given}),
    do: {:ok, "holds #{given} items; the limit items is #{max}"}

  defp kernel_words({:json, message}), do: {:ok, "JSON does not parse: #{message}"}

  defp kernel_words({:unknown_tag, tag}),
    do: {:ok, "#{inspect(tag)} is not a tag this document reads"}

  defp kernel_words({:retired_tag, tag, why}), do: {:ok, "#{inspect(tag)} #{why}"}
  defp kernel_words(_reason), do: :error

  defp type_words(:string), do: {:ok, "a string"}
  defp type_words(:name), do: {:ok, "a name: a non-empty string"}
  defp type_words(:integer), do: {:ok, "an integer"}
  defp type_words(:non_neg_integer), do: {:ok, "a non-negative integer"}
  defp type_words(:pos_integer), do: {:ok, "a positive integer"}
  defp type_words(:number), do: {:ok, "a number"}
  defp type_words(:positive), do: {:ok, "a positive number"}
  defp type_words(:boolean), do: {:ok, "true or false"}
  defp type_words(:map), do: {:ok, "a map"}
  defp type_words(:list), do: {:ok, "a list"}
  defp type_words({:enum, allowed}) when is_list(allowed), do: {:ok, "one of #{list(allowed)}"}
  defp type_words({:list, t}), do: part(t, &"a list of #{&1}")
  defp type_words({:map, t}), do: part(t, &"a map from names to #{&1}")
  defp type_words({:node, kind}), do: {:ok, "a #{kind} node"}

  defp type_words({:one_of, types}) when is_list(types) do
    Enum.reduce_while(types, {:ok, []}, fn type, {:ok, acc} ->
      case type_words(type) do
        {:ok, words} -> {:cont, {:ok, [words | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, words} -> {:ok, words |> Enum.reverse() |> Enum.join(" or ")}
      :error -> :error
    end
  end

  defp type_words(_type), do: :error

  defp part(type, wrap) do
    case type_words(type) do
      {:ok, words} -> {:ok, wrap.(words)}
      :error -> :error
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &inspect/1)
end
