# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Splode.ErrorTest do
  alias Splode.Stacktrace
  use ExUnit.Case

  defmodule InvalidAttribute do
    use Splode.Error, fields: [:message], class: :invalid
  end

  test "message" do
    invalid = %InvalidAttribute{message: "must be in %{list}", vars: [list: [:foo, :bar]]}
    assert "must be in [:foo, :bar]" == invalid |> Exception.message()
  end

  test "stacktrace" do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

    assert %Stacktrace{} = InvalidAttribute.exception(stacktrace: stacktrace).stacktrace
  end
end
