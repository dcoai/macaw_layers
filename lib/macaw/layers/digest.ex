defprotocol Macaw.Layers.Digest do
  @moduledoc """
  What the kernel's digest encodes for a struct (spec/01 §7): its **canonical term**.

  A struct whose fields are its contents (a schema, a `DateTime`) needs nothing: it is
  encoded as its map, `__struct__` and all, as it always was. A struct whose fields are a
  *layout* of its contents implements this protocol and answers the term its identity is,
  so two equal values laid out differently get one digest:

      defimpl Macaw.Layers.Digest, for: MyApp.Chunked do
        def canonical(t), do: {"my_app.chunked", MyApp.Chunked.rows(t)}
      end

  `Macaw.Layers.Document.digest/1` and `Macaw.Layers.Document.encode/1` encode a struct as
  its canonical term wherever it appears, nested in maps, lists and tuples too. The term
  answered must be data, and is itself encoded as any term is, a struct in it by its own
  canonical term.
  """
  @fallback_to_any true

  @doc "The term a struct's digest encodes in its place."
  @spec canonical(t) :: term()
  def canonical(value)
end

defimpl Macaw.Layers.Digest, for: Any do
  # The struct itself, which the encoding takes as its map, `__struct__` and all: every
  # digest made before the hook.
  def canonical(struct), do: struct
end
