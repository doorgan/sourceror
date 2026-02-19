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

defmodule Sourceror.Code.Tuple do
  @moduledoc """
  Utilities for working with tuples.
  """
  alias Sourceror.Code.Common
  alias Sourceror.Zipper

  @doc """
  Returns `true` if the zipper is at a literal tuple, `false` if not.

  ## Examples

      iex> zipper = Sourceror.parse_string!("{1, 2, 3}") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Tuple.tuple?(zipper)
      true
      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Tuple.tuple?(zipper)
      false

  See also `tuple_elem/2`.
  """
  @spec tuple?(Zipper.t()) :: boolean()
  def tuple?(item) do
    item = Sourceror.Code.Common.maybe_move_to_single_child_block(item)

    case item.node do
      {:{}, _, _} -> true
      {_, _} -> true
      _ -> false
    end
  end

  @doc """
  Appends `quoted` to the tuple.

  ## Examples

      iex> zipper = Sourceror.parse_string!("{1, 2}") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.Tuple.append_elem(zipper, 3)
      iex> Sourceror.to_string(zipper.node)
      "{1, 2, 3}"

  See also `tuple_elem/2`.
  """
  @spec append_elem(Zipper.t(), quoted :: Macro.t()) :: {:ok, Zipper.t()} | :error
  def append_elem(zipper, quoted) do
    if tuple?(zipper) do
      zipper = Sourceror.Code.Common.maybe_move_to_single_child_block(zipper)

      case zipper.node do
        {l, r} ->
          {:ok, Zipper.replace(zipper, {:{}, [], [l, r, quoted]})}

        {:{}, _, list} ->
          {:ok, Zipper.replace(zipper, {:{}, [], list ++ [quoted]})}
      end
    else
      :error
    end
  end

  @doc """
  Returns true if the element at the given index equals the given value.

  ## Examples

      iex> zipper = Sourceror.parse_string!("{1, 2, 3}") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Tuple.elem_equals?(zipper, 0, 1)
      true
      iex> Sourceror.Code.Tuple.elem_equals?(zipper, 0, 2)
      false

  See also `tuple_elem/2`.
  """
  @spec elem_equals?(Zipper.t(), elem :: non_neg_integer(), value :: term) :: boolean()
  def elem_equals?(zipper, elem, value) do
    case tuple_elem(zipper, elem) do
      {:ok, zipper} ->
        Sourceror.Code.Common.nodes_equal?(zipper, value)

      _ ->
        false
    end
  end

  @doc """
  Returns a zipper at the tuple element at the given index, or `:error` if the index is out of bounds.

  ## Examples

      iex> zipper = Sourceror.parse_string!("{1, 2, 3}") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Tuple.tuple_elem(zipper, 1)
      iex> match?({:__block__, _, [2]}, result.node)
      true

  See also `tuple?/1`.
  """
  @spec tuple_elem(Zipper.t(), elem :: non_neg_integer()) :: {:ok, Zipper.t()} | :error
  def tuple_elem(item, elem) do
    item
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> Common.move_right(elem)
    |> case do
      {:ok, nth} ->
        {:ok, Common.maybe_move_to_single_child_block(nth)}

      :error ->
        :error
    end
  end
end
