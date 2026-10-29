defmodule Macaw.Layers.Test.Design.Tags do
  @moduledoc false
  use Macaw.Layers.Tags, live: ~w($var $id $use)
end

defmodule Macaw.Layers.Test.Design do
  @moduledoc false
  # A fragment type standing in for visualize's design schema (spec/02 §1), so the
  # machinery is tested against the rules it was written for: marks, labels and axes
  # concatenate with identity, sources, styles and vars unite, frames deepen, a style's
  # `fill` merges by the type's own rule, a label's text holds `{{name}}` holes, a mark's
  # style may be an id inlined at flattening, and every kind lands where visualize's does.
  @behaviour Macaw.Layers.Fragment
  @behaviour Macaw.Layers.Form

  alias Macaw.Layers.{Fragment, Use, Var, Vocabulary}

  @keys %{
    design: %{
      version: %{merge: :override},
      theme: %{merge: :override, node: :theme},
      meta: %{merge: :override, node: :meta},
      sources: %{merge: :union, element: :source},
      styles: %{merge: :union, element: :style},
      vars: %{merge: :union, element: :var},
      frames: %{merge: :deep, element: :frame},
      marks: %{merge: :concat, element: :mark},
      labels: %{merge: :concat, element: :label}
    },
    frame: %{
      kind: %{merge: :override},
      size: %{merge: :override, node: :size},
      margin: %{merge: :override, node: :margin},
      scales: %{merge: :union, element: :scale},
      axes: %{merge: :concat, element: :axis}
    },
    mark: %{
      data: %{merge: :override, node: :data},
      channels: %{merge: :override, node: :channels}
    },
    data: %{transforms: %{merge: :concat, element: :transform}},
    style: %{fill: %{merge: {:type, :parts}}}
  }

  @impl Macaw.Layers.Fragment
  def root, do: :design

  @impl Macaw.Layers.Fragment
  def key(kind, key), do: @keys |> Map.get(kind, %{}) |> Map.get(key)

  @impl Macaw.Layers.Fragment
  def identity(kind, element) when kind in [:mark, :label], do: Map.get(element, :id)
  def identity(:axis, %{scale: scale, side: side}), do: {scale, side}
  def identity(_kind, _element), do: nil

  @impl Macaw.Layers.Fragment
  def kinds, do: [:axis, :composite, :frame, :label, :mark, :scale, :source, :style, :theme, :var]

  @impl Macaw.Layers.Fragment
  def wrapper(key) when key in [:style, :scale, :theme, :mark, :source, :var], do: key
  def wrapper(_key), do: nil

  # Each kind where a whole design keeps it: a name-keyed one under the site's key.
  @impl Macaw.Layers.Fragment
  def place(:style, %{style: body}, key), do: keyed(:styles, key, body)
  def place(:source, %{source: body}, key), do: keyed(:sources, key, body)
  def place(:var, %{var: body}, key), do: keyed(:vars, key, body)
  def place(:scale, %{scale: _body}, nil), do: :keyless

  def place(:scale, %{scale: body}, key),
    do: {:ok, %{frames: %{"main" => %{scales: %{key => body}}}}}

  def place(:mark, %{mark: body}, _key), do: {:ok, %{marks: [body]}}
  def place(_kind, contribution, _key), do: {:ok, contribution}

  defp keyed(_list, nil, _body), do: :keyless
  defp keyed(list, key, body), do: {:ok, %{list => %{key => body}}}

  @impl Macaw.Layers.Fragment
  def merge(:parts, lower, higher) when is_map(lower) and is_map(higher),
    do: Map.merge(lower, higher)

  def merge(:parts, _lower, higher), do: higher

  # A label's text holds `{{name}}` holes, each a variable at the text's key.
  @impl Macaw.Layers.Fragment
  def holes(:label, :text, text) when is_binary(text),
    do: for([_, name] <- Regex.scan(~r/\{\{(\w+)\}\}/, text), do: Var.new(name))

  def holes(_kind, _key, _value), do: []

  @impl Macaw.Layers.Fragment
  def bind_holes(:label, :text, text, bindings) when is_binary(text) do
    Regex.replace(~r/\{\{(\w+)\}\}/, text, fn whole, name ->
      case Macaw.Layers.Names.fetch(bindings, name) do
        {:ok, %Var{name: renamed}} -> "{{#{renamed}}}"
        {:ok, value} -> to_string(value)
        :error -> whole
      end
    end)
  end

  def bind_holes(_kind, _key, value, _bindings), do: value

  # A mark's style given as an id is the style's body inlined; a missing one is removed.
  @impl Macaw.Layers.Fragment
  def inline(%{marks: marks} = design, fetch) when is_list(marks) do
    {marks, missing} =
      marks
      |> Enum.with_index()
      |> Enum.map_reduce([], fn
        {%{style: {:style, _} = id} = mark, i}, missing ->
          case fetch.(id) do
            {:ok, %{style: body}} -> {%{mark | style: body}, missing}
            _missing -> {Map.delete(mark, :style), missing ++ [{id, [:marks, i, :style]}]}
          end

        {mark, _i}, missing ->
          {mark, missing}
      end)

    {%{design | marks: marks}, missing}
  end

  def inline(design, _fetch), do: {design, []}

  # A design as inline sites: its theme, each style and source by its key, each mark.
  @impl Macaw.Layers.Fragment
  def decompose(design) do
    sites =
      for({:theme, theme} <- Map.take(design, [:theme]), do: {%{theme: theme}, nil}) ++
        for({key, body} <- Map.get(design, :styles, %{}), do: {%{style: body}, key}) ++
        for({key, body} <- Map.get(design, :sources, %{}), do: {%{source: body}, key}) ++
        for(mark <- Map.get(design, :marks, []), do: {%{mark: mark}, nil})

    sites
    |> Enum.with_index(1)
    |> Enum.map(fn {{local, key}, n} -> %Use{id: {:use, n}, local: local, key: key} end)
  end

  # -- the forms ---------------------------------------------------------------------------

  @key_table Vocabulary.table(
               [:version, :theme, :meta, :sources, :styles, :vars, :frames, :marks, :labels] ++
                 [:kind, :size, :margin, :scales, :axes, :data, :channels, :transforms] ++
                 [:fill, :stroke, :stroke_width, :opacity, :id, :type, :scale, :side, :ticks] ++
                 [
                   :anchor,
                   :text,
                   :default,
                   :fields,
                   :composite,
                   :uses,
                   :style,
                   :mark,
                   :source,
                   :var
                 ]
             )
  @atom_table Vocabulary.table([
                :line,
                :area,
                :rule,
                :dark,
                :default,
                :cartesian,
                :polar,
                :bottom,
                :left,
                :top,
                :title
              ])

  @impl Macaw.Layers.Form
  def tags, do: Macaw.Layers.Test.Design.Tags
  @impl Macaw.Layers.Form
  def keys, do: @key_table
  @impl Macaw.Layers.Form
  def atoms, do: @atom_table
  @impl Macaw.Layers.Form
  def encode_value(term), do: Fragment.encode_value(__MODULE__, term)
  @impl Macaw.Layers.Form
  def decode_value(tag, payload), do: Fragment.decode_value(__MODULE__, tag, payload)
  @impl Macaw.Layers.Form
  def name_map?(path), do: Fragment.name_map?(__MODULE__, path)
end
