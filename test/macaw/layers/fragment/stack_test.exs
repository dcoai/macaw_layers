defmodule Macaw.Layers.Fragment.StackTest do
  # The cascade (spec/02 §3.2), ported from visualize's `Chart.StackTest` over a test type
  # that declares visualize's design rules, names held as strings. visualize's cases that
  # draw or validate a chart stay in visualize.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Macaw.Layers.{Fragment, Var}
  alias Macaw.Layers.Test.Design

  @theme %{version: 2, theme: :default, styles: %{"series" => %{stroke_width: 1}}}
  @frame %{
    version: 2,
    frames: %{
      "main" => %{
        kind: :cartesian,
        margin: %{top: 10, right: 10, bottom: 30, left: 40},
        scales: %{"x" => %{kind: :time}, "y" => %{kind: :linear}},
        axes: [%{scale: "x", side: :bottom, ticks: 6}]
      }
    }
  }
  @house %{
    theme: :dark,
    styles: %{"series" => %{stroke: :series_2, stroke_width: 2}, "muted" => %{opacity: 0.5}}
  }
  @panel %{
    sources: %{"primary" => %{fields: ["t", "v"]}},
    frames: %{
      "main" => %{
        scales: %{"y" => %{kind: :linear, domain: [0, :auto]}},
        axes: [%{scale: "y", side: :left, grid: true}]
      }
    },
    marks: [%{type: :line, data: "primary", channels: %{x: "t", y: "v"}, style: "series"}],
    labels: [%{anchor: :title, text: ["Uptime"]}]
  }

  defp stack(layers), do: Fragment.stack(Design, layers)
  defp stack(a, b), do: Fragment.stack(Design, a, b)
  defp compose(a, b), do: Fragment.compose(Design, a, b)

  describe "stack/2 of a list" do
    @tag verifies: "fragments-cascade-identity"
    test "four layers stack into one fragment, the higher layer's word at every key" do
      design = stack([@theme, @frame, @house, @panel])

      assert design.theme == :dark
      assert design.styles["series"] == %{stroke: :series_2, stroke_width: 2}
      assert design.styles["muted"] == %{opacity: 0.5}
      assert design.frames["main"].kind == :cartesian
      assert design.frames["main"].margin == @frame.frames["main"].margin
      assert design.frames["main"].scales |> Map.keys() |> Enum.sort() == ["x", "y"]
      assert design.frames["main"].scales["y"] == %{kind: :linear, domain: [0, :auto]}
      assert Enum.map(design.frames["main"].axes, & &1.scale) == ["x", "y"]
      assert design.marks == @panel.marks
    end

    @tag verifies: "fragments-stack-algebra"
    test "swapping a layer changes what it said; the empty stack is empty, one layer is itself, a stack is a layer" do
      other = %{@house | styles: %{"series" => %{stroke: :series_3, stroke_width: 4}}}
      a = stack([@theme, @frame, @house, @panel])
      b = stack([@theme, @frame, other, @panel])
      assert Map.delete(a, :styles) == Map.delete(b, :styles)

      assert stack([]) == %{}
      assert stack([@panel]) == @panel
      assert stack([@theme, @frame]) == stack(@theme, @frame)

      assert stack([stack([@theme, @frame]), @house, @panel]) ==
               stack([@theme, @frame, @house, @panel])

      assert stack([{:named, @panel}]) == @panel
    end
  end

  describe "stack/3, key by key" do
    @tag verifies: "fragments-cascade-identity"
    test "a scalar is the higher's, a union name the higher's entry whole where compose conflicts" do
      assert stack(%{version: 2, theme: :default}, %{theme: :dark}) == %{version: 2, theme: :dark}

      lower = %{styles: %{"series" => %{stroke: :series_1, stroke_width: 2}}}
      higher = %{styles: %{"series" => %{stroke_width: 3}}}
      assert stack(lower, higher) == %{styles: %{"series" => %{stroke_width: 3}}}
      assert compose(lower, higher) == {:error, [{[:styles, "series"], :conflict}]}

      assert stack(%{vars: %{"unit" => %{default: "%"}}, sources: %{"a" => %{fields: ["t"]}}}, %{
               vars: %{"n" => %{default: 3}}
             }) ==
               %{
                 vars: %{"unit" => %{default: "%"}, "n" => %{default: 3}},
                 sources: %{"a" => %{fields: ["t"]}}
               }
    end

    @tag verifies: "fragments-cascade-identity"
    test "collections append, and a node both give as a map cascades key by key" do
      lower = %{marks: [%{type: :line, data: "p", channels: %{}}], labels: [%{anchor: :caption}]}
      higher = %{marks: [%{type: :rule, data: "p", channels: %{}}]}
      assert stack(lower, higher).marks == lower.marks ++ higher.marks
      assert stack(lower, higher).labels == lower.labels

      assert stack(%{frames: %{"main" => %{kind: :polar, margin: %{top: 10}}}}, %{
               frames: %{"main" => %{margin: %{top: 30}}}
             }) ==
               %{frames: %{"main" => %{kind: :polar, margin: %{top: 30}}}}
    end

    @tag verifies: "fragments-rules-each"
    test "a node either layer gives as anything else is the higher's whole; every union key reads a variable so" do
      var = Var.new(:frame)
      assert stack(%{frames: %{"main" => %{kind: :polar}}}, %{frames: var}) == %{frames: var}

      assert stack(%{frames: var}, %{frames: %{"main" => %{kind: :polar}}}) == %{
               frames: %{"main" => %{kind: :polar}}
             }

      assert stack(%{theme: :dark}, %{theme: %{name: "house"}}) == %{theme: %{name: "house"}}

      v = Var.new(:v)

      for {declared, variable, path} <- [
            {%{sources: %{"p" => %{fields: ["t"]}}}, %{sources: v}, [:sources]},
            {%{vars: %{"unit" => %{default: "%"}}}, %{vars: v}, [:vars]},
            {%{styles: %{"series" => %{stroke_width: 2}}}, %{styles: v}, [:styles]},
            {%{frames: %{"main" => %{scales: %{"x" => %{kind: :time}}}}},
             %{frames: %{"main" => %{scales: v}}}, [:frames, "main", :scales]}
          ] do
        assert stack(declared, variable) == variable
        assert stack(variable, declared) == declared
        assert stack(variable, variable) == variable
        assert compose(declared, variable) == {:error, [{path, :conflict}]}
      end
    end

    @tag verifies: "fragments-stack-algebra"
    test "a layer replacing a mergeable key whole is an erasure, so regrouping may differ" do
      a = %{vars: %{"n" => %{default: 0}}}
      b = %{vars: Var.new(:sheet)}
      c = %{vars: %{}}
      assert stack([a, b, c]) == %{vars: %{}}
      assert stack(stack(a, b), c) == %{vars: %{}}
      assert stack(a, stack(b, c)) == %{vars: %{"n" => %{default: 0}}}

      f = %{frames: %{"main" => %{kind: :polar}}}
      g = %{frames: Var.new(:f)}
      h = %{frames: %{"main" => %{margin: %{top: 1}}}}
      assert stack([f, g, h]) == %{frames: %{"main" => %{margin: %{top: 1}}}}
      assert stack(f, stack(g, h)) == %{frames: %{"main" => %{kind: :polar, margin: %{top: 1}}}}
    end

    @tag verifies: "fragments-cascade-identity"
    test "an unknown key is the higher's, and a key one layer alone carries is taken as it is" do
      assert stack(%{extra: 1, marks: [1]}, %{extra: 2, marks: [2]}) == %{extra: 2, marks: [1, 2]}
      assert stack(%{}, @panel) == @panel
      assert stack(@panel, %{}) == @panel
    end
  end

  describe "element identity" do
    @tag verifies: "fragments-cascade-identity"
    test "a higher mark with the same id replaces it whole in place; one with none, or a new id, appends" do
      lower = %{
        marks: [
          %{id: "series", type: :line, data: "p", channels: %{x: "t", y: "v"}},
          %{type: :rule, data: "d", channels: %{x: "at"}}
        ]
      }

      higher = %{marks: [%{id: "series", type: :area, data: "p", channels: %{x: "t"}}]}

      assert stack(lower, higher).marks == [
               %{id: "series", type: :area, data: "p", channels: %{x: "t"}},
               %{type: :rule, data: "d", channels: %{x: "at"}}
             ]

      plain = %{marks: [%{type: :line, data: "p", channels: %{}}]}
      assert stack(plain, plain).marks == plain.marks ++ plain.marks

      a = %{marks: [%{id: "a", type: :line}]}
      b = %{marks: [%{id: "b", type: :area}]}
      assert stack(a, b).marks == a.marks ++ b.marks
    end

    @tag verifies: "fragments-cascade-identity"
    test "a label with the same id replaces where compose keeps both; identity matches within one key" do
      lower = %{labels: [%{id: "title", anchor: :title, text: ["House"]}]}
      higher = %{labels: [%{id: "title", anchor: :title, text: ["Panel"]}]}
      assert stack(lower, higher).labels == higher.labels
      assert {:ok, composed} = compose(lower, higher)
      assert composed.labels == lower.labels ++ higher.labels

      marks = %{marks: [%{id: "a", type: :line}]}
      labels = %{labels: [%{id: "a", anchor: :title}]}
      stacked = stack(marks, labels)
      assert stacked.marks == marks.marks and stacked.labels == labels.labels
    end

    @tag verifies: "fragments-cascade-identity"
    test "two axes for one scale and side collapse to the higher's; another side is another axis" do
      lower = %{
        frames: %{
          "main" => %{axes: [%{scale: "x", side: :bottom, ticks: 6}, %{scale: "y", side: :left}]}
        }
      }

      higher = %{
        frames: %{"main" => %{axes: [%{scale: "x", side: :bottom, grid: true, style: "heavy"}]}}
      }

      assert stack(lower, higher).frames["main"].axes == [
               %{scale: "x", side: :bottom, grid: true, style: "heavy"},
               %{scale: "y", side: :left}
             ]

      top = %{frames: %{"main" => %{axes: [%{scale: "x", side: :top}]}}}
      assert length(stack(lower, top).frames["main"].axes) == 3
    end

    @tag verifies: "fragments-cascade-identity"
    test "elements with no identity are a sequence; duplicates collapse to first position and last value" do
      step = %{op: :filter, field: "v"}
      lower = %{marks: [%{type: :rect, data: %{source: "p", transforms: [step]}, channels: %{}}]}
      assert stack(lower, lower).marks == lower.marks ++ lower.marks

      dup = %{marks: [%{id: "a", type: :line}, %{id: "a", type: :area}]}
      assert stack(dup, %{marks: []}).marks == [%{id: "a", type: :area}]
      assert stack(%{marks: []}, dup).marks == [%{id: "a", type: :area}]
      assert stack(%{}, dup) == dup
      assert stack([dup]) == dup
    end
  end

  # -- properties over generated fragments ----------------------------------------------

  @style_names ~w(series muted accent)
  @scale_names ~w(x y color)

  defp style, do: optional_map(%{stroke_width: integer(1..5), opacity: float(min: 0.0, max: 1.0)})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time, :band]), nice: boolean()})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 3), &Map.new/1)

  defp declaration(pool, gen),
    do: frequency([{4, names(pool, gen)}, {1, map(member_of([:sheet, :other]), &Var.new/1)}])

  defp label do
    gen all(anchor <- member_of([:title, :caption]), id <- member_of([nil, "head", "foot"])) do
      base = %{anchor: anchor, text: ["t"]}
      if id, do: Map.put(base, :id, id), else: base
    end
  end

  defp mark do
    gen all(type <- member_of([:line, :area]), id <- member_of([nil, "a", "b"])) do
      base = %{type: type, data: "p", channels: %{x: "t", y: "v"}}
      if id, do: Map.put(base, :id, id), else: base
    end
  end

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

  @tag verifies: "fragments-stack-algebra"
  property "the cascade is the left fold, and associative where no layer replaces a mergeable key whole" do
    check all(a <- fragment(), b <- fragment(), c <- fragment()) do
      assert stack([a, b, c]) == stack(stack(a, b), c)

      if Enum.all?([a, b, c], &maps?/1) do
        assert stack(stack(a, b), c) == stack(a, stack(b, c))
      end
    end
  end

  defp maps?(fragment) do
    frames = Map.get(fragment, :frames, %{})

    scales =
      for {_name, frame} <- (is_struct(frames) && %{}) || frames, do: Map.get(frame, :scales, %{})

    Enum.all?([:sources, :styles, :vars, :frames], &(not is_struct(Map.get(fragment, &1, %{})))) and
      Enum.all?(scales, &(not is_struct(&1)))
  end

  @tag verifies: "fragments-stack-algebra"
  property "one layer is itself and the empty fragment is the identity" do
    check all(a <- fragment()) do
      assert stack([a]) == a
      assert stack(%{}, a) == a
      assert stack(a, %{}) == a
    end
  end

  @tag verifies: "fragments-cascade-identity"
  property "an identity both layers declare carries the higher layer's element, once, at the lower's position" do
    check all(a <- fragment(), b <- fragment()) do
      stacked = stack(a, b)

      for key <- [:marks, :labels], unique_ids?(a, key), unique_ids?(b, key) do
        elements = Map.get(stacked, key, [])
        assert ids(elements) == Enum.uniq(ids(elements))

        for id <- shared_ids(a, b, key) do
          assert Enum.find(elements, &(&1[:id] == id)) ==
                   Enum.find(Map.fetch!(b, key), &(&1[:id] == id))

          assert Enum.find_index(elements, &(&1[:id] == id)) ==
                   Enum.find_index(Map.fetch!(a, key), &(&1[:id] == id))
        end
      end
    end
  end

  @tag verifies: "fragments-stack-algebra"
  property "over disjoint fragments the cascade is the union" do
    check all(a <- fragment(), b <- fragment()) do
      case compose(a, b) do
        {:ok, composed} -> if disjoint?(a, b), do: assert(stack(a, b) == composed)
        {:error, _} -> assert is_map(stack(a, b))
      end
    end
  end

  defp ids(elements), do: for(e <- elements, id = e[:id], do: id)

  defp unique_ids?(fragment, key) do
    declared = ids(Map.get(fragment, key, []))
    declared == Enum.uniq(declared)
  end

  defp shared_ids(a, b, key) do
    if Map.has_key?(a, key) and Map.has_key?(b, key),
      do: a |> Map.fetch!(key) |> ids() |> Enum.filter(&(&1 in ids(Map.fetch!(b, key)))),
      else: []
  end

  defp disjoint?(a, b) do
    Enum.all?(
      [:marks, :labels],
      &(shared_ids(a, b, &1) == [] and unique_ids?(a, &1) and unique_ids?(b, &1))
    ) and
      Enum.all?([:sources, :styles, :vars, :theme, :version, :frames], fn key ->
        not (Map.has_key?(a, key) and Map.has_key?(b, key))
      end)
  end
end
