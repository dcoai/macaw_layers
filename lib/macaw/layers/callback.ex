defmodule Macaw.Layers.Callback do
  @moduledoc """
  Whether a type module defines an optional callback, loaded or not (spec/01 §9).

  `function_exported?/3` answers `false` for a module the VM hasn't loaded yet. Modules
  load lazily in dev, test and `iex`, so a bare check can run before the type is loaded
  and silently take the path of a type that lacks the callback. `exported?/3` loads the
  module first, so the answer is the module's, whatever has run before.
  """

  @doc """
  `true` when `module` defines `name/arity`, loading the module first. A module that
  can't be loaded raises, as a type that doesn't exist is a mistake, not a type without
  the callback.

      iex> Macaw.Layers.Callback.exported?(Macaw.Layers.Callback, :exported?, 3)
      true
  """
  @spec exported?(module(), atom(), arity()) :: boolean()
  def exported?(module, name, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, name, arity)
  end
end
