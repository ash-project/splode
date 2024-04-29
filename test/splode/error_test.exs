defmodule Splode.ErrorTest do
  use ExUnit.Case

  defmodule InvalidAttribute do
    use Splode.Error, fields: [:message], class: :invalid
  end

  test "message" do
    invalid = %InvalidAttribute{message: "must be in %{list}", vars: [list: [:foo, :bar]]}
    assert "must be in [:foo, :bar]" == invalid |> Exception.message()
  end
end
