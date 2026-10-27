defmodule Macaw.Layers.Use do
  @moduledoc """
  A use site (spec/02 §7): a fragment used at a position, resolved
  `ref → local → mask → bind → stack`. The site is a struct, so it is a leaf of every walk
  but the two id walks (`Macaw.Layers.Fragment.refs/2`, `relocate/3`), which read its parts
  by name.

  - `id`: the site's own identity, `{:use, n}`, the same site wherever it sits;
  - `ref`: which fragment: an id, a local key, or `nil` for an inline-only site;
  - `mask`: paths removed here, or `:all`;
  - `vars`: what the fragment's variables mean here;
  - `local`: what is added or overridden here;
  - `key`: the name a name-keyed kind is declared under, here;
  - `origin`: the entry an unlocked site was copied from, or `nil`.
  """

  @enforce_keys [:id]
  defstruct [:id, ref: nil, mask: [], vars: %{}, local: %{}, key: nil, origin: nil]

  @type t :: %__MODULE__{
          id: {:use, pos_integer()},
          ref: term(),
          mask: [list()] | :all,
          vars: map(),
          local: map(),
          key: String.t() | nil,
          origin: term()
        }
end
