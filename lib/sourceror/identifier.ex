defmodule Sourceror.Identifier do
  @moduledoc """
  Functions to identify an classify forms and quoted expressions.
  """

  # this is used below to handle operators that were added in later
  # versions of Elixir
  concat_if = fn ops, version, new_ops ->
    if Version.match?(System.version(), version) do
      ops ++ new_ops
    else
      ops
    end
  end

  @unary_ops [:&, :!, :^, :not, :+, :-, :"~~~", :@]

  @binary_ops [
                :<-,
                :\\,
                :when,
                :"::",
                :|,
                :=,
                :||,
                :|||,
                :or,
                :&&,
                :&&&,
                :and,
                :==,
                :!=,
                :=~,
                :===,
                :!==,
                :<,
                :<=,
                :>=,
                :>,
                :|>,
                :<<<,
                :>>>,
                :<~,
                :~>,
                :<<~,
                :~>>,
                :<~>,
                :"<|>",
                :in,
                :"^^^",
                :"//",
                :++,
                :--,
                :..,
                :<>,
                :+,
                :-,
                :*,
                :/,
                :.
              ]
              |> concat_if.("~> 1.12", ~w[+++ ---]a)
              |> concat_if.("~> 1.13", ~w[**]a)

  @pipeline_operators [:|>, :~>>, :<<~, :~>, :<~, :<~>, :"<|>"]

  @non_call_forms [:__block__, :__aliases__]

  defguardp __is_atomic_literal__(quoted)
            when is_number(quoted) or is_atom(quoted) or is_binary(quoted)

  # {:__block__, [], [atomic_literal]}
  defguardp __is_atomic_literal_block__(quoted)
            when is_tuple(quoted) and
                   tuple_size(quoted) == 3 and
                   elem(quoted, 0) == :__block__ and
                   tl(elem(quoted, 2)) == [] and
                   __is_atomic_literal__(hd(elem(quoted, 2)))

  @doc """
  Checks if the given identifier is an unary op.

  ## Examples

      iex> is_unary_op(:+)
      true
  """
  @spec is_unary_op(Macro.t()) :: Macro.t()
  defguard is_unary_op(op) when is_atom(op) and op in @unary_ops

  @doc """
  Checks if the given identifier is a binary op.

  ## Examples

      iex> is_binary_op(:+)
      true
  """
  @spec is_binary_op(Macro.t()) :: Macro.t()
  defguard is_binary_op(op) when is_atom(op) and op in @binary_ops

  @doc """
  Checks if the given identifier is a pipeline operator.

  ## Examples

      iex> is_pipeline_op(:|>)
      true
  """
  @spec is_pipeline_op(Macro.t()) :: Macro.t()
  defguard is_pipeline_op(op) when is_atom(op) and op in @pipeline_operators

  @doc """
  Checks if the given quoted form is a call.

  Calls are any form of the shape `{form, metadata, args}` where args is
  a list, with the exception of blocks and aliases, which are identified
  by the forms `:__block__` and `:__aliases__`.

  ## Examples

      iex> "node()" |> Sourceror.parse_string!() |> is_call()
      true

      iex> "Kernel.node()" |> Sourceror.parse_string!() |> is_call()
      true

      iex> "%{}" |> Sourceror.parse_string!() |> is_call()
      true

      iex> "@attr" |> Sourceror.parse_string!() |> is_call()
      true

      iex> "node" |> Sourceror.parse_string!() |> is_call()
      false

      iex> "1" |> Sourceror.parse_string!() |> is_call()
      false

      iex> "(1; 2)" |> Sourceror.parse_string!() |> is_call()
      false

      iex> "Macro.Env" |> Sourceror.parse_string!() |> is_call()
      false
  """
  @spec is_call(Macro.t()) :: Macro.t()
  defguard is_call(quoted)
           when is_tuple(quoted) and
                  tuple_size(quoted) == 3 and
                  is_list(elem(quoted, 2)) and
                  elem(quoted, 0) not in @non_call_forms

  @doc """
  Checks if the given quoted form is an unqualified call.

  All unqualified calls would also return `true` if passed to `is_call/1`,
  but they have the shape `{atom, metadata, args}`.

  ## Examples

      iex> "node()" |> Sourceror.parse_string!() |> is_unqualified_call()
      true

      iex> "%{}" |> Sourceror.parse_string!() |> is_unqualified_call()
      true

      iex> "@attr" |> Sourceror.parse_string!() |> is_unqualified_call()
      true

      iex> "node" |> Sourceror.parse_string!() |> is_unqualified_call()
      false

      iex> "1" |> Sourceror.parse_string!() |> is_unqualified_call()
      false

      iex> "(1; 2)" |> Sourceror.parse_string!() |> is_unqualified_call()
      false

      iex> "Macro.Env" |> Sourceror.parse_string!() |> is_unqualified_call()
      false
  """
  @spec is_unqualified_call(Macro.t()) :: Macro.t()
  defguard is_unqualified_call(quoted)
           when is_call(quoted) and is_atom(elem(quoted, 0))

  @doc """
  Checks if the given quoted form is a qualified call.

  All unqualified calls would also return `true` if passed to `is_call/1`,
  but they have the shape `{{:., dot_metadata, dot_args}, metadata, args}`.

  ## Examples

      iex> "Kernel.node()" |> Sourceror.parse_string!() |> is_qualified_call()
      true

      iex> "__MODULE__.node()" |> Sourceror.parse_string!() |> is_qualified_call()
      true

      iex> "foo.()" |> Sourceror.parse_string!() |> is_qualified_call()
      true

      iex> "foo.bar()" |> Sourceror.parse_string!() |> is_qualified_call()
      true

      iex> "node()" |> Sourceror.parse_string!() |> is_qualified_call()
      false

      iex> "%{}" |> Sourceror.parse_string!() |> is_qualified_call()
      false

      iex> "@attr" |> Sourceror.parse_string!() |> is_qualified_call()
      false

      iex> "1" |> Sourceror.parse_string!() |> is_qualified_call()
      false

      iex> "(1; 2)" |> Sourceror.parse_string!() |> is_qualified_call()
      false

      iex> "Macro.Env" |> Sourceror.parse_string!() |> is_qualified_call()
      false
  """
  @spec is_qualified_call(Macro.t()) :: Macro.t()
  defguard is_qualified_call(quoted)
           when is_call(quoted) and
                  is_call(elem(quoted, 0)) and
                  elem(elem(quoted, 0), 0) == :.

  @doc """
  Checks if the given quoted form is an identifier, such as a variable.

  ## Examples

      iex> "node" |> Sourceror.parse_string!() |> is_identifier()
      true

      iex> "node()" |> Sourceror.parse_string!() |> is_identifier()
      false

      iex> "1" |> Sourceror.parse_string!() |> is_identifier()
      false
  """
  @spec is_identifier(Macro.t()) :: Macro.t()
  defguard is_identifier(quoted)
           when is_tuple(quoted) and
                  tuple_size(quoted) == 3 and
                  is_atom(elem(quoted, 0)) and
                  is_atom(elem(quoted, 2))

  @doc """
  Checks if the given quoted form is an atomic literal in the AST.

  This set includes numbers, atoms, and strings, but not collections like
  tuples, lists, or maps.

  This guard returns `true` for literals that are the only elements inside
  of a `:__block__`, such as `{:__block__, [], [:literal]}`.

  ## Examples

      iex> is_atomic_literal(1)
      true

      iex> is_atomic_literal(1.0)
      true

      iex> is_atomic_literal(:foo)
      true

      iex> is_atomic_literal("foo")
      true

      iex> is_atomic_literal({:__block__, [], [1]})
      true

      iex> is_atomic_literal({:__block__, [], [1, 2]})
      false

      iex> is_atomic_literal({:__block__, [], [{:node, [], nil}]})
      false

      iex> is_atomic_literal('foo')
      false
  """
  @spec is_atomic_literal(Macro.t()) :: Macro.t()
  defguard is_atomic_literal(quoted)
           when __is_atomic_literal__(quoted) or __is_atomic_literal_block__(quoted)

  @doc """
  Checks if the given atom is a valid module alias.

  ## Examples

      iex> valid_alias?(Foo)
      true
      iex> valid_alias?(:foo)
      false
  """
  def valid_alias?(atom) when is_atom(atom) do
    valid_alias?(to_charlist(atom))
  end

  def valid_alias?(~c"Elixir" ++ rest), do: valid_alias_piece?(rest)
  def valid_alias?(_other), do: false

  defp valid_alias_piece?([?., char | rest]) when char >= ?A and char <= ?Z,
    do: valid_alias_piece?(trim_leading_while_valid_identifier(rest))

  defp valid_alias_piece?([]), do: true
  defp valid_alias_piece?(_other), do: false

  defp trim_leading_while_valid_identifier([char | rest])
       when char >= ?a and char <= ?z
       when char >= ?A and char <= ?Z
       when char >= ?0 and char <= ?9
       when char == ?_ do
    trim_leading_while_valid_identifier(rest)
  end

  defp trim_leading_while_valid_identifier(other) do
    other
  end

  @doc false
  def do_block?({:__block__, _, args}) do
    not is_nil(args[:do])
  end

  def do_block?(_), do: false
end
