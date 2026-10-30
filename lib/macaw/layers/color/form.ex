defmodule Macaw.Layers.Color.Form do
  @moduledoc """
  The colors' JSON adapter (spec/04 §1.6, §5): the map form of a literal color and of a
  color value, for a document type that holds colors to write and read through its
  `Macaw.Layers.Form` callbacks. Each is a tag, a transform's operands in their own forms,
  and a theme's pinned steps `$steps`:

  | Value | Map form |
  |---|---|
  | `%Macaw.Layers.Color{}`, 8-bit exact | `{"$rgb": "#3b6fa8"}`, eight digits when translucent |
  | `%Macaw.Layers.Color{}`, any other | `{"$rgb": [r, g, b, a]}`, its fields |
  | `{:color, "red"}` | `{"$color": "red"}` |
  | `{:series, 3}` | `{"$series": 3}` |
  | `{:ramp, "status", 0.5}` | `{"$ramp": ["status", 0.5]}` |
  | `{:lighten, c, 0.3}`, and so each transform | `{"$lighten": [C, 0.3]}` |
  | `{:blend, [c, …]}` | `{"$blend": [C, …]}` |
  | `{:contrast, :under}`, `{:contrast, c}` | `{"$contrast": "under"}`, `{"$contrast": C}` |
  | `%{500 => c, 100 => …}`, each step a literal | `{"$steps": [[100, …], [500, C]]}`, each `C` its `$rgb` |

  `$rgb` reads back the canonical struct (`Macaw.Layers.Color.literal?/1`), so decoding the
  payload `encode_value/1` writes of a literal color gives that color again. Its payload is
  `#` and six or eight hex digits, or four numbers in their ranges; any other is no color.
  A struct that is not a literal color has no form. A name is read as its string, as every
  name of a theme is (spec/04 §2.1), and written from either spelling; a name is read when
  `Macaw.Layers.Color.name?/1` holds of it, a ramp's as a color's, so a theme's own ramp
  round-trips and a theme that lacks it refuses it where it resolves. A string is
  never a color: an operand or a step is a color's own form, and a bare string in its place
  is no color. No atom is made from a document.

  A type implements `c:Macaw.Layers.Form.encode_value/1` and
  `c:Macaw.Layers.Form.decode_value/2` by calling these, and lists `tags/0` among its live
  tags. A value or payload these do not read is `:default`, which the kernel refuses at its
  path.

  The tags of visualize's `Visualize.Chart.Codec`, with `$rgb`.
  """

  alias Macaw.Layers.Color

  @ops [:intensity, :alpha, :lighten, :darken, :saturate, :shade]
  @op_tags Map.new(@ops, &{"$#{&1}", &1})
  @tags ~w($rgb $color $series $ramp $blend $contrast $steps) ++ Map.keys(@op_tags)
  @hex ~r/\A#(?:[0-9a-f]{6}|[0-9a-f]{8})\z/i

  @doc "The colors' tags, for a type's tag table."
  @spec tags() :: [String.t(), ...]
  def tags, do: @tags

  @doc """
  A color's map form, `{:ok, form}`, or `:default` for a term that is not a color here.

      iex> Macaw.Layers.Color.Form.encode_value(Macaw.Layers.Color.parse("#3b6fa880"))
      {:ok, %{"$rgb" => "#3b6fa880"}}
      iex> Macaw.Layers.Color.Form.encode_value(Macaw.Layers.Color.rgb(59.5, 111, 168))
      {:ok, %{"$rgb" => [59.5, 111.0, 168.0, 1.0]}}

  """
  @spec encode_value(term()) :: {:ok, map()} | :default
  def encode_value(%Color{} = color) do
    cond do
      not Color.literal?(color) -> :default
      Color.exact?(color) -> {:ok, %{"$rgb" => Color.to_hex(color)}}
      true -> {:ok, %{"$rgb" => [color.r, color.g, color.b, color.opacity]}}
    end
  end

  def encode_value({:color, name}) when is_atom(name) or is_binary(name),
    do: {:ok, %{"$color" => to_string(name)}}

  def encode_value({:series, i}) when is_integer(i) and i > 0, do: {:ok, %{"$series" => i}}

  def encode_value({:ramp, name, t}) when (is_atom(name) or is_binary(name)) and is_number(t),
    do: {:ok, %{"$ramp" => [to_string(name), t]}}

  def encode_value({op, c, t}) when op in @ops and is_number(t) do
    with {:ok, c} <- operand(c), do: {:ok, %{"$#{op}" => [c, t]}}
  end

  def encode_value({:blend, list}) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn c, {:ok, acc} ->
      case operand(c) do
        {:ok, form} -> {:cont, {:ok, [form | acc]}}
        :default -> {:halt, :default}
      end
    end)
    |> case do
      {:ok, forms} -> {:ok, %{"$blend" => Enum.reverse(forms)}}
      :default -> :default
    end
  end

  def encode_value({:contrast, :under}), do: {:ok, %{"$contrast" => "under"}}

  def encode_value({:contrast, c}) do
    with {:ok, c} <- operand(c), do: {:ok, %{"$contrast" => c}}
  end

  def encode_value(steps) when is_map(steps) and not is_struct(steps) and map_size(steps) > 0 do
    if Enum.all?(steps, fn {n, c} -> is_integer(n) and Color.literal?(c) end),
      do: {:ok, %{"$steps" => steps |> Enum.sort() |> Enum.map(fn {n, c} -> [n, rgb(c)] end)}},
      else: :default
  end

  def encode_value(_term), do: :default

  # An operand is a color value in its own form; text is none.
  defp operand(c), do: if(Color.value?(c), do: encode_value(c), else: :default)

  defp rgb(literal) do
    {:ok, form} = encode_value(literal)
    form
  end

  @doc """
  The value of one of `tags/0`, its payload already read: `{:ok, value}`, or `:default` for
  a tag or payload this reader does not read.

      iex> Macaw.Layers.Color.Form.decode_value("$rgb", "#3b6fa8")
      {:ok, %Macaw.Layers.Color{r: 59.0, g: 111.0, b: 168.0, opacity: 1.0}}
      iex> Macaw.Layers.Color.Form.decode_value("$rgb", "steelblue")
      :default

  """
  @spec decode_value(String.t(), term()) :: {:ok, term()} | :default
  def decode_value("$rgb", hex) when is_binary(hex) do
    if Regex.match?(@hex, hex), do: {:ok, Color.parse(hex)}, else: :default
  end

  def decode_value("$rgb", [r, g, b, a]) do
    if Enum.all?([r, g, b], &in?(&1, 255)) and in?(a, 1),
      do: {:ok, Color.rgb(r, g, b, a)},
      else: :default
  end

  def decode_value("$color", name) when is_binary(name) do
    if Color.name?(name), do: {:ok, {:color, name}}, else: :default
  end

  def decode_value("$series", i) when is_integer(i) and i > 0, do: {:ok, {:series, i}}

  def decode_value("$ramp", [name, t])
      when is_binary(name) and is_number(t) and t >= 0 and t <= 1 do
    if Color.name?(name), do: {:ok, {:ramp, name, t}}, else: :default
  end

  def decode_value("$blend", [_ | _] = list) do
    if Enum.all?(list, &color?/1), do: {:ok, {:blend, list}}, else: :default
  end

  def decode_value("$contrast", "under"), do: {:ok, {:contrast, :under}}

  def decode_value("$contrast", c) do
    if color?(c), do: {:ok, {:contrast, c}}, else: :default
  end

  def decode_value("$steps", [_ | _] = pairs) do
    if Enum.all?(pairs, &match?([n, %Color{}] when is_integer(n), &1)) and
         Enum.all?(pairs, fn [_n, c] -> Color.literal?(c) end),
       do: {:ok, Map.new(pairs, fn [n, c] -> {n, c} end)},
       else: :default
  end

  def decode_value(tag, [c, t]) when is_map_key(@op_tags, tag) and is_number(t) do
    op = Map.fetch!(@op_tags, tag)
    in_range? = if op == :shade, do: t >= 0 and t <= 1000, else: t >= 0 and t <= 1
    if in_range? and color?(c), do: {:ok, {op, c, t}}, else: :default
  end

  def decode_value(_tag, _payload), do: :default

  defp color?(c), do: Color.value?(c)

  defp in?(v, max), do: is_number(v) and v >= 0 and v <= max
end
