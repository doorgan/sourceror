# Copyright 2024 Zach Daniel. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

# Branched from https://github.com/ash-project/igniter
# Initial implementation Copyright (c) 2024 Zach Daniel, licenced under Apache 2.0

defmodule Sourceror.Code.Function do
  @moduledoc """
  Utilities for working with functions.
  """

  require Sourceror.Code.Common
  alias Sourceror.Code.Common
  alias Sourceror.Zipper

  @doc """
  Returns `true` if the argument at the provided index exists and matches the provided pattern

  Note: to check for argument equality, use `argument_equals?/3` instead.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2, 3)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.argument_matches_pattern?(zipper, 1, {:__block__, _, [2]})
      true

  See also `argument_matches_predicate?/3`.
  """
  defmacro argument_matches_pattern?(zipper, index, pattern) do
    quote do
      Sourceror.Code.Function.argument_matches_predicate?(
        unquote(zipper),
        unquote(index),
        fn zipper ->
          match?(unquote(pattern), zipper.node)
        end
      )
    end
  end

  @spec move_to_defp(Zipper.t(), fun :: atom, arity :: integer | list(integer)) ::
          {:ok, Zipper.t()} | :error
  def move_to_defp(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :defp)
  end

  @spec move_to_def(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def move_to_def(zipper) do
    move_to_function_call(zipper, :def, :any)
  end

  @spec move_to_def(Zipper.t(), fun :: atom, arity :: integer | list(integer)) ::
          {:ok, Zipper.t()} | :error
  def move_to_def(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :def)
  end

  defp do_move_to_def(zipper, fun, [arity], kind) do
    do_move_to_def(zipper, fun, arity, kind)
  end

  defp do_move_to_def(zipper, fun, [arity | rest], kind) do
    case do_move_to_def(zipper, fun, arity, kind) do
      {:ok, zipper} -> {:ok, zipper}
      :error -> do_move_to_def(zipper, fun, rest, kind)
    end
  end

  defp do_move_to_def(zipper, fun, arity, kind) do
    with {:ok, zipper} <-
           Common.move_to_pattern(
             zipper,
             {^kind, _, [{^fun, _, args}, _]} when length(args) == arity
           ),
         {:ok, zipper} <- Common.move_to_do_block(zipper) do
      {:ok, zipper}
    else
      :error when arity == 0 ->
        with {:ok, zipper} <-
               Common.move_to_pattern(
                 zipper,
                 {^kind, _, [{^fun, _, context}, _]} when is_atom(context)
               ),
             {:ok, zipper} <- Common.move_to_do_block(zipper) do
          {:ok, zipper}
        end

      :error ->
        :error
    end
  end

  @doc """
  Moves to a function call by the given name and arity, matching the given predicate, in the current scope.

  ## Examples

      iex> zipper = Sourceror.parse_string!("bar = 1\\nfoo(1, 2)") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Function.move_to_function_call_in_current_scope(zipper, :foo, 2)
      iex> match?({:foo, _, _}, result.node)
      true

  See also `move_to_function_call/4`.
  """
  @spec move_to_function_call_in_current_scope(
          Zipper.t(),
          atom | {atom, atom},
          non_neg_integer() | list(non_neg_integer()) | :any
        ) ::
          {:ok, Zipper.t()} | :error
  def move_to_function_call_in_current_scope(zipper, name, arity, predicate \\ fn _ -> true end)

  def move_to_function_call_in_current_scope(zipper, name, [arity | arities], predicate) do
    case move_to_function_call_in_current_scope(zipper, name, arity, predicate) do
      :error ->
        move_to_function_call_in_current_scope(zipper, name, arities, predicate)

      {:ok, zipper} ->
        {:ok, zipper}
    end
  end

  def move_to_function_call_in_current_scope(_, _, [], _) do
    :error
  end

  def move_to_function_call_in_current_scope(%Zipper{} = zipper, name, arity, predicate) do
    if function_call?(zipper, name, arity) && predicate.(zipper) do
      {:ok, zipper}
    else
      Common.move_right(zipper, fn zipper ->
        function_call?(zipper, name, arity) && predicate.(zipper)
      end)
    end
  end

  @doc """
  Moves to a function call by the given name and arity, matching the given predicate, in the current or lower scope.

  ## Examples

      iex> zipper = Sourceror.parse_string!("bar = foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Function.move_to_function_call(zipper, :foo, 2)
      iex> match?({:foo, _, _}, result.node)
      true

  See also `move_to_function_call_in_current_scope/4`.
  """
  @spec move_to_function_call(
          Zipper.t(),
          atom | {atom, atom},
          :any | non_neg_integer() | list(non_neg_integer())
        ) ::
          {:ok, Zipper.t()} | :error
  def move_to_function_call(zipper, name, arity, predicate \\ fn _ -> true end)

  def move_to_function_call(zipper, name, [arity | arities], predicate) do
    case move_to_function_call(zipper, name, arity, predicate) do
      :error ->
        move_to_function_call(zipper, name, arities, predicate)

      {:ok, zipper} ->
        {:ok, zipper}
    end
  end

  def move_to_function_call(_, _, [], _) do
    :error
  end

  def move_to_function_call(%Zipper{} = zipper, name, arity, predicate) do
    if function_call?(zipper, name, arity) && predicate.(zipper) do
      {:ok, zipper}
    else
      Common.move_next(zipper, fn zipper ->
        function_call?(zipper, name, arity) && predicate.(zipper)
      end)
    end
  end

  @doc """
  Returns `true` if the node is a function call of the given name

  If an `atom` is provided, it only matches functions in the form of `function(name)`.

  If an `{module, atom}` is provided, it matches functions called on the given module,
  taking into account aliases.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.function_call?(zipper, :foo, 2)
      true
      iex> Sourceror.Code.Function.function_call?(zipper, :bar, 2)
      false

  See also `function_call?/1`.
  """
  @spec function_call?(Zipper.t(), atom | {module, atom}, arity :: integer | :any | list(integer)) ::
          boolean()
  def function_call?(zipper, name, arity \\ :any)

  def function_call?(%Zipper{} = zipper, name, arity) when is_atom(name) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {^name, _, args} when arity == :any or length(args) == arity ->
        true

      {{^name, _, context}, _, args}
      when is_atom(context) and (arity == :any or length(args) == arity) ->
        true

      {:|>, _, [_, {{^name, _, context}, _, rest}]}
      when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
        true

      {:|>, _, [_, {^name, _, rest}]}
      when arity == :any or length(rest) == arity - 1 ->
        true

      _ ->
        false
    end
  end

  def function_call?(%Zipper{} = zipper, {module, name}, arity) when is_atom(name) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    function_call_shape? =
      case node do
        {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {{:., _, [^module, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          true

        {{:., _, [^module, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [^module, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [^module, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          true

        {{:., _, [{:__block__, _, [^module]}, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          true

        {{:., _, [{:__block__, _, [^module]}, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [{:__block__, _, [^module]}, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [{:__block__, _, [^module]}, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          true

        _node ->
          false
      end

    if function_call_shape? do
      case Zipper.up(zipper) do
        %{node: {:&, _, _}} ->
          false

        _ ->
          true
      end
    else
      false
    end
  end

  @doc """
  Returns true if the value is a function literal.

  Examples:
    - `fn x -> x end`
    - `&(&1 + &2)`
    - `&SomeMod.fun/2`

  To refine the check, you can use `name` and `arity`.

  ## Names

  - `:any` - matches any function literal, named or not
  - `:any_named` - matches any named function literal
  - `:anonymous` - matches any anonymous function literal
  - `{module, name}` - matches a function literal with the given module and name

  ## Examples

      iex> zipper = Sourceror.parse_string!("fn x -> x end") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.function?(zipper, :anonymous, 1)
      true
      iex> zipper = Sourceror.parse_string!("&(&1 + &2)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.function?(zipper, :anonymous, 2)
      true
  """
  @spec function?(
          Zipper.t(),
          name :: :any | :any_named | {module(), atom()} | :anonymous,
          arity :: :any | non_neg_integer() | [non_neg_integer()]
        ) ::
          boolean
  def function?(zipper, name \\ :any, arity \\ :any)

  def function?(zipper, name, arity) when is_list(arity) do
    Enum.any?(arity, fn arity -> function?(zipper, name, arity) end)
  end

  def function?(%Zipper{}, name, _arity)
      when is_atom(name) and name not in [:any, :any_named, :anonymous] do
    raise ArgumentError,
          "The name argument must be one of `:any`, `:any_named`, `:anonymous` or a `{module, name}` tuple."
  end

  def function?(%Zipper{} = zipper, :anonymous, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{{:., _, [{:__aliases__, _, _}, _]}, _, _}]} ->
        false

      {:&, _, [{:&, _, _}]} ->
        arity == :any or arity == 1

      {:&, _, [{name, _, _}]} when is_atom(name) ->
        false

      {:&, _, [body]} ->
        arity == :any or count_captures(body) == arity

      {:fn, _, [{:->, _, [[{:when, _, args}], _body]} | _]}
      when arity == :any or length(args) == arity ->
        true

      {:fn, _, [{:->, _, [args, _body]} | _]} when arity == :any or length(args) == arity ->
        true

      {:fn, _, _} ->
        true

      _ ->
        false
    end
  end

  def function?(%Zipper{} = zipper, {module, name}, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, _},
            actual_arity
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        Common.nodes_equal?(Zipper.replace(zipper, alias), module)

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, _},
            {:__block__, _, [actual_arity]}
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        Common.nodes_equal?(Zipper.replace(zipper, alias), module)

      {:&, _, [call]} ->
        case call do
          {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
          when arity == :any or length(args) == arity ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
          when is_atom(context) and (arity == :any or length(args) == arity) ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
           ]}
          when arity == :any or length(args) == arity - 1 ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
           ]}
          when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  def function?(%Zipper{} = zipper, :any, arity) do
    function?(zipper, :any_named, arity) or function?(zipper, :anonymous, arity)
  end

  def function(%Zipper{} = zipper, :any_named, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{:/, _, [{name, _, context}, actual_arity]}]}
      when is_atom(name) and is_atom(context) and
             (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [{name, _, context}, {:__block__, _, [actual_arity]}]}]}
      when is_atom(name) and is_atom(context) and
             (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [name, actual_arity]}]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [name, {:__block__, _, [actual_arity]}]}]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _}, name]}, _, _},
            actual_arity
          ]}
       ]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _}, name]}, _, _},
            {:__block__, _, [actual_arity]}
          ]}
       ]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [call]} ->
        case call do
          {{:., _, [{:__aliases__, _, _}, name]}, _, args}
          when is_atom(name) and (arity == :any or length(args) == arity) ->
            true

          {{:., _, [{:__aliases__, _, _}, {name, _, context}]}, _, args}
          when is_atom(name) and is_atom(context) and (arity == :any or length(args) == arity) ->
            true

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _split}, name]}, _, args}
           ]}
          when is_atom(name) or (arity == :any or length(args) == arity - 1) ->
            true

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _}, {name, _, context}]}, _, args}
           ]}
          when is_atom(name) and is_atom(context) and (arity == :any or length(args) == arity - 1) ->
            true

          {name, _, args} when is_atom(name) and (arity == :any or length(args) == arity) ->
            true

          {{name, _, context}, _, args}
          when is_atom(name) and is_atom(context) and
                 (arity == :any or length(args) == arity) ->
            true

          {:|>, _, [_, {name, _, context} | rest]}
          when is_atom(name) and is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
            true

          {:|>, _, [_, name | rest]}
          when is_atom(name) and (arity == :any or length(rest) == arity - 1) ->
            true

          _ ->
            false
        end

      _ ->
        false
    end
  end

  @doc """
  Gets the name of a local function call.

  Returns `:error` if the node is not a function call or cannot be determined.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.get_local_function_call_name(zipper)
      {:ok, :foo}
  """
  @spec get_local_function_call_name(Zipper.t()) :: {:ok, atom()} | :error
  def get_local_function_call_name(%Zipper{} = zipper) do
    case get_local_function_call(zipper) do
      {:ok, {name, _arity}} -> {:ok, name}
      :error -> :error
    end
  end

  @doc """
  Gets the name and arity of a local function call.

  Returns `:error` if the node is not a function call or cannot be determined.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.get_local_function_call(zipper)
      {:ok, {:foo, 2}}

  See also `get_local_function_call_name/1`.
  """
  @spec get_local_function_call(Zipper.t()) :: {:ok, {atom(), non_neg_integer()}} | :error
  def get_local_function_call(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {:__block__, _, _} ->
        :error

      {:|>, _, [_, {{name, _, context}, _, args}]} when is_atom(context) and is_atom(name) ->
        {:ok, {name, length(args) + 1}}

      {:|>, _, [_, {name, _, args}]} when is_atom(name) ->
        {:ok, {name, length(args) + 1}}

      {name, _, args} when is_atom(name) ->
        {:ok, {name, length(args)}}

      {{name, _, context}, _, args} when is_atom(context) and is_atom(name) and is_list(args) ->
        {:ok, {name, length(args)}}

      _ ->
        :error
    end
  end

  @doc """
  Returns `true` if the node is a function call.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.function_call?(zipper)
      true
      iex> zipper = Sourceror.parse_string!("1 + 2") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.function_call?(zipper)
      true
  """
  @spec function_call?(Zipper.t()) :: boolean()
  def function_call?(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {:|>, _,
       [
         _,
         {{:., _, [_, name]}, _, _}
       ]}
      when is_atom(name) ->
        true

      {:|>, _,
       [
         _,
         {{:., _, [_, {name, _, context}]}, _, _args}
       ]}
      when is_atom(name) and is_atom(context) ->
        true

      {:|>, _, [_, {{name, _, context}, _, _}]} when is_atom(context) and is_atom(name) ->
        true

      {:|>, _, [_, {name, _, _}]} when is_atom(name) ->
        true

      {name, _, _} when is_atom(name) ->
        true

      {{name, _, context}, _, _} when is_atom(context) and is_atom(name) ->
        true

      {{:., _, [_, name]}, _, _} when is_atom(name) ->
        true

      {{:., _, [_, {name, _, context}]}, _, _}
      when is_atom(name) and is_atom(context) ->
        true

      _ ->
        false
    end
  end

  @doc """
  Updates the `nth` argument of a function call, leaving the zipper at the function call's node.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2, 3)") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.Function.update_nth_argument(zipper, 1, fn z ->
      ...>   {:ok, Sourceror.Code.Common.replace_code(z, "99")}
      ...> end)
      iex> Sourceror.to_string(zipper.node) |> String.contains?("99")
      true

  See also `move_to_nth_argument/2`.
  """
  @spec update_nth_argument(
          Zipper.t(),
          non_neg_integer(),
          (Zipper.t() ->
             {:ok, Zipper.t()} | :error)
        ) ::
          {:ok, Zipper.t()} | :error
  def update_nth_argument(zipper, index, func) do
    Common.within(zipper, fn zipper ->
      cond do
        pipeline?(zipper) and index == 0 ->
          case Zipper.down(zipper) do
            nil -> :error
            zipper -> func.(zipper)
          end

        pipeline?(zipper) ->
          with zipper when not is_nil(zipper) <- Zipper.down(zipper),
               zipper when not is_nil(zipper) <- Zipper.rightmost(zipper) |> Zipper.down(),
               {:ok, nth} <- Common.move_right(zipper, index) do
            func.(nth)
          else
            nil -> :error
            :error -> :error
          end

        true ->
          with zipper when not is_nil(zipper) <- Zipper.down(zipper),
               {:ok, nth} <- Common.move_right(zipper, index) do
            func.(nth)
          else
            nil -> :error
            :error -> :error
          end
      end
    end)
  end

  @doc """
  Moves to the `nth` argument of a function call.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2, 3)") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Function.move_to_nth_argument(zipper, 1)
      iex> match?({:__block__, _, [2]}, result.node)
      true

  See also `update_nth_argument/3`.
  """
  @spec move_to_nth_argument(
          Zipper.t(),
          non_neg_integer()
        ) ::
          {:ok, Zipper.t()} | :error
  def move_to_nth_argument(zipper, index) do
    cond do
      not function_call?(zipper) ->
        :error

      pipeline?(zipper) and index == 0 ->
        case Zipper.down(zipper) do
          nil -> :error
          zipper -> {:ok, zipper}
        end

      pipeline?(zipper) ->
        with zipper when not is_nil(zipper) <- Zipper.down(zipper),
             zipper when not is_nil(zipper) <- Zipper.rightmost(zipper) |> Zipper.down(),
             {:ok, nth} <- Common.move_right(zipper, index) do
          {:ok, nth}
        else
          nil -> :error
          :error -> :error
        end

      true ->
        offset =
          case zipper.node do
            {{:., _, _}, _, _} -> 1
            _ -> 0
          end

        with zipper when not is_nil(zipper) <- Zipper.down(zipper),
             {:ok, nth} <- Common.move_right(zipper, index + offset) do
          {:ok, nth}
        else
          nil -> :error
          :error -> :error
        end
    end
  end

  @doc """
  Appends an argument to a function call, leaving the zipper at the function call's node.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2)") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.Function.append_argument(zipper, 3)
      iex> Sourceror.to_string(zipper.node)
      "foo(1, 2, 3)"
  """
  @spec append_argument(Zipper.t(), any()) :: {:ok, Zipper.t()} | :error
  def append_argument(zipper, value) do
    if function_call?(zipper) do
      if pipeline?(zipper) do
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            {:ok, Zipper.append_child(zipper, value)}
        end
      else
        {:ok, Zipper.append_child(zipper, value)}
      end
    else
      :error
    end
  end

  @doc """
  Checks if the provided function call (in a Zipper) has an argument that equals
  `term` at `index`.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2, 3)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.argument_equals?(zipper, 0, 1)
      true
      iex> Sourceror.Code.Function.argument_equals?(zipper, 0, 2)
      false

  See also `argument_matches_predicate?/3`.
  """
  @spec argument_equals?(Zipper.t(), integer(), any()) :: boolean()
  def argument_equals?(zipper, index, term) do
    if function_call?(zipper) do
      Sourceror.Code.Function.argument_matches_predicate?(
        zipper,
        index,
        &Sourceror.Code.Common.nodes_equal?(&1, term)
      )
    else
      false
    end
  end

  @doc """
  Returns true if the argument at the given index matches the provided predicate.

  ## Examples

      iex> zipper = Sourceror.parse_string!("foo(1, 2, 3)") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Function.argument_matches_predicate?(zipper, 0, fn z ->
      ...>   match?({:__block__, _, [1]}, z.node)
      ...> end)
      true

  See also `argument_equals?/3`.
  """
  @spec argument_matches_predicate?(Zipper.t(), non_neg_integer(), (Zipper.t() -> boolean)) ::
          boolean()
  def argument_matches_predicate?(zipper, index, func) do
    cond do
      not function_call?(zipper) ->
        false

      pipeline?(zipper) and index == 0 ->
        case Zipper.down(zipper) do
          nil -> nil
          zipper -> func.(zipper)
        end

      pipeline?(zipper) ->
        zipper
        |> Zipper.down()
        |> Zipper.right()
        |> argument_matches_predicate?(index - 1, func)

      true ->
        offset =
          case Zipper.node(zipper) do
            {{:., _, [_mod, name]}, _, args} when is_atom(name) and is_list(args) -> 1
            _ -> 0
          end

        with zipper when not is_nil(zipper) <- Zipper.down(zipper),
             {:ok, zipper} <- Common.move_right(zipper, index + offset) do
          zipper
          |> Common.maybe_move_to_single_child_block()
          |> func.()
        else
          nil -> false
          :error -> false
        end
    end
  end

  defp pipeline?(zipper) do
    case zipper.node do
      {:|>, _, _} -> true
      _ -> false
    end
  end

  # Counts up all the arguments and generates new unique arguments for them.
  # Works around the caveat that each usage of a unique `&n` variable must only
  # be counted once.
  defp count_captures(args) do
    Macro.prewalk(args, [], fn
      {:&, _, [v]} = ast, acc when is_integer(v) ->
        {ast, [v | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
    |> Enum.count()
  end
end
