defmodule Macaw.Layers.Theme.Sheet do
  @moduledoc """
  A theme compiled to a stylesheet (spec/04 §6): custom properties scoped by a class,
  `.mw-theme-<name>`, so every element under that class draws in the theme and a page
  switches theme by its class alone. Adopters emit the same class and properties, so a
  visualize chart standalone and on a page reads the same properties.

      Macaw.Layers.Theme.Sheet.stylesheet(
        [Macaw.Layers.Theme.default(), Macaw.Layers.Theme.dark()],
        auto: {Macaw.Layers.Theme.default(), Macaw.Layers.Theme.dark()}
      )

  The sheet's bytes are a pure function of its themes, so it is cached and served by its
  digest. There is never a `<style>` element per component.

  Ported from visualize's `Visualize.Theme.stylesheet/1` and `color_scheme/2`.
  """

  alias Macaw.Layers.Theme
  alias Macaw.Layers.Theme.Table

  # In high-contrast mode the furniture is the user's system colors, so what is drawn from
  # the theme agrees with the palette the browser forces.
  @forced [
    text: "CanvasText",
    axis: "CanvasText",
    background: "Canvas",
    surface: "Canvas",
    grid: "GrayText"
  ]

  @doc """
  The theme's rule: `.mw-theme-<name>` declaring every slot, then each of the theme's own
  colors that is not a slot and each step it pins other than 500, then the forced-colors
  block. A theme name that is not lower-case words raises `ArgumentError`.

      iex> Macaw.Layers.Theme.Sheet.rule(Macaw.Layers.Theme.default()) |> String.split("\\n") |> Enum.take(2)
      [".mw-theme-default {", "  --mw-series-1: #3b6fa8;"]
  """
  @spec rule(Theme.t()) :: String.t()
  def rule(%Theme{} = theme) do
    class = class(theme.name)
    block(class, declarations(theme), "") <> forced(class)
  end

  @doc """
  The rule `.mw-theme-auto`: `light`'s properties, and `dark`'s under
  `@media (prefers-color-scheme: dark)`, then the forced-colors block.
  """
  @spec auto(Theme.t(), Theme.t()) :: String.t()
  def auto(%Theme{} = light, %Theme{} = dark) do
    class = ".mw-theme-auto"

    block(class, declarations(light), "") <>
      "@media (prefers-color-scheme: dark) {\n" <>
      block(class, declarations(dark), "  ") <> "}\n" <> forced(class)
  end

  @doc """
  The whole static sheet: one rule per theme, in order, then, with `auto: {light, dark}`,
  the auto rule.
  """
  @spec stylesheet([Theme.t()], keyword()) :: String.t()
  def stylesheet(themes, opts \\ []) when is_list(themes) do
    rules = Enum.map_join(themes, "", &rule/1)

    case Keyword.fetch(opts, :auto) do
      {:ok, {light, dark}} -> rules <> auto(light, dark)
      :error -> rules
    end
  end

  defp class(name) do
    if is_binary(name) and Table.word?(name),
      do: ".mw-theme-" <> String.replace(name, "_", "-"),
      else:
        raise(
          ArgumentError,
          "a theme's class is its name in lower-case words, got #{inspect(name)}"
        )
  end

  defp block(class, lines, indent),
    do:
      "#{indent}#{class} {\n" <> Enum.map_join(lines, "", &"#{indent}  #{&1}\n") <> "#{indent}}\n"

  defp forced(class) do
    lines =
      Enum.map_join(@forced, "", fn {slot, system} ->
        "    #{Theme.css_name(slot)}: #{system};\n"
      end)

    "@media (forced-colors: active) {\n  #{class} {\n" <> lines <> "  }\n}\n"
  end

  # One `--mw-<name>: value;` per slot, then per own color that is not a slot, in name
  # order, each followed by the steps it pins.
  defp declarations(theme) do
    slots = Theme.slots(theme)
    taken = MapSet.new(slots)

    own =
      theme
      |> Table.own_colors()
      |> Map.keys()
      |> Enum.reject(&(&1 in taken))
      |> Enum.sort()

    for name <- slots ++ own, line <- declaration(theme, name), do: line
  end

  defp declaration(theme, name) do
    {kind, value} = Table.value(theme, name)
    property = Theme.css_name(name)
    ["#{property}: #{Table.css_value(kind, value)};" | pinned(theme, name, property)]
  end

  defp pinned(theme, name, property) do
    case Map.get(Table.own_colors(theme), name) do
      %{} = steps when not is_struct(steps) ->
        for {n, literal} <- Enum.sort(steps),
            n != 500,
            do: "#{property}-#{n}: #{Table.css_value(:color, literal)};"

      _other ->
        []
    end
  end
end
