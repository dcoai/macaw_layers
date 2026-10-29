defmodule Macaw.Layers.Theme.Contrast do
  @moduledoc false
  # Contrast on a theme (spec/04 §2.6, §3.2, §4): the ink a text takes over a color, the
  # floors a theme offered to people holds against its own background, a color value held
  # to a profile, and a data color under the contrast guard. `Macaw.Layers.Theme` is the
  # public face. Every color here is a term, a literal `%Macaw.Layers.Color{}`; a string is
  # never one (spec/04 §1.1).
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

  @black Color.rgb(0, 0, 0)
  @white Color.rgb(255, 255, 255)

  @doc false
  @spec ink(Theme.t(), Color.t() | nil) :: Color.t()
  def ink(%Theme{} = theme, under) do
    under = under!(under) || literal(theme.background) || @white

    slots =
      for slot <- [theme.text, theme.background],
          Color.literal?(slot),
          do: {slot, Color.contrast(slot, under)}

    case best(slots) do
      {literal, ratio} when ratio >= @text ->
        literal

      _neither ->
        {literal, _ratio} =
          best([{@black, Color.contrast(@black, under)}, {@white, Color.contrast(@white, under)}])

        literal
    end
  end

  defp under!(nil), do: nil

  defp under!(under) do
    cond do
      Color.literal?(under) -> under
      is_binary(under) -> raise ArgumentError, "ink: under #{Typed.text_hint(under)}"
      true -> raise ArgumentError, "ink: under is a literal color or nil, got #{inspect(under)}"
    end
  end

  # The first of the highest ratio, so the earlier candidate wins a tie.
  defp best([]), do: nil

  defp best(candidates) do
    Enum.reduce(candidates, fn {_, ratio} = candidate, {_, best} = acc ->
      if ratio > best, do: candidate, else: acc
    end)
  end

  # A slot's literal, `nil` where a theme built by hand holds none.
  defp literal(value), do: if(Color.literal?(value), do: value)

  @doc false
  @spec floors(Theme.t()) :: :ok | {:error, [{atom(), term()}, ...]}
  def floors(%Theme{} = theme) do
    background = literal(theme.background) || @white

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

  # A slot that holds no literal reaches no ratio.
  defp ratio(value, background) do
    case literal(value) do
      %Color{} = color -> Float.floor(Color.contrast(over(color, background), background), 2)
      nil -> 0.0
    end
  end

  # Two literals are one color where they write one hex: what a reader can tell apart.
  defp same?(a, b) do
    case {literal(a), literal(b)} do
      {%Color{} = x, %Color{} = y} -> Color.to_hex(x) == Color.to_hex(y)
      _other -> a === b
    end
  end

  # A color as it is seen: laid over the background when translucent.
  defp over(%Color{r: r, g: g, b: b, opacity: a}, %Color{} = background) do
    mix = fn x, y -> x * a + y * (1 - a) end
    Color.rgb(mix.(r, background.r), mix.(g, background.g), mix.(b, background.b))
  end

  @doc false
  @spec check_color(term(), :roles | :open) :: :ok | {:error, {:literal_color, term()}}
  def check_color(value, profile) when profile in [:roles, :open] do
    cond do
      is_binary(value) -> raise ArgumentError, "check_color: #{Typed.text_hint(value)}"
      not Color.value?(value) -> raise ArgumentError, "not a color value: #{inspect(value)}"
      profile == :roles and literal?(value) -> {:error, {:literal_color, value}}
      true -> :ok
    end
  end

  def check_color(_value, profile),
    do: raise(ArgumentError, "a color profile is :roles or :open, got #{inspect(profile)}")

  defp literal?(%Color{}), do: true
  defp literal?({:blend, list}) when is_list(list), do: Enum.any?(list, &literal?/1)
  defp literal?({:contrast, c}), do: literal?(c)
  defp literal?({_op, c, t}) when is_number(t), do: literal?(c)
  defp literal?(_value), do: false

  @doc false
  @spec data_color(Theme.t(), term()) ::
          {:ok, Color.t()} | {:error, {:contrast, float()} | :unreadable}
  def data_color(%Theme{} = theme, value) do
    background = literal(theme.background) || @white

    case resolved(theme, value) do
      %Color{} = color ->
        ratio = Color.contrast(over(color, background), background)

        if ratio >= @non_text,
          do: {:ok, color},
          else: {:error, {:contrast, Float.floor(ratio, 2)}}

      nil ->
        {:error, :unreadable}
    end
  end

  # The literal a data color resolves to, or `nil` where it does not: a color value whose
  # every name and ramp the theme resolves. Text is no color, and so resolves to none.
  defp resolved(theme, value) do
    if Color.value?(value) and resolves?(theme, value),
      do: Color.resolve(value, theme, :literal)
  end

  defp resolves?(theme, value) do
    Enum.all?(Typed.names(value), &Theme.color_name?(theme, &1)) and
      Table.names_resolve(theme, value, []) == :ok
  end
end
