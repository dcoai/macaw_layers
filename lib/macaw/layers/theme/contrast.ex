defmodule Macaw.Layers.Theme.Contrast do
  @moduledoc false
  # Contrast on a theme (spec/04 §2.6, §3.2, §4): the ink a text takes over a color, the
  # floors a theme offered to people holds against its own background, a color value held
  # to a profile, and a data color under the contrast guard. `Macaw.Layers.Theme` is the
  # public face.
  #
  # The ink is ported from visualize's `Visualize.Theme.ink/2`.

  alias Macaw.Layers.{Color, Theme}
  alias Macaw.Layers.Color.Typed
  alias Macaw.Layers.Theme.Table

  # WCAG 2.2: SC 1.4.3 (text, AA) and SC 1.4.11 (non-text).
  @text 4.5
  @non_text 3.0
  # A grid is seen, never read: enough to show the plane's divisions.
  @grid 1.2

  @doc false
  @spec ink(Theme.t(), String.t() | Color.t() | nil) :: String.t()
  def ink(%Theme{} = theme, under) do
    under = parsed(under) || parsed(theme.background) || Color.rgb(255, 255, 255)

    slots =
      for literal <- [theme.text, theme.background],
          color = parsed(literal),
          color != nil,
          do: {literal, Color.contrast(color, under)}

    case best(slots) do
      {literal, ratio} when ratio >= @text ->
        literal

      _neither ->
        {literal, _ratio} =
          best([
            {"#000000", Color.contrast(Color.rgb(0, 0, 0), under)},
            {"#ffffff", Color.contrast(Color.rgb(255, 255, 255), under)}
          ])

        literal
    end
  end

  # The first of the highest ratio, so the earlier candidate wins a tie.
  defp best([]), do: nil

  defp best(candidates) do
    Enum.reduce(candidates, fn {_, ratio} = candidate, {_, best} = acc ->
      if ratio > best, do: candidate, else: acc
    end)
  end

  defp parsed(%Color{} = color), do: color
  defp parsed(string) when is_binary(string), do: Color.parse(string)
  defp parsed(_other), do: nil

  @doc false
  @spec floors(Theme.t()) :: :ok | {:error, [{atom(), term()}, ...]}
  def floors(%Theme{} = theme) do
    background = parsed(theme.background) || Color.rgb(255, 255, 255)

    series =
      theme.series
      |> Enum.with_index(1)
      |> Enum.map(fn {literal, k} -> {Theme.series_atom(k), literal, @non_text} end)

    measured =
      for {slot, literal, floor} <-
            [{:text, theme.text, @text}, {:axis, theme.axis, @non_text}] ++
              series ++ [{:grid, theme.grid, @grid}],
          ratio = ratio(literal, background),
          ratio < floor,
          do: {slot, {:contrast, ratio, floor}}

    surface = if same?(theme.surface, theme.grid), do: [{:surface, {:equal, :grid}}], else: []

    case measured ++ surface do
      [] -> :ok
      faults -> {:error, faults}
    end
  end

  # A literal that does not parse reaches no ratio.
  defp ratio(literal, background) do
    case parsed(literal) do
      %Color{} = color -> Float.floor(Color.contrast(over(color, background), background), 2)
      nil -> 0.0
    end
  end

  defp same?(a, b) do
    case {parsed(a), parsed(b)} do
      {%Color{} = x, %Color{} = y} -> Color.to_hex(x) == Color.to_hex(y)
      _other -> a == b
    end
  end

  # A color as it is seen: laid over the background when translucent.
  defp over(%Color{r: r, g: g, b: b, opacity: a}, %Color{} = background) do
    mix = fn x, y -> x * a + y * (1 - a) end
    Color.rgb(mix.(r, background.r), mix.(g, background.g), mix.(b, background.b))
  end

  @doc false
  @spec check_color(term(), :roles | :open) :: :ok | {:error, {:literal_color, term()}}
  def check_color(_value, :open), do: :ok

  def check_color(value, :roles) do
    if literal?(value), do: {:error, {:literal_color, value}}, else: :ok
  end

  def check_color(_value, profile),
    do: raise(ArgumentError, "a color profile is :roles or :open, got #{inspect(profile)}")

  defp literal?(value) when is_binary(value), do: true
  defp literal?({:blend, list}) when is_list(list), do: Enum.any?(list, &literal?/1)
  defp literal?({:contrast, c}), do: literal?(c)
  defp literal?({_op, c, t}) when is_number(t), do: literal?(c)
  defp literal?(_value), do: false

  @doc false
  @spec data_color(Theme.t(), term()) ::
          {:ok, String.t()} | {:error, {:contrast, float()} | :unreadable}
  def data_color(%Theme{} = theme, value) do
    background = parsed(theme.background) || Color.rgb(255, 255, 255)

    with literal when is_binary(literal) <- literal(theme, value),
         %Color{} = color <- Color.parse(literal) do
      ratio = Color.contrast(over(color, background), background)

      if ratio >= @non_text,
        do: {:ok, literal},
        else: {:error, {:contrast, Float.floor(ratio, 2)}}
    else
      _unreadable -> {:error, :unreadable}
    end
  end

  # The literal a data color resolves to, or `nil` where it does not: a string as written,
  # a color value whose every name, ramp and operand the theme resolves.
  defp literal(_theme, value) when is_binary(value), do: if(Typed.readable?(value), do: value)

  defp literal(theme, value) do
    if Color.value?(value) and resolves?(theme, value), do: Color.resolve(value, theme, :literal)
  end

  defp resolves?(theme, value) do
    Typed.unreadable(value) == [] and
      Enum.all?(Typed.names(value), &Theme.color_name?(theme, &1)) and
      Table.names_resolve(theme, value, []) == :ok
  end
end
