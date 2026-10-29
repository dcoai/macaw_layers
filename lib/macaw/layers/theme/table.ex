defmodule Macaw.Layers.Theme.Table do
  @moduledoc false
  # A theme's color table (spec/04 §2.2): a name's entry looked up in the theme's own
  # `colors`, then the default theme's, then the extensions', then the CSS named colors, each
  # by either spelling of the name; a name's literal color through any chain of names; a
  # ramp's anchors as literals; and each own entry held to what an entry may be. A literal is
  # the term `%Macaw.Layers.Color{}`; a string is never a color (spec/04 §1.1).
  #
  # Ported from the color-table half of visualize's `Visualize.Theme`.

  alias Macaw.Layers.{Color, Theme}
  alias Macaw.Layers.Color.Typed
  alias Macaw.Layers.Theme.{Contract, Extension}

  # The CSS named colors as literals, read once when this compiles.
  @css_colors Map.new(Color.named_colors(), &{&1, Color.parse!(&1)})

  @doc false
  @spec own_colors(Theme.t()) :: map()
  def own_colors(%Theme{colors: colors}) when is_map(colors), do: colors
  def own_colors(%Theme{}), do: %{}

  @doc false
  @spec extra_colors(Theme.t()) :: map()
  def extra_colors(%Theme{extensions: extensions}) when is_list(extensions),
    do: Extension.colors(extensions)

  def extra_colors(%Theme{}), do: %{}

  @doc false
  # A name's entry, or `nil` when the table has no such name. A theme lacking a role takes
  # the default's, never a series color (§2.3).
  @spec lookup(Theme.t(), atom() | String.t()) :: term()
  def lookup(theme, name) do
    spelled(own_colors(theme), name) || spelled(Theme.default_colors(), name) ||
      spelled(extra_colors(theme), name) || css(name)
  end

  defp css(name) do
    Map.get(@css_colors, to_string(name))
  end

  # An entry by either spelling of its name: a document names a theme's colors by string,
  # Elixir by atom.
  defp spelled(map, name) do
    case map do
      %{^name => value} ->
        value

      map when is_atom(name) ->
        Map.get(map, Atom.to_string(name))

      map ->
        Enum.find_value(map, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == name, do: v end)
    end
  end

  @doc false
  # A name's literal. A chain of names that reaches itself raises; `Theme.violations/1`
  # reports it first.
  @spec literal(Theme.t(), atom() | String.t()) :: Color.t()
  def literal(theme, name), do: literal(theme, name, [])

  defp literal(theme, name, seen) do
    if name in seen,
      do: raise(ArgumentError, "color #{inspect(name)} reaches itself through the color table")

    case lookup(theme, name) do
      %Color{} = literal -> literal
      {:ramp, ramp, t} -> Theme.ramp(theme, ramp, t)
      {:color, other} -> literal(theme, other, [name | seen])
      %{500 => %Color{} = base} -> base
      value -> Color.resolve(value, theme, :literal)
    end
  end

  @doc false
  # The literal a theme pins at step `n` of a name, `nil` when it pins none there.
  @spec step(Theme.t(), atom() | String.t(), number()) :: Color.t() | nil
  def step(theme, name, n) do
    case lookup(theme, name) do
      %{^n => %Color{} = literal} -> literal
      _unpinned -> nil
    end
  end

  @doc false
  # A ramp's anchors as literals, the default theme's where the theme lacks the ramp.
  @spec anchors(Theme.t(), atom()) :: [Color.t() | term()]
  def anchors(theme, name) do
    if name not in Contract.ramps(),
      do:
        raise(
          ArgumentError,
          "unknown ramp #{inspect(name)}; the ramps are #{inspect(Contract.ramps())}"
        )

    anchors =
      case Map.get(theme.ramps || %{}, name) do
        [_, _ | _] = anchors -> anchors
        _missing -> Map.fetch!(Theme.default_ramps(), name)
      end

    Enum.map(anchors, &(anchor_literal(theme, &1) || &1))
  end

  @doc false
  # An anchor as the literal color it is: a literal as itself, a name the literal it holds
  # through any chain of names, a transform the literal it computes; `nil` for one that
  # reaches none. An anchor never reads a ramp, so it cannot loop.
  @spec anchor_literal(Theme.t(), term()) :: Color.t() | nil
  def anchor_literal(theme, anchor), do: anchor_literal(theme, anchor, [])

  defp anchor_literal(_theme, %Color{} = literal, _seen),
    do: if(Color.literal?(literal), do: literal)

  defp anchor_literal(theme, {:color, name}, seen) do
    if name in seen do
      nil
    else
      case lookup(theme, name) do
        %Color{} = literal -> anchor_literal(theme, literal, seen)
        {:color, _} = next -> anchor_literal(theme, next, [name | seen])
        %{500 => %Color{} = base} -> anchor_literal(theme, base, seen)
        _other -> nil
      end
    end
  end

  defp anchor_literal(theme, value, seen) when is_tuple(value) do
    with true <- Color.value?(value),
         literals when literals != nil <- literal_names(theme, value, seen) do
      Color.resolve(literals, theme, :literal)
    else
      _no -> nil
    end
  end

  defp anchor_literal(_theme, _anchor, _seen), do: nil

  defp literal_names(_theme, %Color{} = literal, _seen), do: literal
  defp literal_names(theme, {:color, _} = name, seen), do: anchor_literal(theme, name, seen)
  defp literal_names(_theme, {:contrast, :under}, _seen), do: nil

  defp literal_names(theme, {:blend, list}, seen) do
    literals = Enum.map(list, &literal_names(theme, &1, seen))
    if nil in literals, do: nil, else: {:blend, literals}
  end

  defp literal_names(theme, {:contrast, c}, seen) do
    with c when c != nil <- literal_names(theme, c, seen), do: {:contrast, c}
  end

  defp literal_names(theme, {op, c, t}, seen) when is_atom(op) and is_number(t) do
    with c when c != nil <- literal_names(theme, c, seen), do: {op, c, t}
  end

  defp literal_names(_theme, _other, _seen), do: nil

  @doc false
  # An entry of the theme's own `colors` held to what an entry may be: a literal color, a
  # color value whose names are the table's and do not reach the entry again, or pinned
  # steps. Text is refused naming the edges that read it.
  @spec entry(Theme.t(), atom() | String.t()) :: :ok | {:error, String.t()}
  def entry(theme, name) do
    value = Map.fetch!(own_colors(theme), name)

    cond do
      not word?(to_string(name)) ->
        {:error, "a color name is lower-case letters, digits and _, starting with a letter"}

      is_binary(value) ->
        {:error, Typed.text_hint(value)}

      Color.value?(value) ->
        names_resolve(theme, value, [name])

      is_map(value) and not is_struct(value) ->
        steps(value)

      true ->
        {:error,
         "#{inspect(value)} is not a color: a literal color, a color value or pinned steps"}
    end
  end

  defp steps(steps) do
    cond do
      not Map.has_key?(steps, 500) ->
        {:error,
         "pinned steps must include 500, the name's own color; got #{inspect(Map.keys(steps))}"}

      bad = Enum.find(Map.keys(steps), &(not (is_integer(&1) and &1 >= 0 and &1 <= 1000))) ->
        {:error, "a pinned step is an integer in 0..1000, got #{inspect(bad)}"}

      bad = Enum.find(Map.values(steps), &(not Color.literal?(&1))) ->
        {:error, "a pinned step is a literal color#{step_words(bad)}"}

      true ->
        :ok
    end
  end

  defp step_words(text) when is_binary(text), do: ": " <> Typed.text_hint(text)
  defp step_words(other), do: ", got " <> inspect(other)

  @doc false
  # Whether every name in a color value is the table's, without a loop back to `seen`.
  @spec names_resolve(Theme.t(), term(), list()) :: :ok | {:error, String.t()}
  def names_resolve(theme, {:color, other}, seen) do
    cond do
      other in seen ->
        {:error, "reaches itself through #{inspect(other)}"}

      lookup(theme, other) == nil and not Theme.color_name?(theme, other) ->
        {:error, "names #{inspect(other)}, which is not a color"}

      true ->
        names_resolve(theme, lookup(theme, other), [other | seen])
    end
  end

  def names_resolve(_theme, {:ramp, name, _t}, _seen) do
    if name in Contract.ramps(),
      do: :ok,
      else: {:error, "names the ramp #{inspect(name)}, which is not a ramp"}
  end

  def names_resolve(theme, {:blend, list}, seen),
    do: Enum.find_value(list, :ok, &error_or_nil(names_resolve(theme, &1, seen)))

  def names_resolve(theme, {_op, c, _t}, seen), do: names_resolve(theme, c, seen)
  def names_resolve(theme, {:contrast, c}, seen), do: names_resolve(theme, c, seen)
  def names_resolve(_theme, _value, _seen), do: :ok

  defp error_or_nil(:ok), do: nil
  defp error_or_nil(error), do: error

  # -- a slot's value ---------------------------------------------------------------------

  @doc false
  # A slot or name as `{kind, value}`, `kind` saying how CSS writes it. An unknown name, or
  # a series slot beyond the palette, raises `ArgumentError`.
  @spec value(Theme.t(), atom() | String.t()) :: {:color | :font | :size, term()}
  def value(theme, slot) do
    fixed = Enum.find(Theme.fixed_slots(), &(&1 == slot or Atom.to_string(&1) == slot))

    cond do
      fixed in [:axis, :grid, :text, :background, :surface] -> {:color, Map.fetch!(theme, fixed)}
      fixed == :font_family -> {:font, theme.font_family}
      fixed in Theme.size_slots() -> {:size, Map.fetch!(theme, fixed)}
      true -> table_value(theme, slot)
    end
  end

  defp table_value(%Theme{series: series} = theme, slot) do
    case series_index(slot) do
      k when is_integer(k) and k >= 1 and k <= length(series) ->
        {:color, Enum.at(series, k - 1)}

      _other ->
        if lookup(theme, slot) == nil,
          do:
            raise(
              ArgumentError,
              "unknown theme slot #{inspect(slot)}; see Macaw.Layers.Theme.slots/1 and color_names/1"
            ),
          else: {:color, literal(theme, slot)}
    end
  end

  @doc false
  @spec series_index(term()) :: pos_integer() | nil
  def series_index(slot) when is_atom(slot) or is_binary(slot) do
    with "series_" <> rest <- to_string(slot),
         {k, ""} <- Integer.parse(rest) do
      k
    else
      _ -> nil
    end
  end

  def series_index(_slot), do: nil

  @doc false
  @spec word?(String.t()) :: boolean()
  # A spelling in the grammar of a theme's names, `Color.name?/1`.
  def word?(spelling) when is_binary(spelling), do: Color.name?(spelling)

  @doc false
  # A value as CSS writes it: a size in px, a literal color its CSS text (spec/04 §1.6), and
  # a string with the characters that would end its declaration, its rule or a `<style>`
  # around the sheet written as CSS escapes.
  @spec css_value(atom(), term()) :: String.t()
  def css_value(:size, n), do: "#{n}px"
  def css_value(:color, %Color{} = literal), do: Color.to_css(literal)
  def css_value(_kind, value) when is_binary(value), do: css_escape(value)
  def css_value(_kind, value), do: to_string(value)

  defp css_escape(value) do
    case :binary.match(value, ["<", ">", ";", "{", "}", "\\"]) do
      :nomatch ->
        value

      _found ->
        String.replace(value, ["<", ">", ";", "{", "}", "\\"], fn char ->
          "\\" <> (char |> :binary.first() |> Integer.to_string(16)) <> " "
        end)
    end
  end
end
