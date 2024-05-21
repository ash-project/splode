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
        interaction: ContainerErrorClass
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

  test "merge_error?" do
    assert SystemError.merge_error?(HwError.exception(splode: SystemError))
    assert SystemError.merge_error?(SwError.exception(splode: SystemError))

    assert SystemError.merge_error?(CpuError.exception(splode: SystemError))
    assert SystemError.merge_error?(RamError.exception(splode: SystemError))
    assert SystemError.merge_error?(DivByZeroException.exception(splode: SystemError))
    assert SystemError.merge_error?(NullReferenceException.exception(splode: SystemError))
    assert SystemError.merge_error?(UnknownError.exception(splode: SystemError))

    assert ContainerError.merge_error?(ContainerErrorClass.exception(splode: ContainerError))
    assert ContainerError.merge_error?(HwError.exception(splode: ContainerError))
    assert ContainerError.merge_error?(SwError.exception(splode: ContainerError))

    assert ContainerError.merge_error?(CpuError.exception(splode: ContainerError))
    assert ContainerError.merge_error?(RamError.exception(splode: ContainerError))
    assert ContainerError.merge_error?(DivByZeroException.exception(splode: ContainerError))
    assert ContainerError.merge_error?(NullReferenceException.exception(splode: ContainerError))
    assert ContainerError.merge_error?(UnknownError.exception(splode: ContainerError))

    assert ContainerWithoutMergeWith.merge_error?(
             ContainerErrorClass.exception(splode: ContainerWithoutMergeWith)
           )

    refute ContainerWithoutMergeWith.merge_error?(HwError.exception(splode: SystemError))
    refute ContainerWithoutMergeWith.merge_error?(SwError.exception(splode: SystemError))
    refute ContainerWithoutMergeWith.merge_error?(CpuError.exception(splode: SystemError))
    refute ContainerWithoutMergeWith.merge_error?(RamError.exception(splode: SystemError))

    refute ContainerWithoutMergeWith.merge_error?(
             DivByZeroException.exception(splode: SystemError)
           )

    refute ContainerWithoutMergeWith.merge_error?(
             NullReferenceException.exception(splode: SystemError)
           )

    refute ContainerWithoutMergeWith.merge_error?(UnknownError.exception(splode: SystemError))
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

      container_unknown_error =
        ContainerUnknownError.exception(error: hw_error, splode: SystemError)

      interaction_error =
        ContainerErrorClass.exception(errors: [container_unknown_error, example_container_error])
        |> ContainerError.to_error()

      assert %{errors: [^cpu, ^ram, ^example_container_error]} = interaction_error
    end

    test "to_error flattens multiple levels", %{
      cpu: cpu,
      ram: ram,
      example_container_error: example_container_error
    } do
      hw_error = [cpu, ram] |> SystemError.to_class()

      container_unknown_error =
        ContainerUnknownError.exception(error: hw_error, splode: SystemError)

      interaction_error =
        ContainerErrorClass.exception(
          errors: [container_unknown_error, example_container_error],
          splode: ContainerError
        )

      container_unknown_error2 =
        ContainerUnknownError.exception(error: interaction_error, splode: ContainerError)

      interaction_error2 =
        ContainerErrorClass.exception(errors: [container_unknown_error2])
        |> ContainerError.to_error()

      assert %{errors: [^cpu, ^ram, ^example_container_error]} = interaction_error2
    end

    test "to_error doesn't flatten nested errors when not included in merge_with", %{
      cpu: cpu,
      ram: ram,
      example_container_error: example_container_error
    } do
      hw_error =
        [cpu, ram]
        |> SystemError.to_class()

      another_unknown_error =
        ContainerUnknownError.exception(error: hw_error, splode: SystemError)

      interaction_error =
        ContainerErrorClass.exception(errors: [another_unknown_error, example_container_error])
        |> ContainerWithoutMergeWith.to_error()

      assert %{errors: [^another_unknown_error, ^example_container_error]} = interaction_error
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
end
