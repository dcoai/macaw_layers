defmodule Macaw.Layers.Test.Layout.Tags do
  @moduledoc false
  use Macaw.Layers.Tags, live: ~w($var $id $use)
end

defmodule Macaw.Layers.Test.Layout do
  @moduledoc false
  # A second fragment type, beside `Macaw.Layers.Test.Design`, so a store holds two: panels
  # name-keyed under `panels`, and a version line at 2 whose one step renames a panel's
  # `cols` to `columns`, so a bundle's fragment migrates as a document of its type does.
  @behaviour Macaw.Layers.Fragment
  @behaviour Macaw.Layers.Form
  @behaviour Macaw.Layers.Version

  alias Macaw.Layers.{Fragment, Vocabulary}

  @impl Macaw.Layers.Fragment
  def root, do: :layout

  @impl Macaw.Layers.Fragment
  def key(:layout, :panels), do: %{merge: :union, element: :panel}
  def key(:panel, :style), do: %{merge: :override}
  def key(_kind, _key), do: nil

  @impl Macaw.Layers.Fragment
  def kinds, do: [:panel]

  @impl Macaw.Layers.Fragment
  def wrapper(:panel), do: :panel
  def wrapper(_key), do: nil

  @impl Macaw.Layers.Fragment
  def place(:panel, %{panel: _body}, nil), do: :keyless
  def place(:panel, %{panel: body}, key), do: {:ok, %{panels: %{key => body}}}
  def place(_kind, contribution, _key), do: {:ok, contribution}

  @impl Macaw.Layers.Version
  def current, do: 2

  @impl Macaw.Layers.Version
  def step(%{"panel" => %{"cols" => cols} = panel} = form, 1),
    do: {:ok, %{form | "panel" => panel |> Map.delete("cols") |> Map.put("columns", cols)}}

  def step(form, 1), do: {:ok, form}

  @key_table Vocabulary.table([:panels, :panel, :columns, :style, :title])

  @impl Macaw.Layers.Form
  def tags, do: Macaw.Layers.Test.Layout.Tags
  @impl Macaw.Layers.Form
  def keys, do: @key_table
  @impl Macaw.Layers.Form
  def atoms, do: %{}
  @impl Macaw.Layers.Form
  def encode_value(term), do: Fragment.encode_value(__MODULE__, term)
  @impl Macaw.Layers.Form
  def decode_value(tag, payload), do: Fragment.decode_value(__MODULE__, tag, payload)
end
