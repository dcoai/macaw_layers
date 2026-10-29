defmodule Macaw.Layers.Theme.RampsTest do
  @moduledoc """
  A theme's meaning-bearing ramps and roles (spec/04 §2.3, §2.6): the shipped themes hold
  their contracts, a theme that breaks one is refused naming the ramp, roles are fixed
  points on the status ramp, and the fallback is the default theme's, never a series color.
  """
  use ExUnit.Case, async: true

  import Macaw.Layers.Color, only: [sigil_RGB: 2]

  alias Macaw.Layers.{Color, Theme}

  @themes [Theme.default(), Theme.dark(), Theme.color_safe()]

  # The D3-compatible sequential schemes visualize's color scales carry, as data.
  @schemes %{
             blues: ~w(#f7fbff #deebf7 #c6dbef #9ecae1 #6baed6 #4292c6 #2171b5 #084594),
             greens: ~w(#f7fcf5 #e5f5e0 #c7e9c0 #a1d99b #74c476 #41ab5d #238b45 #005a32),
             grays: ~w(#ffffff #f0f0f0 #d9d9d9 #bdbdbd #969696 #737373 #525252 #252525),
             oranges: ~w(#fff5eb #fee6ce #fdd0a2 #fdae6b #fd8d3c #f16913 #d94801 #8c2d04),
             purples: ~w(#fcfbfd #efedf5 #dadaeb #bcbddc #9e9ac8 #807dba #6a51a3 #4a1486),
             reds: ~w(#fff5f0 #fee0d2 #fcbba1 #fc9272 #fb6a4a #ef3b2c #cb181d #99000d),
             viridis: ~w(#440154 #482777 #3f4a8a #31678e #26838f #1f9d8a #6cce5a #b6de2b #fee825)
           }
           |> Map.new(fn {name, hexes} -> {name, Enum.map(hexes, &Color.parse!/1)} end)

  defp lch(%Color{} = color), do: Color.to_hcl(color)

  describe "the shipped themes" do
    @tag verifies: "themes-ramps-contracts"
    test "every one holds every ramp and role contract" do
      for theme <- @themes, do: assert(Theme.check(theme) == :ok, inspect(theme.name))
    end

    @tag verifies: "themes-ramps-contracts"
    test "every one carries the four ramps and the two free roles" do
      for theme <- @themes do
        assert theme.ramps |> Map.keys() |> Enum.sort() ==
                 Enum.sort([:status, :thermal, :diverging, :sequential])

        # The roles are names by use in the color table (spec/04 §2.2).
        for role <- Theme.role_names(), do: assert(Map.has_key?(theme.colors, role))
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "status and sequential run away from the background: the low end recedes" do
      for theme <- @themes, ramp <- [:status, :sequential] do
        page = lch(theme.background).l
        low = lch(Theme.ramp(theme, ramp, 0)).l
        high = lch(Theme.ramp(theme, ramp, 1)).l
        assert abs(low - page) < abs(high - page), "#{theme.name} #{ramp}"
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "the status roles hold 3:1 on the light themes' white" do
      for theme <- [Theme.default(), Theme.color_safe()], role <- [:good, :warning, :bad] do
        color = Theme.resolve(theme, role, :literal)
        assert Color.contrast(color, theme.background) >= 3, "#{theme.name} #{role}"
      end
    end

    @tag verifies: "themes-builtins-values"
    test "builtin/1 names the three, and nothing else" do
      assert Enum.map([:default, :dark, :color_safe], &Theme.builtin(&1).name) ==
               [:default, :dark, :color_safe]

      assert Theme.builtin(:house) == nil
    end

    @tag verifies: "themes-ramps-contracts"
    test "the status roles keep good, warning, bad in hue and lightness on every shipped theme" do
      for theme <- @themes do
        [good, warning, bad] =
          Enum.map([:good, :warning, :bad], &lch(Theme.resolve(theme, &1, :literal)))

        # The hue order: green or blue, then amber, then red (spec/04 §2.3).
        assert good.h >= 100 and good.h < 315
        assert warning.h >= 45 and warning.h < 100
        assert bad.h < 45 or bad.h >= 345
        # The lightness order: monotonic, so a reader who sees no hue still reads it.
        assert (good.l - warning.l) * (warning.l - bad.l) > 0, inspect(theme.name)
      end
    end
  end

  describe "contracts refuse a theme that breaks one, naming the ramp" do
    @tag verifies: "themes-ramps-contracts"
    test "reordered status hues" do
      error =
        assert_raise ArgumentError, fn ->
          Theme.new(name: :house, ramps: %{status: [~RGB"#c23238", ~RGB"#bd7407", ~RGB"#4ca34b"]})
        end

      assert error.message =~ "theme \"house\": ramp :status breaks its contract"
      assert error.message =~ "good (0) must be green or blue"
    end

    @tag verifies: "themes-ramps-contracts"
    test "status lightness that is not monotonic" do
      error =
        assert_raise ArgumentError, fn ->
          Theme.new(ramps: %{status: [~RGB"#4ca34b", ~RGB"#e0a030", ~RGB"#c23238"]})
        end

      assert error.message =~ "ramp :status"
      assert error.message =~ "lightness must change one way along the ramp, by at least 3 L*"
      assert error.message =~ ~s(anchor 2 "#e0a030")
    end

    @tag verifies: "themes-ramps-contracts"
    test "sequential lightness that steps by less than the tolerance" do
      assert {:error, {:ramp, :sequential}, message} =
               Theme.check(%{
                 Theme.default()
                 | ramps: %{sequential: [~RGB"#5e95d3", ~RGB"#5a92d0", ~RGB"#004580"]}
               })

      assert message =~ "only"
    end

    @tag verifies: "themes-ramps-contracts"
    test "a status whose hue turns back between its anchors" do
      # Green, then a blue, then amber and red: the ends and the middle are right and the
      # lightness falls, but the hue climbs from green to blue before it falls.
      ramp = [~RGB"#68be64", ~RGB"#65a0e2", ~RGB"#bd7407", ~RGB"#ca4c23", ~RGB"#c23238"]

      assert {:error, {:ramp, :status}, message} =
               Theme.check(%{Theme.default() | ramps: %{status: ramp}})

      assert message =~ "hue must fall from good to bad"
    end

    @tag verifies: "themes-ramps-contracts"
    test "a thermal ramp with no neutral midpoint, and a diverging one of one hue" do
      assert {:error, {:ramp, :thermal}, message} =
               Theme.check(%{
                 Theme.default()
                 | ramps: %{thermal: [~RGB"#0e68ad", ~RGB"#5e95d3", ~RGB"#c02e31"]}
               })

      assert message =~ "midpoint (0.5) must be neutral"

      assert {:error, {:ramp, :diverging}, message} =
               Theme.check(%{
                 Theme.default()
                 | ramps: %{diverging: [~RGB"#b35806", ~RGB"#ededed", ~RGB"#c02e31"]}
               })

      assert message =~ "at least 60° apart"
    end

    @tag verifies: "themes-ramps-contracts"
    test "a sequential ramp of more than one hue family" do
      viridis = @schemes.viridis

      assert {:error, {:ramp, :sequential}, message} =
               Theme.check(%{Theme.default() | ramps: %{sequential: viridis}})

      assert message =~ "one hue family"

      for scheme <- [:blues, :greens, :grays, :oranges, :purples, :reds] do
        sequential = Map.fetch!(@schemes, scheme)
        assert Theme.check(%{Theme.default() | ramps: %{sequential: sequential}}) == :ok
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "roles: info is a blue, neutral is neutral" do
      assert {:error, {:color, :neutral}, _} =
               Theme.check(Theme.build(Theme.default(), colors: %{neutral: ~RGB"#3b6fa8"}))

      assert {:error, {:color, :info}, _} =
               Theme.check(Theme.build(Theme.default(), roles: %{info: ~RGB"#c23238"}))
    end

    @tag verifies: "themes-ramps-contracts"
    test "what is not a ramp, a role or a color" do
      assert_raise ArgumentError, ~r/ramp :heat breaks its contract: is not a ramp/, fn ->
        Theme.new(ramps: %{heat: [~RGB"#fff", ~RGB"#000"]})
      end

      assert_raise ArgumentError,
                   ~r/color :good breaks its contract: "nope" is text, and a string is never a color/,
                   fn ->
                     Theme.new(colors: %{good: "nope"})
                   end

      assert_raise ArgumentError, ~r/color "mine" breaks its contract: names "nope"/, fn ->
        Theme.new(colors: %{mine: {:color, :nope}})
      end

      assert_raise ArgumentError, ~r/color "a" breaks its contract: reaches itself/, fn ->
        Theme.new(colors: %{a: {:color, :b}, b: {:color, :a}})
      end

      assert_raise ArgumentError, ~r/needs at least two anchors/, fn ->
        Theme.new(ramps: %{sequential: [~RGB"#004580"]})
      end

      assert_raise ArgumentError,
                   ~r/anchor 2 "nope" is text, and a string is never a color/,
                   fn ->
                     Theme.new(ramps: %{sequential: [~RGB"#e9f2fc", "nope"]})
                   end

      assert_raise ArgumentError, ~r/anchor 1 :nope is not a color/, fn ->
        Theme.new(ramps: %{sequential: [:nope, ~RGB"#004580"]})
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "a background alone never breaks a contract: lightness may run either way" do
      assert Theme.new(background: ~RGB"#000000").ramps == Theme.default().ramps
      assert Theme.new(background: Color.rgb(0, 0, 0, 0)).name == :default
    end
  end

  describe "ramps and roles resolve" do
    @tag verifies: "themes-resolve-modes"
    test "{:ramp, :status, 0.5} is :warning in every theme, in both modes" do
      for theme <- @themes, mode <- [:literal, :css] do
        for {role, t} <- [good: 0, warning: 0.5, bad: 1, bad: 1.0] do
          assert Theme.resolve(theme, {:ramp, :status, t}, mode) ==
                   Theme.resolve(theme, role, mode)
        end
      end
    end

    @tag verifies: "themes-resolve-modes"
    test "a role is a slot: a CSS reference with its literal" do
      theme = Theme.default()
      assert Theme.resolve(theme, :bad, :css) == "var(--mw-bad, #c23238)"
      assert Theme.resolve(theme, :neutral, :literal) === ~RGB"#6f7480"
    end

    @tag verifies: "themes-ramps-contracts"
    test "a ramp position between anchors is Lab-interpolated, a literal in both modes" do
      theme = Theme.default()
      quarter = Theme.ramp(theme, :thermal, 0.25)

      expected = Color.interpolate_lab(~RGB"#0e68ad", ~RGB"#e8e8e8", 0.5)

      assert quarter === expected
      assert Theme.resolve(theme, {:ramp, :thermal, 0.25}, :literal) === quarter
      assert Theme.resolve(theme, {:ramp, :thermal, 0.25}, :css) == Color.to_css(quarter)
      assert Theme.ramp(theme, :thermal, -1) === ~RGB"#0e68ad"
      assert Theme.ramp(theme, :thermal, 2) === ~RGB"#c02e31"
    end

    @tag verifies: "themes-ramps-contracts"
    test "lightness along a shipped sequential ramp is monotonic at every position" do
      for theme <- @themes do
        ls = for i <- 0..20, do: lch(Theme.ramp(theme, :sequential, i / 20)).l
        assert ls == Enum.sort(ls) or ls == Enum.sort(ls, :desc), inspect(theme.name)
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "an unknown ramp or a position that is not a number raises" do
      assert_raise ArgumentError, ~r/unknown ramp :heat/, fn ->
        Theme.ramp(Theme.default(), :heat, 0.5)
      end

      assert_raise ArgumentError, ~r/a position is a number/, fn ->
        Theme.ramp(Theme.default(), :status, "half")
      end
    end
  end

  describe "fallback is the default theme's, never a series color" do
    @tag verifies: "themes-ramps-contracts"
    test "a struct that lacks a ramp or a role" do
      bare = %{Theme.dark() | ramps: %{}, colors: %{}}
      assert Theme.ramp(bare, :status, 0) == Theme.ramp(Theme.default(), :status, 0)

      assert Theme.resolve(bare, :info, :literal) ==
               Theme.resolve(Theme.default(), :info, :literal)

      refute Theme.resolve(bare, :good, :literal) in bare.series
    end

    @tag verifies: "themes-builtins-values"
    test "new/1 and merge/2 merge ramps and roles key by key" do
      theme = Theme.new(ramps: %{sequential: [~RGB"#fff5eb", ~RGB"#fd8d3c", ~RGB"#8c2d04"]})
      assert theme.ramps.status == Theme.default().ramps.status
      assert theme.ramps.sequential == [~RGB"#fff5eb", ~RGB"#fd8d3c", ~RGB"#8c2d04"]

      night = Theme.merge(Theme.dark(), roles: %{info: ~RGB"#5e95d3"})
      assert night.colors == %{Theme.dark().colors | info: ~RGB"#5e95d3"}
      assert night.ramps == Theme.dark().ramps
    end
  end

  describe "Macaw.Layers.Color's Lab" do
    @tag verifies: "themes-ramps-contracts"
    test "to_lab/1 and lab/4 are each other's inverse" do
      for hex <- ~w(#808080 #3b6fa8 #c8373b #f7f7f7 #000000 #ffffff #4ca34b) do
        %{l: l, a: a, b: b} = hex |> Color.parse() |> Color.to_lab()
        assert Color.to_hex(Color.lab(l, a, b)) == hex
      end
    end

    @tag verifies: "themes-ramps-contracts"
    test "a gray is neutral" do
      for hex <- ~w(#808080 #f7f7f7 #333333) do
        %{a: a, b: b} = hex |> Color.parse() |> Color.to_lab()
        assert abs(a) < 2 and abs(b) < 4
      end

      assert %{a: +0.0, b: +0.0} = "#808080" |> Color.parse() |> Color.to_lab()
    end
  end
end
