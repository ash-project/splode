defmodule Splode do
  @moduledoc """
  Use this module to create your error aggregator and handler.

  For example:

  ```elixir
  defmodule MyApp.Errors do
    use Splode, error_classes: [
      invalid: MyApp.Errors.Invalid,
      unknown: MyApp.Errors.Unknown
    ],
    unknown_error: MyApp.Errors.Unknown.Unknown
  end
  ```
  """

  @doc """
  Returns true if the given value is a splode error.
  """
  @callback splode_error?(term) :: boolean()

  @doc """
  Sets the path on the error or errors
  """
  @callback set_path(Splode.Error.t() | [Splode.Error.t()], term | list(term)) ::
              Splode.Error.t() | [Splode.Error.t()]

  @doc """
  Combine errors into an error class
  """
  @callback to_class(any()) :: Splode.Error.t()

  @doc """
  Turns any value into a splode error
  """
  @callback to_error(any()) :: Splode.Error.t()
  @doc """
  Converts a combination of a module and json input into an Splode exception.

  This allows for errors to be serialized and deserialized
  """
  @callback from_json(module, map) :: Splode.Error.t()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], generated: true, location: :keep do
      @behaviour Splode
      @error_classes Keyword.put_new(
                       List.wrap(opts[:error_classes]),
                       :unknown,
                       Splode.Error.Unknown
                     )

      @unknown_error opts[:unknown_error] ||
                       raise(
                         ArgumentError,
                         "must supply the `unknown_error` option, pointing at a splode error to use in situations where we cannot convert an error."
                       )

      if Enum.empty?(opts[:error_classes]) do
        raise ArgumentError,
              "must supply at least one error class to `use Splode`, via `use Splode, error_classes: [class: ModuleForClass]`"
      end

      @type error_class() ::
              unquote(@error_classes |> Keyword.keys() |> Enum.reduce(&{:|, [], [&1, &2]}))

      @type class_module() ::
              unquote(@error_classes |> Keyword.values() |> Enum.reduce(&{:|, [], [&1, &2]}))

      @type t :: %{
              required(:__struct__) => module(),
              required(:__exception__) => true,
              required(:class) => error_class(),
              required(:bread_crumbs) => list(String.t()),
              required(:vars) => Keyword.t(),
              required(:stacktrace) => Splode.Stacktrace.t() | nil,
              required(:context) => map(),
              optional(atom) => any
            }

      @type class :: %{
              required(:__struct__) => class_module(),
              required(:__exception__) => true,
              required(:errors) => list(t()),
              required(:class) => error_class(),
              required(:bread_crumbs) => list(String.t()),
              required(:vars) => Keyword.t(),
              required(:stacktrace) => Splode.Stacktrace.t() | nil,
              required(:context) => map(),
              optional(atom) => any
            }

      @class_modules Keyword.values(@error_classes) |> Enum.reject(&is_nil/1)

      @error_class_indices @error_classes |> Keyword.keys() |> Enum.with_index() |> Enum.into(%{})

      @impl true
      def set_path(errors, path) when is_list(errors) do
        Enum.map(errors, &set_path(&1, path))
      end

      def set_path(error, path) when is_map(error) do
        path = List.wrap(path)

        error =
          if Map.has_key?(error, :path) && is_list(error.path) do
            %{error | path: path ++ error.path}
          else
            error
          end

        error =
          if Map.has_key?(error, :changeset) && error.changeset do
            %{
              error
              | changeset: %{error.changeset | errors: set_path(error.changeset.errors, path)}
            }
          else
            error
          end

        if Map.has_key?(error, :errors) && is_list(error.errors) do
          %{error | errors: Enum.map(error.errors, &set_path(&1, path))}
        else
          error
        end
      end

      def set_path(error, _), do: error

      @impl true
      def splode_error?(%struct{}) do
        struct.splode_error?()
      rescue
        _ ->
          false
      end

      def splode_error?(_), do: false

      def splode_error?(%struct{splode: splode}, splode) do
        struct.splode_error?()
      rescue
        _ ->
          false
      end

      def splode_error?(%struct{splode: nil}, _splode) do
        struct.splode_error?()
      rescue
        _ ->
          false
      end

      def splode_error?(_, _), do: false

      @impl true
      def to_class(value, opts \\ [])

      def to_class(%struct{errors: [error]} = class, _opts)
          when struct in @class_modules do
        if error.class == :special do
          error
        else
          class
        end
      end

      def to_class(value, opts) when not is_list(value) do
        if splode_error?(value) && value.class == :special do
          Map.put(value, :splode, __MODULE__)
        else
          to_class([value], opts)
        end
      end

      def to_class(values, opts) when is_list(values) do
        errors =
          if Keyword.keyword?(values) && values != [] do
            [to_error(values, Keyword.delete(opts, :bread_crumbs))]
          else
            Enum.map(values, &to_error(&1, Keyword.delete(opts, :bread_crumbs)))
          end

        if Enum.count_until(errors, 2) == 1 &&
             Enum.at(errors, 0).class == :special do
          List.first(errors)
        else
          values
          |> flatten_preserving_keywords()
          |> Enum.uniq_by(&clear_stacktraces/1)
          |> Enum.map(fn value ->
            if splode_error?(value, __MODULE__) do
              Map.put(value, :splode, __MODULE__)
            else
              exception_opts =
                if opts[:stacktrace] do
                  [
                    error: value,
                    stacktrace: %Splode.Stacktrace{stacktrace: opts[:stacktrace]},
                    splode: __MODULE__
                  ]
                else
                  [error: value, splode: __MODULE__]
                end

              @unknown_error.exception(exception_opts)
            end
          end)
          |> choose_error()
          |> accumulate_bread_crumbs(opts[:bread_crumbs])
          |> Map.put(:splode, __MODULE__)
        end
      end

      defp choose_error([]) do
        @error_classes[:unknown].exception(splode: __MODULE__)
      end

      defp choose_error(errors) do
        errors = Enum.map(errors, &to_error/1)

        [error | other_errors] =
          Enum.sort_by(errors, fn error ->
            # the second element here sorts errors that are already parent errors
            {Map.get(@error_class_indices, error.class),
             @error_classes[error.class] != error.__struct__}
          end)

        parent_error_module = @error_classes[error.class]

        if parent_error_module == error.__struct__ do
          %{error | errors: (error.errors || []) ++ other_errors}
        else
          parent_error_module.exception(errors: errors, splode: __MODULE__)
        end
      end

      @impl true
      def to_error(value, opts \\ [])

      def to_error(list, opts) when is_list(list) do
        if Keyword.keyword?(list) do
          list
          |> Keyword.take([:error, :vars])
          |> Keyword.put_new(:error, list[:message])
          |> Keyword.put_new(:value, list)
          |> Keyword.put(:splode, __MODULE__)
          |> @unknown_error.exception()
          |> add_stacktrace(opts[:stacktrace])
          |> accumulate_bread_crumbs(opts[:bread_crumbs])
        else
          case list do
            [item] ->
              to_error(item, opts)

            list ->
              to_class(list, opts)
          end
        end
      end

      def to_error(error, opts) when is_binary(error) do
        [error: error, splode: __MODULE__]
        |> @unknown_error.exception()
        |> Map.put(:stacktrace, nil)
        |> add_stacktrace(opts[:stacktrace])
        |> accumulate_bread_crumbs(opts[:bread_crumbs])
      end

      def to_error(other, opts) do
        cond do
          splode_error?(other, __MODULE__) ->
            other
            |> Map.put(:splode, __MODULE__)
            |> add_stacktrace(opts[:stacktrace])
            |> accumulate_bread_crumbs(opts[:bread_crumbs])

          is_exception(other) ->
            [error: Exception.format(:error, other), splode: __MODULE__]
            |> @unknown_error.exception()
            |> Map.put(:stacktrace, nil)
            |> add_stacktrace(opts[:stacktrace])
            |> accumulate_bread_crumbs(opts[:bread_crumbs])

          true ->
            [error: "unknown error: #{inspect(other)}", splode: __MODULE__]
            |> @unknown_error.exception()
            |> Map.put(:stacktrace, nil)
            |> add_stacktrace(opts[:stacktrace])
            |> accumulate_bread_crumbs(opts[:bread_crumbs])
        end
      end

      defp flatten_preserving_keywords(list) do
        if Keyword.keyword?(list) do
          [list]
        else
          Enum.flat_map(list, fn item ->
            cond do
              Keyword.keyword?(item) ->
                [item]

              is_list(item) ->
                flatten_preserving_keywords(item)

              true ->
                [item]
            end
          end)
        end
      end

      defp add_stacktrace(%{stacktrace: _} = error, stacktrace) do
        stacktrace =
          case stacktrace do
            %Splode.Stacktrace{stacktrace: nil} ->
              nil

            nil ->
              nil

            stacktrace ->
              %Splode.Stacktrace{stacktrace: stacktrace}
          end

        %{error | stacktrace: stacktrace || error.stacktrace || fake_stacktrace()}
      end

      defp add_stacktrace(e, _), do: e

      defp fake_stacktrace do
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
        %Splode.Stacktrace{stacktrace: Enum.drop(stacktrace, 3)}
      end

      defp accumulate_bread_crumbs(error, bread_crumbs) when is_list(bread_crumbs) do
        bread_crumbs
        |> Enum.reverse()
        |> Enum.reduce(error, &accumulate_bread_crumbs(&2, &1))
      end

      defp accumulate_bread_crumbs(%{errors: [_ | _] = errors} = error, bread_crumbs)
           when is_binary(bread_crumbs) do
        updated_errors = accumulate_bread_crumbs(errors, bread_crumbs)

        add_bread_crumbs(%{error | errors: updated_errors}, bread_crumbs)
      end

      defp accumulate_bread_crumbs(errors, bread_crumbs)
           when is_list(errors) and is_binary(bread_crumbs) do
        Enum.map(errors, &add_bread_crumbs(&1, bread_crumbs))
      end

      defp accumulate_bread_crumbs(error, bread_crumbs) do
        add_bread_crumbs(error, bread_crumbs)
      end

      defp add_bread_crumbs(error, bread_crumbs) when is_list(bread_crumbs) do
        bread_crumbs
        |> Enum.reverse()
        |> Enum.reduce(error, &add_bread_crumbs(&2, &1))
      end

      defp add_bread_crumbs(error, bread_crumb) when is_binary(bread_crumb) do
        %{error | bread_crumbs: [bread_crumb | error.bread_crumbs]}
      end

      defp add_bread_crumbs(error, _) do
        error
      end

      @impl true
      def from_json(module, json) do
        {handled, unhandled} = process_known_json_keys(json)

        unhandled =
          Map.update(unhandled, "vars", [], fn vars ->
            Map.to_list(vars)
          end)

        json = Map.merge(unhandled, handled)

        module.from_json(json)
      end

      defp process_known_json_keys(json) do
        {handled, unhandled} = Map.split(json, ~w(field fields message path))

        handled =
          handled
          |> update_if_present("field", &String.to_existing_atom/1)
          |> update_if_present("fields", fn fields ->
            fields
            |> List.wrap()
            |> Enum.map(&Splode.Error.atomize_safely/1)
          end)
          |> update_if_present("path", fn item ->
            item
            |> List.wrap()
            |> Enum.map(fn
              item when is_integer(item) ->
                item

              item when is_binary(item) ->
                case Integer.parse(item) do
                  {integer, ""} -> integer
                  _ -> item
                end
            end)
          end)

        {handled, unhandled}
      end

      defp clear_stacktraces(%{stacktrace: stacktrace} = error) when not is_nil(stacktrace) do
        clear_stacktraces(%{error | stacktrace: nil})
      end

      defp clear_stacktraces(%{errors: errors} = exception) when is_list(errors) do
        %{exception | errors: Enum.map(errors, &clear_stacktraces/1)}
      end

      defp clear_stacktraces(error), do: error

      defp update_if_present(handled, key, fun) do
        if Map.has_key?(handled, key) do
          Map.update!(handled, key, fun)
        else
          handled
        end
      end

      defoverridable set_path: 2
    end
  end
end
