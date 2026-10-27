defmodule Macaw.Layers.Color.Form do
  @moduledoc false
  # The map form of a color value (spec/04 §1.3, §5), for a document type that holds one to
  # write and read through its `Macaw.Layers.Form` callbacks: each value as a tag, its
  # operands in their own forms, and a theme's pinned steps as `$steps`.
  #
  #     {:color, :red}                   {"$color": "red"}
  #     {:series, 3}                     {"$series": 3}
  #     {:ramp, :status, 0.5}            {"$ramp": ["status", 0.5]}
  #     {:lighten, c, 0.3}               {"$lighten": [C, 0.3]}     and so each transform
  #     {:blend, [c, …]}                 {"$blend": [C, …]}
  #     {:contrast, :under | c}          {"$contrast": "under" | C}
  #     %{500 => "#d62728", 100 => …}    {"$steps": [[100, …], [500, "#d62728"]]}
  #
  # A name the library gives is read as its atom and any other as its string; a ramp of
  # another name is no color. No atom is made from a document.
  #
  # The tags of visualize's `Visualize.Chart.Codec`.

  alias Macaw.Layers.{Color, Theme, Vocabulary}

  @ops [:intensity, :alpha, :lighten, :darken, :saturate, :shade]
  @op_tags Map.new(@ops, &{"$#{&1}", &1})
  @tags ~w($color $series $ramp $blend $contrast $steps) ++ Map.keys(@op_tags)
  @names Vocabulary.table(Theme.library_color_names())
  @ramps Vocabulary.table(Theme.ramp_names())

  @doc false
  @spec tags() :: [String.t(), ...]
  def tags, do: @tags

  @doc false
  @spec encode_value(term()) :: {:ok, map()} | :default
  def encode_value({:color, name}) when is_atom(name) or is_binary(name),
    do: {:ok, %{"$color" => to_string(name)}}

  def encode_value({:series, i}) when is_integer(i) and i > 0, do: {:ok, %{"$series" => i}}

  def encode_value({:ramp, name, t}) when is_atom(name) and is_number(t),
    do: {:ok, %{"$ramp" => [Atom.to_string(name), t]}}

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
    if Enum.all?(steps, fn {n, c} -> is_integer(n) and is_binary(c) end),
      do: {:ok, %{"$steps" => steps |> Enum.sort() |> Enum.map(fn {n, c} -> [n, c] end)}},
      else: :default
  end

  def encode_value(_term), do: :default

  defp operand(c) when is_binary(c), do: {:ok, c}
  defp operand(c), do: encode_value(c)

  @doc false
  # The value of one of these tags, its payload already read, or `:default` for a payload
  # this reader does not read, which the kernel refuses at its path.
  @spec decode_value(String.t(), term()) :: {:ok, term()} | :default
  def decode_value("$color", name) when is_binary(name) and name != "" do
    case Vocabulary.fetch(@names, name) do
      {:ok, atom} -> {:ok, {:color, atom}}
      :error -> {:ok, {:color, name}}
    end
  end

  def decode_value("$series", i) when is_integer(i) and i > 0, do: {:ok, {:series, i}}

  def decode_value("$ramp", [name, t])
      when is_binary(name) and is_number(t) and t >= 0 and t <= 1 do
    case Vocabulary.fetch(@ramps, name) do
      {:ok, ramp} -> {:ok, {:ramp, ramp, t}}
      :error -> :default
    end
  end

  def decode_value("$blend", [_ | _] = list) do
    if Enum.all?(list, &color?/1), do: {:ok, {:blend, list}}, else: :default
  end

  def decode_value("$contrast", "under"), do: {:ok, {:contrast, :under}}

  def decode_value("$contrast", c) do
    if color?(c), do: {:ok, {:contrast, c}}, else: :default
  end

  def decode_value("$steps", [_ | _] = pairs) do
    if Enum.all?(pairs, &match?([n, c] when is_integer(n) and is_binary(c), &1)),
      do: {:ok, Map.new(pairs, fn [n, c] -> {n, c} end)},
      else: :default
  end

  def decode_value(tag, [c, t]) when is_map_key(@op_tags, tag) and is_number(t) do
    op = Map.fetch!(@op_tags, tag)
    in_range? = if op == :shade, do: t >= 0 and t <= 1000, else: t >= 0 and t <= 1
    if in_range? and color?(c), do: {:ok, {op, c, t}}, else: :default
  end

  def decode_value(_tag, _payload), do: :default

  defp color?(c), do: is_binary(c) or Color.value?(c)
end
