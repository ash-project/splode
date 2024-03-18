defmodule Splode.ErrorClass do
  @moduledoc "Tools for working with error classes"

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts =
        Keyword.update(opts, :fields, [errors: []], fn fields ->
          has_error_fields? =
            Enum.any?(fields, fn
              :errors ->
                true

              {:errors, _} ->
                true

              _ ->
                false
            end)

          if has_error_fields? do
            fields
          else
            fields ++ [errors: []]
          end
        end)
        |> Keyword.put(:error_class?, true)

      use Splode.Error, opts

      def message(%{errors: errors}) do
        Splode.ErrorClass.error_messages(errors)
      end
    end
  end

  @doc "Creates a long form composite error message for a list of errors"
  def error_messages(errors, opts \\ []) do
    custom_message = opts[:custom_message]

    generic_message =
      errors
      |> List.wrap()
      |> Enum.group_by(& &1.class)
      |> Enum.map_join("\n\n", fn {class, class_errors} ->
        header = String.capitalize(to_string(class)) <> " Error\n\n"

        header <>
          Enum.map_join(class_errors, "\n", fn
            error when is_binary(error) ->
              "* #{error}"

            %{stacktrace: %Splode.Stacktrace{stacktrace: stacktrace}} = class_error ->
              bread_crumb(class_error.bread_crumbs) <>
                "* #{Exception.message(class_error)}\n" <>
                path(class_error) <>
                Enum.map_join(stacktrace, "\n", fn stack_item ->
                  "  " <> Exception.format_stacktrace_entry(stack_item)
                end)

            %{bread_crumbs: bread_crumbs} = class_error when is_list(bread_crumbs) ->
              if is_exception(class_error) do
                bread_crumb(class_error.bread_crumbs) <>
                  "* #{Exception.message(class_error)}\n" <>
                  path(class_error)
              else
              end

            other ->
              Exception.format(:error, other)
          end)
      end)

    if custom_message do
      custom =
        custom_message
        |> List.wrap()
        |> Enum.map_join("\n", &"* #{&1}")

      "\n\n" <> custom <> generic_message
    else
      generic_message
    end
  end

  defp path(%{path: path}) when path not in [[], nil] do
    "    at " <> to_path(path) <> "\n"
  end

  defp path(_), do: ""

  defp to_path(path) do
    Enum.map_join(path, ", ", fn item ->
      if is_list(item) do
        "[#{to_path(item)}]"
      else
        if is_binary(item) || is_atom(item) || is_number(item) do
          item
        else
          inspect(item)
        end
      end
    end)
  end

  @doc false
  def bread_crumb(nil), do: ""
  def bread_crumb([]), do: ""

  def bread_crumb(bread_crumbs) do
    case Enum.filter(bread_crumbs, & &1) do
      [] ->
        ""

      bread_crumbs ->
        "Bread Crumbs: " <> Enum.join(bread_crumbs, " > ") <> "\n"
    end
  end
end
