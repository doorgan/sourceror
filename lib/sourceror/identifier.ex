defmodule Sourceror.Identifier do
  @moduledoc """
  Functions to identify an classify forms and quoted expressions.
  """

  @unary_ops [:&, :!, :^, :not, :+, :-, :~~~, :@]
  binary_ops = [
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
    :<|>,
    :in,
    :^^^,
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

  @binary_ops (if Version.match?(System.version(), "~> 1.12") do
                 binary_ops ++ Enum.map(~w[+++ ---], &String.to_atom/1)
               else
                 binary_ops
               end)

  @pipeline_operators [:|>, :~>>, :<<~, :~>, :<~, :<~>, :<|>]

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
  defguard is_pipeline_op(op) when is_atom(op) and op in @pipeline_operators

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

  def valid_alias?('Elixir' ++ rest), do: valid_alias_piece?(rest)
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
