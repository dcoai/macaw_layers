defmodule Macaw.Layers.Theme.ContrastTest do
  @moduledoc """
  The contrast a theme guarantees (spec/04 §2.6): both built-in themes hold their floors
  against their own background.
  """
  use ExUnit.Case, async: true

  alias Macaw.Layers.{Color, Theme}

  @themes [Theme.default(), Theme.dark()]

  defp contrast(hex, %Theme{background: background}) do
    color = Color.parse(hex)
    assert color, "#{hex} does not parse"
    Color.contrast(color, Color.parse(background))
  end

  for theme <- @themes do
    @theme theme

    @tag verifies: "themes-floors-builtins"
    test "the #{theme.name} theme: text 4.5:1, axis 3:1, every series 3:1, grid 1.2:1" do
      assert contrast(@theme.text, @theme) >= 4.5
      assert contrast(@theme.axis, @theme) >= 3.0
      assert contrast(@theme.grid, @theme) >= 1.2

      for color <- @theme.series do
        ratio = contrast(color, @theme)
        assert ratio >= 3.0, "#{color} is #{Float.round(ratio, 2)}:1 on #{@theme.name}"
      end
    end
  end
end
