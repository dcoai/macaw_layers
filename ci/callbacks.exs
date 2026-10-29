# Refuses a bare `function_exported?/3` in lib/ outside `Macaw.Layers.Callback`
# (spec/01 §9, #4): it answers false for a module not loaded yet, which skips an optional
# callback silently. Ask `Callback.exported?/3` instead.
#
#   elixir ci/callbacks.exs [DIR]

dir = List.first(System.argv(), "lib")
allowed = Path.join(dir, "macaw/layers/callback.ex")

found =
  for file <- Path.wildcard(Path.join(dir, "**/*.ex")),
      file != allowed,
      {line, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
      String.contains?(line, "function_exported?("),
      do: "#{file}:#{n}: #{String.trim(line)}"

case found do
  [] ->
    IO.puts("callbacks OK — no bare function_exported? in #{dir}")

  _ ->
    IO.puts(
      :stderr,
      "a bare function_exported? skips an optional callback of a module not loaded yet; use Macaw.Layers.Callback.exported?/3:"
    )

    Enum.each(found, &IO.puts(:stderr, "  " <> &1))
    System.halt(1)
end
