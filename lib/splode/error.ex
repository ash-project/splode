defmodule Splode.Error do
  @moduledoc """
  Use this module to create an aggregatable error.

  For example:

  ```elixir
  defmodule MyApp.Errors.InvalidArgument do
    use Splode.Error, fields: [:name, :message], class: :invalid

    def splode_message(%{name: name, message: message}) do
      "Invalid argument \#{name}: \#{message}"
    end
  end
  ```
  """
  @callback splode_error?() :: boolean()
  @callback from_json(map) :: struct()
  @callback splode_message(struct()) :: String.t()
  @type t :: Exception.t()

  @doc false
  def atomize_safely(value) do
    String.to_existing_atom(value)
  rescue
    _ ->
      :unknown
  end

  defmacro __using__(opts) do
    quote generated: true, bind_quoted: [opts: opts] do
      @behaviour Splode.Error

      if !opts[:class] do
        raise "Must provide an error class for a splode error, i.e `use Splode.Error, class: :invalid`"
      end

      defexception List.wrap(opts[:fields]) ++
                     [
                       bread_crumbs: [],
                       vars: [],
                       path: [],
                       stacktrace: nil,
                       class: opts[:class]
                     ]

      @impl Splode.Error
      def splode_error?, do: true

      @impl Exception
      def message(%{vars: vars} = exception) do
        string = splode_message(exception)

        string =
          case Splode.ErrorClass.bread_crumb(exception.bread_crumbs) do
            "" ->
              string

            context ->
              context <> "\n" <> string
          end

        Enum.reduce(List.wrap(vars), string, fn {key, value}, acc ->
          if String.contains?(acc, "%{#{key}}") do
            String.replace(acc, "%{#{key}}", to_string(value))
          else
            acc
          end
        end)
      end

      @impl Exception
      def exception(opts) do
        opts =
          if is_nil(opts[:stacktrace]) do
            {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

            Keyword.put(opts, :stacktrace, %Splode.Stacktrace{stacktrace: stacktrace})
          else
            opts
          end

        super(opts) |> Map.update(:vars, [], &Splode.Error.clean_vars/1)
      end

      @impl Splode.Error
      def from_json(json) do
        keyword =
          json
          |> Map.to_list()
          |> Enum.map(fn {key, value} -> {Splode.Error.atomize_safely(key), value} end)

        exception(keyword)
      end

      defoverridable exception: 1, from_json: 1
    end
  end

  @doc false
  def clean_vars(vars) when is_map(vars) do
    clean_vars(Map.to_list(vars))
  end

  def clean_vars(vars) do
    vars |> Kernel.||([]) |> Keyword.drop([:field, :message, :path])
  end
end
