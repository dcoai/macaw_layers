defmodule Macaw.Layers.Tags do
  @moduledoc """
  A document type's table of `$` tags (spec/01 §6).

  A value JSON can't express is written as a **tag**: a one-key object whose key starts
  with a single `$`, such as `{"$atom": "ok"}`. Each document type has one table, declared
  in a module of its own:

      defmodule MyApp.Layout.Tags do
        use Macaw.Layers.Tags,
          live: ~w($ratio $span),
          retired: %{"$cols" => "was removed in v2: say columns"},
          renamed: %{"$tint" => "$color"}
      end

  The kernel's own tags, `$atom`, `$time` and `$version`, are live in every table.

  - **Writing:** `tag/2`, a macro in the table's module, refuses at compile time a literal
    tag the table does not list as live, so nothing is written that a reader would refuse.
  - **Reading:** `read/1` holds a parsed document to the table: a renamed tag is read under
    its new name, and an unknown or retired tag is refused at the path of its object,
    `{:unknown_tag, tag}` or `{:retired_tag, tag, why}`, never read as data.
  - **Escaping:** data may hold any key. A data key that starts with `$` is written with one
    more `$` (`escape/1`) and read back with one fewer (`unescape/1`), so `$$` never names
    a tag. The stamp `$version` at a document's root is not data, and is not escaped.

  The generic part of visualize's `Visualize.Chart.Codec.Tags`, with the table supplied by
  each type.
  """

  alias Macaw.Layers.Fault

  @kernel ~w($atom $time $version)

  @doc "The tags the kernel writes, live in every table."
  @spec kernel() :: [String.t()]
  def kernel, do: @kernel

  @doc "A table's live, retired and renamed tags."
  @callback live() :: [String.t()]
  @doc "Tags no longer written, each with what replaced it."
  @callback retired() :: %{String.t() => String.t()}
  @doc "Tags written under another name now, old => new."
  @callback renamed() :: %{String.t() => String.t()}

  defmacro __using__(opts) do
    live = Keyword.get(opts, :live, [])
    retired = Keyword.get(opts, :retired, Macro.escape(%{}))
    renamed = Keyword.get(opts, :renamed, Macro.escape(%{}))

    quote bind_quoted: [live: live, retired: retired, renamed: renamed] do
      @behaviour Macaw.Layers.Tags

      for tag <- live ++ Map.keys(retired) ++ Map.keys(renamed) do
        unless match?("$" <> _, tag) and not match?("$$" <> _, tag) do
          raise ArgumentError, "a tag starts with a single $, got: #{inspect(tag)}"
        end
      end

      @tags_live Enum.uniq(Macaw.Layers.Tags.kernel() ++ live)
      @tags_retired retired
      @tags_renamed renamed

      @impl true
      def live, do: @tags_live
      @impl true
      def retired, do: @tags_retired
      @impl true
      def renamed, do: @tags_renamed

      @doc "The parsed document held to this table (`Macaw.Layers.Tags.read/2`)."
      def read(term), do: Macaw.Layers.Tags.read(term, __MODULE__)

      @doc """
      The one-key object of a tag. A literal tag the table does not list as live is a
      compile error; a computed one must be live when it is called.
      """
      defmacro tag(name, payload) when is_binary(name) do
        if name not in @tags_live do
          raise CompileError,
            file: __CALLER__.file,
            line: __CALLER__.line,
            description: "#{inspect(name)} is not a live tag of #{inspect(__MODULE__)}"
        end

        quote do: %{unquote(name) => unquote(payload)}
      end

      defmacro tag(name, payload) do
        module = __MODULE__
        quote do: Macaw.Layers.Tags.tag!(unquote(module), unquote(name), unquote(payload))
      end
    end
  end

  @doc "The one-key object of a live tag of `table`; raises `ArgumentError` for any other."
  @spec tag!(module(), String.t(), term()) :: map()
  def tag!(table, name, payload) do
    if name in table.live(),
      do: %{name => payload},
      else: raise(ArgumentError, "#{inspect(name)} is not a live tag of #{inspect(table)}")
  end

  @doc """
  A data key as a document writes it: one that starts with `$` gets one more.

      iex> Macaw.Layers.Tags.escape("$price")
      "$$price"
  """
  @spec escape(String.t()) :: String.t()
  def escape("$" <> _ = key), do: "$" <> key
  def escape(key) when is_binary(key), do: key

  @doc """
  A data key as a document holds it, read: one that starts with `$$` loses one.

      iex> Macaw.Layers.Tags.unescape("$$price")
      "$price"
  """
  @spec unescape(String.t()) :: String.t()
  def unescape("$$" <> rest), do: "$" <> rest
  def unescape(key) when is_binary(key), do: key

  @doc """
  The parsed document held to `table`: `{:ok, term}` with every renamed tag under its new
  name, or every unknown or retired tag refused at its object's path, ordered by path.
  Data keys are left as written; `unescape/1` reads them.
  """
  @spec read(term(), module()) :: {:ok, term()} | {:error, [Fault.t(), ...]}
  def read(term, table) do
    case walk(term, [], table) do
      {term, []} -> {:ok, term}
      {_term, faults} -> {:error, Fault.sort(faults)}
    end
  end

  defp walk(map, path, table) when is_map(map) and map_size(map) == 1 do
    [{key, value}] = Map.to_list(map)

    case tag_of(key) do
      nil -> data(map, path, table)
      tag -> tagged(tag, value, map, path, table)
    end
  end

  defp walk(map, path, table) when is_map(map), do: data(map, path, table)

  defp walk(list, path, table) when is_list(list) do
    {items, faults} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {item, i} -> walk(item, path ++ [i], table) end)
      |> Enum.unzip()

    {items, Enum.concat(faults)}
  end

  defp walk(leaf, _path, _table), do: {leaf, []}

  defp tagged(tag, value, map, path, table) do
    cond do
      tag in table.live() ->
        {value, faults} = walk(value, path ++ [tag], table)
        {%{tag => value}, faults}

      new = table.renamed()[tag] ->
        tagged(new, value, map, path, table)

      why = table.retired()[tag] ->
        {map, [{path, {:retired_tag, tag, why}}]}

      true ->
        {map, [{path, {:unknown_tag, tag}}]}
    end
  end

  defp data(map, path, table) do
    {pairs, faults} =
      map
      |> Enum.map(fn {key, value} ->
        {value, faults} = walk(value, path ++ [key], table)
        {{key, value}, faults}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(faults)}
  end

  # A key that starts with a single `$` names a tag; `$$` is an escaped data key.
  defp tag_of("$$" <> _), do: nil
  defp tag_of("$" <> _ = key), do: key
  defp tag_of(_key), do: nil
end
