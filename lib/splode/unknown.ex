defmodule Splode.Error.Unknown do
  @moduledoc "The default top level unknown error container"
  use Splode.Error, fields: [:errors], class: :unknown

  def splode_message(exception) do
    Splode.ErrorClass.error_messages(exception.errors)
  end

  def exception(opts) do
    if opts[:error] do
      super(Keyword.update(opts, :errors, [opts[:error]], &[opts[:error] | &1]))
    else
      super(opts)
    end
  end
end
