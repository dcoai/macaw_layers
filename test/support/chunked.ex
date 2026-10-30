defmodule Macaw.Layers.Test.Chunked do
  @moduledoc false
  # A value whose fields are a layout of its contents, as macaw_data's chunked table is:
  # one list of rows, held in chunks of any sizes. Its identity is the rows, so it
  # answers them as its canonical term (spec/01 §7).
  defstruct chunks: []

  def new(rows, size),
    do: %__MODULE__{chunks: rows |> Enum.chunk_every(size) |> Enum.map(&List.to_tuple/1)}

  def rows(%__MODULE__{chunks: chunks}), do: Enum.flat_map(chunks, &Tuple.to_list/1)
end

defimpl Macaw.Layers.Digest, for: Macaw.Layers.Test.Chunked do
  def canonical(t), do: {"test.chunked", Macaw.Layers.Test.Chunked.rows(t)}
end
