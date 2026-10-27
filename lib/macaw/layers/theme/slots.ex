defmodule Macaw.Layers.Theme.Slots do
  @moduledoc false
  # The series slots `:series_1` … and the style series names `:style_1` …, written out so
  # no atom is made from a string (spec/01 §2): a theme holds at most 64 of each, far past
  # the categories a reader can tell apart by color.

  @series ~w(
    series_1 series_2 series_3 series_4 series_5 series_6 series_7 series_8 series_9 series_10
    series_11 series_12 series_13 series_14 series_15 series_16 series_17 series_18 series_19 series_20
    series_21 series_22 series_23 series_24 series_25 series_26 series_27 series_28 series_29 series_30
    series_31 series_32 series_33 series_34 series_35 series_36 series_37 series_38 series_39 series_40
    series_41 series_42 series_43 series_44 series_45 series_46 series_47 series_48 series_49 series_50
    series_51 series_52 series_53 series_54 series_55 series_56 series_57 series_58 series_59 series_60
    series_61 series_62 series_63 series_64
  )a
  @style_series ~w(
    style_1 style_2 style_3 style_4 style_5 style_6 style_7 style_8 style_9 style_10
    style_11 style_12 style_13 style_14 style_15 style_16 style_17 style_18 style_19 style_20
    style_21 style_22 style_23 style_24 style_25 style_26 style_27 style_28 style_29 style_30
    style_31 style_32 style_33 style_34 style_35 style_36 style_37 style_38 style_39 style_40
    style_41 style_42 style_43 style_44 style_45 style_46 style_47 style_48 style_49 style_50
    style_51 style_52 style_53 style_54 style_55 style_56 style_57 style_58 style_59 style_60
    style_61 style_62 style_63 style_64
  )a

  @doc false
  @spec max() :: pos_integer()
  def max, do: length(@series)

  @doc false
  # The series slot `:series_k`, `k` in `1..max()`.
  @spec series(pos_integer()) :: atom()
  def series(k) when is_integer(k) and k >= 1 and k <= 64, do: Enum.at(@series, k - 1)

  @doc false
  # The style series name `:style_k`, `k` in `1..max()`.
  @spec style(pos_integer()) :: atom()
  def style(k) when is_integer(k) and k >= 1 and k <= 64, do: Enum.at(@style_series, k - 1)
end
