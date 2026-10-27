defmodule Macaw.Layers.Fragment.ComposeTest do
  # Composition by the type's merge rules (spec/02 §2, §3.1), ported from visualize's
  # `Chart.ComposeTest` over a test type that declares visualize's design rules. Names are
  # strings, as a reader holds them; no chart is drawn or validated.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Fragment, Var}
  alias Macaw.Layers.Test.Design

  @label_set %{
    labels: [
      %{anchor: :caption, text: ["© house"]},
      %{anchor: {:frame, :top_right}, text: ["last 24 h"]}
    ]
  }
  @house %{
    version: 2,
    theme: :dark,
    styles: %{"series" => %{stroke_width: 2}, "muted" => %{opacity: 0.5}},
    frames: %{
      "main" => %{
        kind: :cartesian,
        margin: %{top: 10, right: 10, bottom: 30, left: 40},
        scales: %{"x" => %{kind: :time}},
        axes: [%{scale: "x", side: :bottom, ticks: 6}]
      }
    }
  }
  @chart %{
    version: 2,
    sources: %{"primary" => %{fields: ["t", "v"]}},
    styles: %{"accent" => %{stroke: :series_2}},
    frames: %{
      "main" => %{
        kind: :cartesian,
        scales: %{"y" => %{kind: :linear, domain: [0, :auto]}},
        axes: [%{scale: "y", side: :left, grid: true}]
      }
    },
    marks: [%{type: :line, data: "primary", channels: %{x: "t", y: "v"}, style: "accent"}],
    labels: [%{anchor: :title, text: ["Uptime"]}]
  }

  defp compose(a, b), do: Fragment.compose(Design, a, b)
  defp compose(list), do: Fragment.compose(Design, list)

  describe "compose/3 (spec/02 §3.1)" do
    @tag verifies: "fragments-compose-union"
    test "a label set, a house sheet and a chart compose into one fragment" do
      {:ok, design} = compose([@label_set, @house, @chart])

      assert Enum.map(design.labels, & &1.anchor) == [:caption, {:frame, :top_right}, :title]
      assert design.styles |> Map.keys() |> Enum.sort() == ["accent", "muted", "series"]
      assert design.theme == :dark
      assert design.frames["main"].margin == @house.frames["main"].margin
      assert design.frames["main"].scales |> Map.keys() |> Enum.sort() == ["x", "y"]
      assert Enum.map(design.frames["main"].axes, & &1.scale) == ["x", "y"]
      assert design.marks == @chart.marks
    end

    @tag verifies: "fragments-compose-union"
    test "a union name declared differently is a conflict at its path, every one reported" do
      a = %{
        styles: %{"series" => %{stroke_width: 2}},
        frames: %{"main" => %{scales: %{"x" => %{kind: :time}}}}
      }

      b = %{
        styles: %{"series" => %{stroke_width: 3}},
        frames: %{"main" => %{scales: %{"x" => %{kind: :linear}}}}
      }

      assert compose(a, b) ==
               {:error,
                [{[:frames, "main", :scales, "x"], :conflict}, {[:styles, "series"], :conflict}]}

      assert compose([a, b]) == compose(a, b)
    end

    @tag verifies: "fragments-compose-union"
    test "a union name declared equally in both is taken once; a key one fragment carries is taken as it is" do
      a = %{styles: %{"series" => %{stroke_width: 2}}, vars: %{"unit" => %{default: "%"}}}
      assert compose(a, a) == {:ok, a}
      assert compose(%{version: 2}, %{marks: []}) == {:ok, %{version: 2, marks: []}}
      assert compose(%{}, @chart) == {:ok, @chart}
      assert compose(@chart, %{}) == {:ok, @chart}
    end

    @tag verifies: "fragments-compose-union"
    test "a node given as anything but a map by either side is the later's whole, else it merges" do
      assert compose(%{theme: :dark}, %{theme: %{name: "house"}}) ==
               {:ok, %{theme: %{name: "house"}}}

      assert compose(%{theme: %{name: "a", axis: "#000"}}, %{theme: %{name: "b"}}) ==
               {:ok, %{theme: %{name: "b", axis: "#000"}}}
    end

    @tag verifies: "fragments-compose-union"
    test "compose/2 folds left to right and is the empty map for no fragments; an unknown key is the later's" do
      assert compose([]) == {:ok, %{}}
      assert compose([@chart]) == {:ok, @chart}
      {:ok, ab} = compose(@label_set, @house)
      assert compose([@label_set, @house, @chart]) == compose(ab, @chart)

      assert compose(%{extra: 1, marks: [1]}, %{extra: 2, marks: [2]}) ==
               {:ok, %{extra: 2, marks: [1, 2]}}
    end
  end

  describe "a struct at a mergeable key (spec/02 §2)" do
    @tag verifies: "fragments-rules-each"
    test "a whole-node variable at a union key is one value, never merged as a name map" do
      sheet = Var.new(:sheet)
      styles = %{"series" => %{stroke_width: 2}}

      assert compose(%{styles: sheet}, %{styles: styles}) == {:error, [{[:styles], :conflict}]}
      assert compose(%{styles: styles}, %{styles: sheet}) == {:error, [{[:styles], :conflict}]}

      assert compose(%{styles: sheet}, %{styles: Var.new(:other)}) ==
               {:error, [{[:styles], :conflict}]}

      assert compose(%{styles: sheet}, %{styles: sheet}) == {:ok, %{styles: sheet}}
      assert compose(%{styles: sheet}, %{version: 2}) == {:ok, %{styles: sheet, version: 2}}
    end

    @tag verifies: "fragments-rules-each"
    test "every name-map key reads a whole-node variable the same way, at its own path" do
      v = Var.new(:v)

      for {declared, variable, path} <- [
            {%{sources: %{"p" => %{fields: ["t"]}}}, %{sources: v}, [:sources]},
            {%{vars: %{"unit" => %{default: "%"}}}, %{vars: v}, [:vars]},
            {%{styles: %{"series" => %{stroke_width: 2}}}, %{styles: v}, [:styles]},
            {%{frames: %{"main" => %{scales: %{"x" => %{kind: :time}}}}},
             %{frames: %{"main" => %{scales: v}}}, [:frames, "main", :scales]},
            {%{frames: %{"main" => %{kind: :polar}}}, %{frames: v}, [:frames]}
          ] do
        assert compose(variable, declared) == {:error, [{path, :conflict}]}
        assert compose(declared, variable) == {:error, [{path, :conflict}]}
        assert compose(variable, variable) == {:ok, variable}
      end
    end

    @tag verifies: "fragments-rules-each"
    test "a concat key given as a variable is the later's whole, and is not a conflict" do
      v = Var.new(:m)
      assert compose(%{marks: [%{type: :line}]}, %{marks: v}) == {:ok, %{marks: v}}
      assert compose(%{marks: v}, %{marks: [%{type: :line}]}) == {:ok, %{marks: [%{type: :line}]}}
    end

    @tag verifies: "fragments-rules-each"
    test "a key of the type's own rule merges by the type, under compose and under stack" do
      lower = %{styles: %{"s" => %{fill: %{type: :solid, color: :red}}}}
      higher = %{styles: %{"s" => %{fill: %{color: :blue}}}}

      assert compose(%{style: %{fill: %{type: :solid}}}, %{style: %{fill: %{color: :blue}}}) ==
               {:ok, %{style: %{fill: %{type: :solid, color: :blue}}}}

      assert Fragment.stack(Design, %{style: %{fill: %{type: :solid}}}, %{
               style: %{fill: %{color: :blue}}
             }) ==
               %{style: %{fill: %{type: :solid, color: :blue}}}

      # Under a union name the entry is the higher's whole, the type's rule never reached.
      assert Fragment.stack(Design, lower, higher) == higher
    end
  end

  # -- properties over generated fragments ----------------------------------------------

  @style_names ~w(series muted accent axis label)
  @scale_names ~w(x y color angle)

  defp style, do: optional_map(%{stroke_width: integer(1..5), opacity: float(min: 0.0, max: 1.0)})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time, :band]), nice: boolean()})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 3), &Map.new/1)

  # A union key may be given as a whole-node variable: one in five.
  defp declaration(pool, gen),
    do: frequency([{4, names(pool, gen)}, {1, map(member_of([:sheet, :other]), &Var.new/1)}])

  defp mark,
    do:
      fixed_map(%{
        type: member_of([:line, :area]),
        data: constant("p"),
        channels: constant(%{x: "t", y: "v"})
      })

  defp label,
    do:
      fixed_map(%{
        anchor: member_of([:title, :caption]),
        text: list_of(string(:alphanumeric), max_length: 2)
      })

  defp frame do
    optional_map(%{
      kind: member_of([:cartesian, :polar]),
      size: fixed_map(%{width: integer(100..900), height: integer(100..900)}),
      scales: declaration(@scale_names, scale()),
      axes:
        list_of(fixed_map(%{scale: member_of(@scale_names), side: member_of([:top, :left])}),
          max_length: 2
        )
    })
  end

  defp fragment do
    optional_map(%{
      version: constant(1),
      theme: member_of([:default, :dark]),
      sources: declaration(~w(primary other), fixed_map(%{fields: constant(["t", "v"])})),
      styles: declaration(@style_names, style()),
      vars: declaration(~w(unit n), fixed_map(%{default: integer()})),
      frames: fixed_map(%{"main" => frame()}),
      marks: list_of(mark(), max_length: 3),
      labels: list_of(label(), max_length: 3)
    })
  end

  @tag verifies: "fragments-compose-union"
  property "collections concatenate and scalars are the later's" do
    check all(a <- fragment(), b <- fragment()) do
      case compose(a, b) do
        {:ok, merged} ->
          assert foreign_structs(merged) == []
          assert Map.get(merged, :marks) == concat(a, b, :marks)
          assert Map.get(merged, :labels) == concat(a, b, :labels)
          assert Map.get(merged, :theme) == later(a, b, :theme)
          assert Map.get(merged, :version) == later(a, b, :version)

          if is_map(a[:frames]) and is_map(b[:frames]) do
            assert Map.get(merged.frames["main"], :size) ==
                     later(a.frames["main"], b.frames["main"], :size)

            assert Map.get(merged.frames["main"], :axes) ==
                     concat(a.frames["main"], b.frames["main"], :axes)
          end

        {:error, faults} ->
          assert Enum.all?(faults, &match?({[_ | _], :conflict}, &1))
          assert Enum.any?(faults, fn {path, _} -> conflicting?(a, b, path) end)
      end
    end
  end

  @tag verifies: "fragments-compose-union"
  property "composition over a list is associative" do
    check all(a <- fragment(), b <- fragment(), c <- fragment()) do
      left = with {:ok, ab} <- compose(a, b), do: compose(ab, c)
      right = with {:ok, bc} <- compose(b, c), do: compose(a, bc)

      case {left, right} do
        {{:ok, l}, {:ok, r}} -> assert l == r
        {{:error, _}, {:error, _}} -> :ok
        _mixed -> flunk("one grouping composed and the other conflicted")
      end

      assert compose([a, b, c]) == left
    end
  end

  @tag verifies: "fragments-compose-union"
  property "union keys compose the same in either order when nothing conflicts" do
    check all(a <- fragment(), b <- fragment()) do
      with {:ok, ab} <- compose(a, b), {:ok, ba} <- compose(b, a) do
        assert Map.get(ab, :styles) == Map.get(ba, :styles)
        assert Map.get(ab, :vars) == Map.get(ba, :vars)
      end
    end
  end

  defp concat(a, b, key) do
    case {Map.fetch(a, key), Map.fetch(b, key)} do
      {{:ok, x}, {:ok, y}} -> x ++ y
      {{:ok, x}, :error} -> x
      {:error, {:ok, y}} -> y
      {:error, :error} -> nil
    end
  end

  defp later(a, b, key), do: Map.get(b, key, Map.get(a, key))

  # No walk may produce a struct carrying keys its definition does not declare.
  defp foreign_structs(v) when is_struct(v),
    do: if(Map.keys(v) == Map.keys(struct(v.__struct__, name: "x")), do: [], else: [v])

  defp foreign_structs(v) when is_map(v),
    do: Enum.flat_map(v, fn {_k, e} -> foreign_structs(e) end)

  defp foreign_structs(v) when is_list(v), do: Enum.flat_map(v, &foreign_structs/1)
  defp foreign_structs(_v), do: []

  defp conflicting?(a, b, path) do
    x = get_in(a, Enum.map(path, &Access.key(&1, nil)))
    y = get_in(b, Enum.map(path, &Access.key(&1, nil)))
    x != nil and y != nil and x != y
  end
end
