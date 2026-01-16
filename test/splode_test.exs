# SPDX-FileCopyrightText: 2024 splode contributors <https://github.com/ash-project/splode/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule SplodeTest do
  use ExUnit.Case

  # Error classes

  defmodule HwError do
    @moduledoc false
    use Splode.ErrorClass, class: :hw
  end

  defmodule SwError do
    @moduledoc false
    use Splode.ErrorClass, class: :sw
  end

  defmodule ContainerErrorClass do
    @moduledoc false
    use Splode.ErrorClass, class: :ui
  end

  # Errors

  defmodule CpuError do
    @moduledoc false
    use Splode.Error, class: :hw
    def message(err), do: err |> inspect()
  end

  defmodule RamError do
    @moduledoc false
    use Splode.Error, class: :hw
    def message(err), do: err |> inspect()
  end

  defmodule DivByZeroException do
    @moduledoc false
    use Splode.Error, fields: [:num, :denom], class: :sw
    def message(err), do: err |> inspect()
  end

  defmodule NullReferenceException do
    @moduledoc false
    use Splode.Error, class: :sw
    def message(err), do: err |> inspect()
  end

  defmodule UnknownError do
    @moduledoc false
    use Splode.Error, fields: [:error], class: :unknown
    def message(err), do: err |> inspect()
  end

  defmodule ExampleContainerError do
    @moduledoc false
    use Splode.Error, fields: [:description], class: :ui
    def message(err), do: err |> inspect()
  end

  defmodule ContainerUnknownError do
    @moduledoc false
    use Splode.Error, fields: [:error], class: :unknown
    def message(err), do: err |> inspect()
  end

  defmodule SystemError do
    @moduledoc false
    use Splode,
      error_classes: [
        hw: HwError,
        sw: SwError
      ],
      unknown_error: UnknownError
  end

  defmodule ContainerError do
    @moduledoc false
    use Splode,
      error_classes: [
        interaction: ContainerErrorClass,
        hw: HwError,
        sw: SwError
      ],
      unknown_error: ContainerUnknownError,
      merge_with: [SystemError]
  end

  defmodule ContainerWithoutMergeWith do
    @moduledoc false
    use Splode,
      error_classes: [
        interaction: ContainerErrorClass
      ],
      unknown_error: ContainerUnknownError,
      merge_with: []
  end

  defmodule Example do
    def function do
      {:error, "Error"}
    end

    def function! do
      SystemError.unwrap!(function())
    end
  end

  test "splode functions work" do
    assert_raise SplodeTest.UnknownError, ~r/error: "Error"/, fn ->
      Example.function!()
    end
  end

  test "splode_error?" do
    refute SystemError.splode_error?(:error)
    refute SystemError.splode_error?(%{})
    refute SystemError.splode_error?([])

    assert SystemError.splode_error?(HwError.exception())
    assert SystemError.splode_error?(SwError.exception())

    assert SystemError.splode_error?(CpuError.exception())
    assert SystemError.splode_error?(RamError.exception())
    assert SystemError.splode_error?(DivByZeroException.exception())
    assert SystemError.splode_error?(NullReferenceException.exception())
    assert SystemError.splode_error?(UnknownError.exception())
  end

  test "set_path" do
    null = NullReferenceException.exception(path: [:a])
    null = SystemError.set_path(null, :b)

    assert null.path == [:b, :a]
  end

  describe "to_class" do
    setup do
      cpu = CpuError.exception() |> SystemError.to_error()
      ram = RamError.exception() |> SystemError.to_error()
      div = DivByZeroException.exception() |> SystemError.to_error()
      null = NullReferenceException.exception() |> SystemError.to_error()
      example_container_error = ExampleContainerError.exception() |> ContainerError.to_error()

      %{
        cpu: cpu,
        ram: ram,
        div: div,
        null: null,
        example_container_error: example_container_error
      }
    end

    test "wraps errors in error class with same class", %{
      cpu: cpu,
      ram: ram,
      div: div,
      null: null
    } do
      # H/W errors
      hw_error = [cpu, ram] |> SystemError.to_class()
      assert %HwError{errors: [^cpu, ^ram]} = hw_error

      # S/W errors
      sw_error = [div, null] |> SystemError.to_class()
      assert %SwError{errors: [^div, ^null]} = sw_error
    end

    test "error class with smaller index is selected for mixed class case", %{
      cpu: cpu,
      ram: ram,
      div: div,
      null: null
    } do
      errors = [cpu, ram, div, null] |> Enum.shuffle()
      assert %HwError{errors: ^errors} = errors |> SystemError.to_class()
    end

    test "idempotent", %{
      cpu: cpu,
      ram: ram,
      div: div,
      null: null
    } do
      error =
        [cpu, ram, div, null] |> Enum.shuffle() |> Enum.take(2) |> SystemError.to_class()

      assert error == error |> SystemError.to_class()
    end

    test "to_error flattens nested errors when included in merge_with", %{
      cpu: cpu,
      ram: ram,
      example_container_error: example_container_error
    } do
      hw_error = [cpu, ram] |> SystemError.to_class()

      interaction_error = ContainerError.to_class([hw_error, example_container_error])

      assert %{errors: [^cpu, ^ram, ^example_container_error]} = interaction_error
    end

    test "to_error doesn't flatten nested errors when not included in merge_with", %{
      cpu: cpu,
      ram: ram,
      example_container_error: example_container_error
    } do
      hw_error = [cpu, ram] |> SystemError.to_class()

      interaction_error = ContainerWithoutMergeWith.to_class([hw_error, example_container_error])

      assert %{errors: [%SplodeTest.ContainerUnknownError{}, %SplodeTest.ContainerUnknownError{}]} =
               interaction_error
    end
  end

  test "to_error" do
    error_tuple = {:error, :div_by_zero}
    assert %UnknownError{class: :unknown} = SystemError.to_error(error_tuple)

    runtime_error = %RuntimeError{}
    assert %UnknownError{class: :unknown} = SystemError.to_error(runtime_error)

    div_by_zero = DivByZeroException.exception()
    assert %DivByZeroException{} = SystemError.to_error(div_by_zero)
  end

  test "from_json" do
    div_by_zero =
      SystemError.from_json(DivByZeroException, %{"num" => 10, "denom" => 0})

    assert %DivByZeroException{num: 10, denom: 0} = div_by_zero
  end

  describe "filter_stacktraces" do
    defmodule FilteredInternalError do
      @moduledoc false
      use Splode.Error, class: :internal
      def message(err), do: err |> inspect()
    end

    defmodule FilteredInternalErrorClass do
      @moduledoc false
      use Splode.ErrorClass, class: :internal
    end

    defmodule FilteredUnknownError do
      @moduledoc false
      use Splode.Error, fields: [:error], class: :unknown
      def message(err), do: err |> inspect()
    end

    defmodule FilteredErrors do
      @moduledoc false
      use Splode,
        error_classes: [
          internal: FilteredInternalErrorClass
        ],
        unknown_error: FilteredUnknownError,
        filter_stacktraces: [SplodeTest.Internal, "SplodeTest.Internal."]
    end

    defmodule Internal do
      def make_stacktrace do
        # Simulate a stacktrace with internal frames
        [
          {SplodeTest.External, :function, 1, [file: ~c"external.ex", line: 10]},
          {SplodeTest.Internal, :call1, 2, [file: ~c"internal.ex", line: 20]},
          {SplodeTest.Internal.Helper, :call2, 0, [file: ~c"internal.ex", line: 30]},
          {SplodeTest.Internal.Deep, :call3, 1, [file: ~c"internal.ex", line: 40]},
          {SplodeTest.External.Other, :entry, 0, [file: ~c"external.ex", line: 50]},
          {SplodeTest.Internal, :another, 0, [file: ~c"internal.ex", line: 60]},
          {SplodeTest.External.Final, :done, 0, [file: ~c"external.ex", line: 70]}
        ]
      end
    end

    test "filters stacktrace keeping only deepest frame from each sequence of matching modules" do
      stacktrace = Internal.make_stacktrace()

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      filtered = error.stacktrace.stacktrace

      # Should keep: External, Internal.Deep (deepest of first sequence), External.Other,
      # Internal (only one in second sequence), External.Final
      assert length(filtered) == 5

      modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

      assert modules == [
               SplodeTest.External,
               SplodeTest.Internal.Deep,
               SplodeTest.External.Other,
               SplodeTest.Internal,
               SplodeTest.External.Final
             ]
    end

    test "handles stacktrace with no matching modules" do
      stacktrace = [
        {SplodeTest.External, :function, 1, [file: ~c"external.ex", line: 10]},
        {SplodeTest.Other, :call, 2, [file: ~c"other.ex", line: 20]}
      ]

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      # Should be unchanged
      assert error.stacktrace.stacktrace == stacktrace
    end

    test "handles stacktrace with all matching modules" do
      stacktrace = [
        {SplodeTest.Internal, :call1, 1, [file: ~c"internal.ex", line: 10]},
        {SplodeTest.Internal.Helper, :call2, 0, [file: ~c"internal.ex", line: 20]},
        {SplodeTest.Internal.Deep, :call3, 1, [file: ~c"internal.ex", line: 30]}
      ]

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      # Should keep only the deepest (last) one
      filtered = error.stacktrace.stacktrace
      assert length(filtered) == 1
      assert [{SplodeTest.Internal.Deep, :call3, 1, _}] = filtered
    end

    test "filters existing stacktrace on error when passing through to_error" do
      # Create an error with an unfiltered stacktrace
      raw_stacktrace = Internal.make_stacktrace()

      error = FilteredInternalError.exception(stacktrace: raw_stacktrace)

      # Now pass it through to_error which should filter
      processed = FilteredErrors.to_error(error)

      filtered = processed.stacktrace.stacktrace
      modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

      assert modules == [
               SplodeTest.External,
               SplodeTest.Internal.Deep,
               SplodeTest.External.Other,
               SplodeTest.Internal,
               SplodeTest.External.Final
             ]
    end

    defmodule NoFilterErrors do
      @moduledoc false
      use Splode,
        error_classes: [
          internal: FilteredInternalErrorClass
        ],
        unknown_error: FilteredUnknownError
    end

    test "no filtering when filter_stacktraces is not configured" do
      stacktrace = Internal.make_stacktrace()

      error = NoFilterErrors.to_error("test error", stacktrace: stacktrace)

      # Should be unchanged
      assert error.stacktrace.stacktrace == stacktrace
    end

    test "elixir stdlib frames are included in matching sequences but not kept" do
      # Simulates: Internal -> Enum.map -> Stream.reduce -> External
      # The Enum/Stream frames should be filtered out along with Internal
      stacktrace = [
        {SplodeTest.External, :caller, 0, [file: ~c"external.ex", line: 10]},
        {SplodeTest.Internal, :do_work, 1, [file: ~c"internal.ex", line: 20]},
        {Enum, :map, 2, [file: ~c"enum.ex", line: 100]},
        {Stream, :run, 1, [file: ~c"stream.ex", line: 200]},
        {Enumerable.List, :reduce, 3, [file: ~c"enum.ex", line: 300]},
        {SplodeTest.External.Entry, :start, 0, [file: ~c"external.ex", line: 50]}
      ]

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      filtered = error.stacktrace.stacktrace
      modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

      # Should keep External, Internal (deepest of the sequence that includes Enum/Stream), and External.Entry
      assert modules == [
               SplodeTest.External,
               SplodeTest.Internal,
               SplodeTest.External.Entry
             ]
    end

    test "elixir stdlib frames don't start a new sequence on their own" do
      # Enum/Stream frames without a preceding matching module should be kept
      stacktrace = [
        {SplodeTest.External, :caller, 0, [file: ~c"external.ex", line: 10]},
        {Enum, :map, 2, [file: ~c"enum.ex", line: 100]},
        {Stream, :run, 1, [file: ~c"stream.ex", line: 200]},
        {SplodeTest.External.Entry, :start, 0, [file: ~c"external.ex", line: 50]}
      ]

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      # Should be unchanged - Enum/Stream frames are kept when not in a matching sequence
      assert error.stacktrace.stacktrace == stacktrace
    end

    test "multiple matching sequences separated by elixir stdlib frames are merged" do
      # Internal -> Enum -> Internal should be one sequence
      stacktrace = [
        {SplodeTest.External, :caller, 0, [file: ~c"external.ex", line: 10]},
        {SplodeTest.Internal, :first, 1, [file: ~c"internal.ex", line: 20]},
        {Enum, :map, 2, [file: ~c"enum.ex", line: 100]},
        {SplodeTest.Internal.Helper, :second, 0, [file: ~c"internal.ex", line: 30]},
        {SplodeTest.External.Entry, :start, 0, [file: ~c"external.ex", line: 50]}
      ]

      error = FilteredErrors.to_error("test error", stacktrace: stacktrace)

      filtered = error.stacktrace.stacktrace
      modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

      # Internal.Helper is the deepest matching frame in the sequence
      assert modules == [
               SplodeTest.External,
               SplodeTest.Internal.Helper,
               SplodeTest.External.Entry
             ]
    end

    test "filters stacktraces when errors go through to_class" do
      # Create an error with an unfiltered stacktrace
      raw_stacktrace = [
        {SplodeTest.External, :caller, 0, [file: ~c"external.ex", line: 10]},
        {SplodeTest.Internal, :do_work, 1, [file: ~c"internal.ex", line: 20]},
        {Enum, :map, 2, [file: ~c"enum.ex", line: 100]},
        {SplodeTest.External.Entry, :start, 0, [file: ~c"external.ex", line: 50]}
      ]

      error = FilteredInternalError.exception(stacktrace: raw_stacktrace)

      # Pass through to_class (not to_error)
      class_error = FilteredErrors.to_class(error)

      # The nested error should have filtered stacktrace
      nested_error = hd(class_error.errors)
      filtered = nested_error.stacktrace.stacktrace
      modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

      assert modules == [
               SplodeTest.External,
               SplodeTest.Internal,
               SplodeTest.External.Entry
             ]
    end

    test "filters nested error stacktraces in error classes" do
      raw_stacktrace = [
        {SplodeTest.External, :caller, 0, [file: ~c"external.ex", line: 10]},
        {SplodeTest.Internal, :do_work, 1, [file: ~c"internal.ex", line: 20]},
        {SplodeTest.External.Entry, :start, 0, [file: ~c"external.ex", line: 50]}
      ]

      error1 = FilteredInternalError.exception(stacktrace: raw_stacktrace)
      error2 = FilteredInternalError.exception(stacktrace: raw_stacktrace)

      # Combine into a class error
      class_error = FilteredErrors.to_class([error1, error2])

      # Both nested errors should have filtered stacktraces
      for nested_error <- class_error.errors do
        filtered = nested_error.stacktrace.stacktrace
        modules = Enum.map(filtered, fn {mod, _, _, _} -> mod end)

        assert modules == [
                 SplodeTest.External,
                 SplodeTest.Internal,
                 SplodeTest.External.Entry
               ]
      end
    end
  end
end
