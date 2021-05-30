defmodule Sourceror.Utils.TypedStruct do
  @moduledoc false

  defmacro typedstruct(do: ast) do
    fields_ast =
      case ast do
        {:__block__, _, fields} -> fields
        field -> [field]
      end

    fields_data = Enum.map(fields_ast, &get_field_data/1)

    enforced_fields =
      for field <- fields_data, field.enforced? do
        field.name
      end

    typespecs =
      Enum.map(fields_data, fn
        %{name: name, typespec: typespec, enforced?: true} ->
          {name, typespec}

        %{name: name, typespec: typespec} ->
          {
            name,
            {:|, [], [typespec, nil]}
          }
      end)

    fields =
      for %{name: name, default: default} <- fields_data do
        {name, default}
      end

    quote location: :keep do
      @type t :: %__MODULE__{unquote_splicing(typespecs)}
      @enforce_keys unquote(enforced_fields)
      defstruct unquote(fields)
    end
  end

  defp get_field_data({:field, _, [name, typespec]}) do
    get_field_data({:field, [], [name, typespec, []]})
  end

  defp get_field_data({:field, _, [name, typespec, opts]}) do
    default = Keyword.get(opts, :default)
    enforced? = Keyword.get(opts, :enforced?, false)

    %{
      name: name,
      typespec: typespec,
      default: default,
      enforced?: enforced?
    }
  end
end
