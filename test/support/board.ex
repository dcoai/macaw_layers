defmodule Macaw.Layers.Test.Board do
  @moduledoc false
  # `Design` with the composite's hooks (spec/02 §8.1, §8.2), as visualize's composites
  # use them: a composite node may carry `defaults`, which `scope/3` puts under each mark
  # its sites place, and a keyed site whose contribution has no kind lands its one frame as
  # the site's key through `place_whole/2` (visualize #384, the gauge composite).
  @behaviour Macaw.Layers.Fragment
  @behaviour Macaw.Layers.Form

  alias Macaw.Layers.Test.Design

  for {name, arity} <- Design.__info__(:functions), name != :key do
    args = Macro.generate_arguments(arity, __MODULE__)
    def unquote(name)(unquote_splicing(args)), do: Design.unquote(name)(unquote_splicing(args))
  end

  def key(:composite, :defaults), do: %{merge: :override}
  def key(kind, key), do: Design.key(kind, key)

  def scope(%{defaults: defaults}, %{mark: mark} = contribution, _key) when is_map(mark),
    do: %{contribution | mark: Map.put_new(mark, :defaults, defaults)}

  def scope(_composite, contribution, _key), do: contribution

  def place_whole(%{frames: frames} = contribution, key) when map_size(frames) == 1,
    do: {:ok, %{contribution | frames: %{key => frames |> Map.values() |> hd()}}}

  def place_whole(contribution, _key), do: {:ok, contribution}
end
