defmodule Macaw.Layers.Use do
  @moduledoc """
  A use site (spec/02 §7): a fragment used at a position, resolved
  `ref → local → mask → bind → stack`.

      %Macaw.Layers.Use{
        id:     {:use, 7},          # the site's own identity, the same site wherever it sits
        ref:    {:style, 11},       # which fragment: an id, a local key, or nil
        mask:   [["stroke"]],       # paths removed here, so a lower layer shows through; or :all
        vars:   %{"color" => …},    # what the fragment's variables mean here
        local:  %{opacity: 0.8},    # what is added or overridden here
        key:    "series",           # the name a name-keyed kind is declared under, here
        origin: nil                 # the entry an unlocked site was copied from
      }

  The site is a struct, so it is a leaf of every walk but the two id walks
  (`Macaw.Layers.Fragment.refs/2`, `relocate/3`), which read its parts by name. Mask and
  bind run after local, so both speak for everything the site contributes; a mask of
  `:all` removes the whole site, its local included. A reference the fetch cannot find is
  transparent: the site is its local alone, and the miss is reported.

  Ported from visualize's `Visualize.Chart.Use`.

      iex> alias Macaw.Layers.Use
      iex> Use.new({:style, 2}, [Use.new({:style, 1})]).id
      {:use, 2}
      iex> Use.mask(%{frames: %{"main" => %{legend: %{}, margin: %{}}}}, [[:frames, "main", :margin]])
      %{frames: %{"main" => %{legend: %{}}}}
  """

  alias Macaw.Layers.{Fragment, Names, Var}

  @enforce_keys [:id]
  defstruct [:id, ref: nil, mask: [], vars: %{}, local: %{}, key: nil, origin: nil]

  @typedoc "A path into a fragment: its keys from the root, or a bare name for one key."
  @type path :: [term()] | atom() | String.t()

  @type t :: %__MODULE__{
          id: {:use, pos_integer()},
          ref: term(),
          mask: [path()] | :all,
          vars: map(),
          local: map(),
          key: String.t() | nil,
          origin: term()
        }

  @doc "A use of `ref` with id `{:use, 1}` and the empty parts."
  @spec new(term()) :: t()
  def new(ref), do: new(ref, [])

  @doc """
  A use of `ref` with a fresh id, one more than the highest among `siblings`, the ids of an
  inline composite's sites among them, so ids are unique across a whole tree.
  """
  @spec new(term(), [t()]) :: t()
  def new(ref, siblings) when is_list(siblings) do
    highest = siblings |> Enum.flat_map(&ids/1) |> Enum.max(fn -> 0 end)
    %__MODULE__{id: {:use, highest + 1}, ref: ref}
  end

  defp ids(%__MODULE__{id: {:use, n}, ref: nil, local: %{composite: %{uses: uses}}})
       when is_list(uses),
       do: [n | Enum.flat_map(uses, &ids/1)]

  defp ids(%__MODULE__{id: {:use, n}}), do: [n]

  @doc """
  The fragment with each path removed (spec/02 §4): a path is the keys from the root, read
  by spelling, or a bare name for one key; a node it empties is kept as an empty map; a
  path that names nothing removes nothing; `:all` removes everything.
  """
  @spec mask(map(), [path()] | :all) :: map()
  def mask(_fragment, :all), do: %{}

  def mask(fragment, paths) when is_list(paths),
    do: Enum.reduce(paths, fragment, &drop(&2, path(&1)))

  defp path(path) when is_list(path), do: path
  defp path(name), do: [name]

  defp drop(fragment, [key]) when is_map(fragment) and not is_struct(fragment) do
    case Names.key(fragment, key) do
      {:ok, found} -> Map.delete(fragment, found)
      :error -> fragment
    end
  end

  defp drop(fragment, [key | rest]) when is_map(fragment) and not is_struct(fragment) do
    case Names.key(fragment, key) do
      {:ok, found} -> Map.put(fragment, found, drop(Map.fetch!(fragment, found), rest))
      :error -> fragment
    end
  end

  defp drop(list, [index | rest]) when is_list(list) and is_integer(index) and index >= 0 do
    if index < length(list), do: List.update_at(list, index, &drop(&1, rest)), else: list
  end

  defp drop(other, _path), do: other

  @doc "`Macaw.Layers.Var.bind/2`: the fragment's variables substituted."
  @spec bind(term(), map()) :: term()
  defdelegate bind(fragment, vars), to: Var

  @doc """
  The site over a body already in hand: its local cascaded over the body, its mask over
  the result, its variables bound over all of it — everything `resolve/3` does after the
  fetch. A mask of `:all` is the whole site removed.
  """
  @spec over(module(), t(), map()) :: map()
  def over(_type, %__MODULE__{mask: :all}, _body), do: %{}

  def over(type, %__MODULE__{mask: mask, vars: vars, local: local}, body) do
    type
    |> Fragment.stack(body, local)
    |> mask(mask)
    |> then(&Var.bind(type, &1, vars))
  end

  @doc """
  One site through `fetch`, a function from an id to `{:ok, fragment}` or `:error`:
  `{:ok, contribution}`, or `{:missing, ref, contribution}` where the ref was not found,
  the contribution then the local alone, masked and bound. A `nil` ref is an inline site.
  """
  @spec resolve(module(), t(), (term() -> {:ok, map()} | :error)) ::
          {:ok, map()} | {:missing, term(), map()}
  def resolve(type, %__MODULE__{ref: nil} = use, _fetch), do: {:ok, over(type, use, %{})}

  def resolve(type, %__MODULE__{ref: ref} = use, fetch) do
    case fetch.(ref) do
      {:ok, body} -> {:ok, over(type, use, body)}
      :error -> {:missing, ref, over(type, use, %{})}
    end
  end
end
