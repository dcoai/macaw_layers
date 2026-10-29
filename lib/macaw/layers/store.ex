defmodule Macaw.Layers.Store do
  @moduledoc """
  Where documents live (spec/03 §1): the store behavior, the assign's functions, typed ids
  (§2) and import as a relocation (§3.3).

  A store holds **entries**, `%{id, name, fragment}`, of the fragment types it was given
  (spec/02 §1). An entry's kind is derived from its fragment, never stored; its name is an
  attribute, never an identity. A store is reached through an **assign**, `{module,
  context}` or a bare module, so every call carries who is acting and from where.

      Store.put({Macaw.Layers.Store.Memory, agent}, %{id: nil, name: "Styles:thick", fragment: %{style: %{width: 3}}})
      #=> {:ok, {:style, 1}}

  Ported from visualize's `Visualize.Chart.Builder.Store`, its callbacks answering `{:ok, …}`
  or `{:error, …}` as every Macaw contract does.
  """

  alias Macaw.Layers.{Bundle, Fault, Fragment, Vocabulary}

  @typedoc "A store's module and its context, or a bare module, whose context is `nil`."
  @type assign :: module() | {module(), term()}
  @typedoc "An id: a kind of the store's types and a positive integer the store issued."
  @type id :: {atom(), pos_integer()}
  @typedoc "A stored fragment: its id, `nil` before the store issues one, and its name."
  @type entry :: %{id: id() | nil, name: String.t(), fragment: map()}
  @typedoc "What a picker lists."
  @type summary :: %{id: id(), name: String.t(), kind: atom()}
  @typedoc "What an import answers: the `old => new` table, and each reference outside the bundle."
  @type imported :: %{ids: %{id() => id()}, outside: [{id(), Fault.path()}]}

  @doc "The fragment types the store holds."
  @callback types(context :: term()) :: [module()]
  @doc "Every entry's summary."
  @callback list(context :: term()) :: {:ok, [summary()]} | {:error, term()}
  @doc "The entry of an id."
  @callback get(id(), context :: term()) :: {:ok, entry()} | {:error, :not_found | term()}
  @doc "An entry stored: a new id issued to one without, a held one replaced."
  @callback put(entry(), context :: term()) :: {:ok, id()} | {:error, term()}
  @doc "An entry removed."
  @callback delete(id(), context :: term()) :: :ok | {:error, term()}
  @doc "A bundle relocated into the store, whole or not at all (§3.3)."
  @callback import(Bundle.t(), context :: term()) ::
              {:ok, imported()} | {:error, [Fault.t(), ...]}

  @doc "The assign as `{module, context}`; a bare module has a `nil` context."
  @spec split(assign()) :: {module(), term()}
  def split({module, context}) when is_atom(module), do: {module, context}
  def split(module) when is_atom(module), do: {module, nil}

  @doc "The store's types."
  @spec types(assign()) :: [module()]
  def types(assign), do: call(assign, :types, [])

  @doc "Every entry's summary."
  @spec list(assign()) :: {:ok, [summary()]} | {:error, term()}
  def list(assign), do: call(assign, :list, [])

  @doc "The entry of an id."
  @spec get(assign(), id()) :: {:ok, entry()} | {:error, term()}
  def get(assign, id), do: call(assign, :get, [id])

  @doc "An entry stored."
  @spec put(assign(), entry()) :: {:ok, id()} | {:error, term()}
  def put(assign, entry), do: call(assign, :put, [entry])

  @doc "An entry removed."
  @spec delete(assign(), id()) :: :ok | {:error, term()}
  def delete(assign, id), do: call(assign, :delete, [id])

  @doc "A bundle imported."
  @spec import(assign(), Bundle.t()) :: {:ok, imported()} | {:error, [Fault.t(), ...]}
  def import(assign, bundle), do: call(assign, :import, [bundle])

  defp call(assign, function, args) do
    {module, context} = split(assign)
    apply(module, function, args ++ [context])
  end

  # -- the types and their kinds -------------------------------------------------------------

  @doc """
  The types, checked when a store is configured: each a fragment type, and no kind
  declared by two of them. Raises `ArgumentError` naming both types and the kind.
  """
  @spec check_types!([module()]) :: [module()]
  def check_types!(types) when is_list(types) do
    Enum.reduce(types, %{}, fn type, seen ->
      Enum.reduce(type.kinds(), seen, fn kind, seen ->
        case Map.fetch(seen, kind) do
          {:ok, other} ->
            raise ArgumentError,
                  "#{inspect(other)} and #{inspect(type)} both declare the kind #{inspect(kind)}"

          :error ->
            Map.put(seen, kind, type)
        end
      end)
    end)

    types
  end

  @doc "Every kind of the store's types (an assign, or the types themselves), sorted."
  @spec kinds(assign() | [module()]) :: [atom()]
  def kinds(types) when is_list(types), do: types |> Enum.flat_map(& &1.kinds()) |> Enum.sort()
  def kinds(assign), do: assign |> types() |> kinds()

  @doc "The type a kind belongs to, or `nil`."
  @spec type_of(assign() | [module()], atom()) :: module() | nil
  def type_of(types, kind) when is_list(types), do: Enum.find(types, &(kind in &1.kinds()))
  def type_of(assign, kind), do: assign |> types() |> type_of(kind)

  @doc """
  `{type, kind}` of the first of the store's types that derives the fragment a kind
  (spec/02 §6.1), or `nil`: a fragment about more than one thing is not storable.
  """
  @spec kind(assign() | [module()], map()) :: {module(), atom()} | nil
  def kind(types, fragment) when is_list(types) do
    Enum.find_value(types, fn type ->
      case Fragment.kind(type, fragment) do
        nil -> nil
        kind -> {type, kind}
      end
    end)
  end

  def kind(assign, fragment), do: assign |> types() |> kind(fragment)

  @doc """
  A name's filing, `<group>:<sub-group>:<name>`: the segments before the last, empty ones
  dropped, and the last. Nothing references it.

      iex> Macaw.Layers.Store.group("Styles::thick")
      {["Styles"], "thick"}
  """
  @spec group(String.t()) :: {[String.t()], String.t()}
  def group(name) when is_binary(name) do
    {groups, [last]} = name |> String.split(":") |> Enum.split(-1)
    {Enum.reject(groups, &(&1 == "")), last}
  end

  # -- ids ---------------------------------------------------------------------------------

  @doc """
  An id as one string, for the DOM and the wire.

      iex> Macaw.Layers.Store.encode_id({:style, 11})
      "style:11"
  """
  @spec encode_id(id()) :: String.t()
  def encode_id({kind, n}) when is_atom(kind) and is_integer(n) and n > 0, do: "#{kind}:#{n}"

  @doc """
  The id a string spells, its kind matched against `kinds` by its string, so no atom is
  made from a client's string: `{:ok, id}` or `:error`.

      iex> Macaw.Layers.Store.decode_id([:style, :mark], "style:11")
      {:ok, {:style, 11}}
      iex> Macaw.Layers.Store.decode_id([:style, :mark], "widget:11")
      :error
  """
  @spec decode_id([atom()], term()) :: {:ok, id()} | :error
  def decode_id(kinds, string) when is_list(kinds) and is_binary(string) do
    with [spelling, digits] <- String.split(string, ":", parts: 2),
         {:ok, kind} <- Vocabulary.fetch(Vocabulary.table(kinds), spelling),
         {n, ""} when n > 0 <- Integer.parse(digits) do
      {:ok, {kind, n}}
    else
      _ -> :error
    end
  end

  def decode_id(_kinds, _other), do: :error

  @doc """
  A reference held to the kind its site takes, before it is resolved (§2): `:ok`, or
  `{:error, {:ref_kind, wanted, given}}` for an id of another kind, for a type's reader to
  report at the site's path.
  """
  @spec ref_kind(id(), atom()) :: :ok | {:error, {:ref_kind, atom(), atom()}}
  def ref_kind({wanted, _n}, wanted), do: :ok
  def ref_kind({given, _n}, wanted), do: {:error, {:ref_kind, wanted, given}}

  # -- import as a relocation --------------------------------------------------------------

  @doc """
  A bundle imported through the store's own `put/2` (§3.3): every check first, then new
  ids issued, then every reference rewritten through one table and each entry put again.

  The checks: the bundle judged as a term (`Macaw.Layers.Bundle.check/2`), its envelope
  and each entry's kind against the store's types, with no form written or read back, and
  the host's `check:` over each entry. A fault anywhere writes nothing; every fault is
  reported at `[:entries, i | path]`.

  - `check:` — `(entry -> :ok | {:error, [fault]})`, the host's own check, such as names
    its registry does not know;
  - `transaction:` — a function given `run`, which it calls as `run.(state, put)` inside its
    own transaction, `put.(entry, state)` answering `{:ok, id, state}` or `{:error, reason}`;
    `run` answers `{:ok, imported, state}` or `{:error, faults}`, and the transaction
    function `{:ok, imported}` or `{:error, faults}`, committing only the first. Without it,
    entries are written through the store's `put/2`, which is whole only where those writes
    cannot fail.

  A reference to an id outside the bundle is left as it is and reported in `outside` by the
  entry that holds it: it resolves as a mask (spec/02 §7).
  """
  @spec relocate(assign(), Bundle.t(), keyword()) ::
          {:ok, imported()} | {:error, [Fault.t(), ...]}
  def relocate(assign, %Bundle{} = bundle, opts \\ []) do
    types = types(assign)

    with {:ok, bundle} <- Bundle.check(bundle, types),
         :ok <- host_check(bundle.entries, Keyword.get(opts, :check)) do
      run = fn state, put -> write(types, bundle.entries, state, put) end

      case Keyword.fetch(opts, :transaction) do
        {:ok, transaction} -> transaction.(run)
        :error -> direct(assign, run)
      end
    end
  end

  defp host_check(_entries, nil), do: :ok

  defp host_check(entries, check) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, i} ->
      case check.(entry) do
        :ok ->
          []

        {:error, faults} ->
          Enum.map(faults, fn {path, reason} -> {[:entries, i | path], reason} end)
      end
    end)
    |> case do
      [] -> :ok
      faults -> {:error, Fault.sort(faults)}
    end
  end

  defp direct(assign, run) do
    put = fn entry, nil ->
      case put(assign, entry) do
        {:ok, id} -> {:ok, id, nil}
        {:error, reason} -> {:error, reason}
      end
    end

    with {:ok, imported, nil} <- run.(nil, put), do: {:ok, imported}
  end

  defp write(types, entries, state, put) do
    indexed = Enum.with_index(entries)

    with {:ok, table, state} <- issue(indexed, state, put) do
      rewrite(types, indexed, table, state, put)
    end
  end

  defp issue(indexed, state, put) do
    Enum.reduce_while(indexed, {:ok, %{}, state}, fn {entry, i}, {:ok, table, state} ->
      case put.(%{entry | id: nil}, state) do
        {:ok, new, state} -> {:cont, {:ok, Map.put(table, entry.id, new), state}}
        {:error, reason} -> {:halt, {:error, [{[:entries, i], reason}]}}
      end
    end)
  end

  defp rewrite(types, indexed, table, state, put) do
    Enum.reduce_while(indexed, {:ok, [], state}, fn {entry, i}, {:ok, outside, state} ->
      {kind, _n} = entry.id
      {fragment, missed} = Fragment.relocate(type_of(types, kind), entry.fragment, table)

      case put.(%{entry | id: Map.fetch!(table, entry.id), fragment: fragment}, state) do
        {:ok, _id, state} ->
          {:cont, {:ok, outside ++ Enum.map(missed, &{&1, [:entries, i]}), state}}

        {:error, reason} ->
          {:halt, {:error, [{[:entries, i], reason}]}}
      end
    end)
    |> case do
      {:ok, outside, state} -> {:ok, %{ids: table, outside: outside}, state}
      {:error, _faults} = error -> error
    end
  end
end
