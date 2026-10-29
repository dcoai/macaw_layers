defmodule Macaw.Layers.Test.ColdDesign do
  @moduledoc false
  # `Design` under another name, for the tests that unload it to check that an optional
  # callback is found whether or not its module is loaded (spec/01 §9). Unloading
  # `Design` itself would race the async tests that use it.

  @behaviour Macaw.Layers.Fragment
  @behaviour Macaw.Layers.Form

  for {name, arity} <- Macaw.Layers.Test.Design.__info__(:functions) do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: Macaw.Layers.Test.Design.unquote(name)(unquote_splicing(args))
  end
end
