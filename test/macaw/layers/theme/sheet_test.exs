defmodule Macaw.Layers.Theme.SheetTest do
  # A theme compiled to a stylesheet (spec/04 §6).
  use ExUnit.Case, async: true

  alias Macaw.Layers.Theme
  alias Macaw.Layers.Theme.Sheet

  doctest Sheet

  @forced_dark "  .mw-theme-dark {\n    --mw-text: CanvasText;\n    --mw-axis: CanvasText;\n" <>
                 "    --mw-background: Canvas;\n    --mw-surface: Canvas;\n" <>
                 "    --mw-grid: GrayText;\n  }\n}\n"

  @tag verifies: "themes-sheet-rules"
  test "a rule declares every slot under the theme's class, sizes in px, then its own colors, then the forced-colors block" do
    css = Sheet.rule(Theme.dark())
    assert String.starts_with?(css, ".mw-theme-dark {\n  --mw-series-1: #7fb3e6;\n")
    assert css =~ "\n  --mw-background: #1b1e24;\n"
    assert css =~ "\n  --mw-surface: #23272f;\n"
    assert css =~ "\n  --mw-font-family: sans-serif;\n"
    assert css =~ "\n  --mw-title-size: 16px;\n"
    assert css =~ "\n  --mw-warning: #db8e1c;\n"

    # The theme's own color names that are not slots, in name order.
    [rule, forced] = String.split(css, "@media (forced-colors: active) {\n")

    assert String.ends_with?(
             rule,
             "  --mw-gray: #b7bcc6;\n  --mw-green: #4f924c;\n  --mw-red: #ff8f8a;\n}\n"
           )

    assert length(String.split(rule, "\n  --mw-")) == 1 + length(Theme.slots(Theme.dark())) + 5
    assert forced == @forced_dark
  end

  @tag verifies: "themes-sheet-rules"
  test "a host theme's own names and pinned steps are declared, its class its name" do
    house =
      Theme.new(
        name: :house_brand,
        colors: %{brand: "#123456", red: %{500 => "#d62728", 100 => "#fde8e8"}}
      )

    css = Sheet.rule(house)

    assert String.starts_with?(css, ".mw-theme-house-brand {\n")
    assert css =~ "\n  --mw-brand: #123456;\n"
    assert css =~ "\n  --mw-red: #d62728;\n  --mw-red-100: #fde8e8;\n"
    assert css =~ "@media (forced-colors: active) {\n  .mw-theme-house-brand {\n"

    assert_raise ArgumentError, ~r/a theme's class is its name in lower-case words/, fn ->
      Sheet.rule(%{house | name: "House Brand"})
    end
  end

  @tag verifies: "themes-sheet-rules"
  test "auto declares the light theme and switches to the dark one under prefers-color-scheme" do
    css = Sheet.auto(Theme.default(), Theme.dark())

    [light, rest] = String.split(css, "@media (prefers-color-scheme: dark) {\n")
    assert String.starts_with?(light, ".mw-theme-auto {\n  --mw-series-1: #3b6fa8;\n")
    assert light =~ "\n  --mw-background: #ffffff;\n"
    assert String.starts_with?(rest, "  .mw-theme-auto {\n    --mw-series-1: #7fb3e6;\n")
    assert rest =~ "\n    --mw-background: #1b1e24;\n"

    assert String.ends_with?(
             css,
             "@media (forced-colors: active) {\n  .mw-theme-auto {\n    --mw-text: CanvasText;\n    --mw-axis: CanvasText;\n    --mw-background: Canvas;\n    --mw-surface: Canvas;\n    --mw-grid: GrayText;\n  }\n}\n"
           )
  end

  @tag verifies: "themes-sheet-rules"
  test "the stylesheet is the rules in order, then auto, and depends only on its themes" do
    themes = [Theme.default(), Theme.dark(), Theme.print()]
    sheet = Sheet.stylesheet(themes, auto: {Theme.default(), Theme.dark()})

    assert sheet ==
             Enum.map_join(themes, "", &Sheet.rule/1) <> Sheet.auto(Theme.default(), Theme.dark())

    assert Sheet.stylesheet(themes) == Enum.map_join(themes, "", &Sheet.rule/1)
    assert Sheet.stylesheet([]) == ""

    assert Sheet.stylesheet(Enum.map(themes, &Theme.builtin(&1.name)),
             auto: {Theme.default(), Theme.dark()}
           ) == sheet

    refute sheet =~ "<style"
  end
end
