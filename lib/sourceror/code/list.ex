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

defmodule Sourceror.Code.List do
  @moduledoc """
  Utilities for working with lists.
  """

  require Sourceror.Code.Common
  alias Sourceror.Code.Common
  alias Sourceror.Zipper

  @type equality_pred :: (Zipper.t(), Macro.t() -> boolean)

  @doc """
  Returns true if the `zipper` is at a list literal.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.List.list?(zipper)
      true
      iex> zipper = Sourceror.parse_string!("{1, 2, 3}") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.List.list?(zipper)
      false
  """
  @spec list?(Zipper.t()) :: boolean()
  def list?(zipper) do
    Common.node_matches_pattern?(zipper, value when is_list(value))
  end

  @doc """
  Prepends `quoted` to the list unless it is already present, determined by `equality_pred`.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.prepend_new_to_list(zipper, 0)
      iex> Sourceror.to_string(zipper.node)
      "[0, 1, 2, 3]"

  See also `append_new_to_list/3`.
  """
  @spec prepend_new_to_list(Zipper.t(), quoted :: Macro.t(), equality_pred) ::
          {:ok, Zipper.t()} | :error
  def prepend_new_to_list(zipper, quoted, equality_pred \\ &Common.nodes_equal?/2) do
    Common.within(zipper, fn zipper ->
      if list?(zipper) do
        zipper
        |> find_list_item_index(fn value ->
          equality_pred.(value, quoted)
        end)
        |> case do
          nil ->
            prepend_to_list(zipper, quoted)

          _ ->
            {:ok, zipper}
        end
      else
        :error
      end
    end)
  end

  @doc """
  Appends `quoted` to the list unless it is already present, determined by `equality_pred`.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.append_new_to_list(zipper, 4)
      iex> Sourceror.to_string(zipper.node)
      "[1, 2, 3, 4]"

  See also `prepend_new_to_list/3`.
  """
  @spec append_new_to_list(Zipper.t(), quoted :: Macro.t(), equality_pred) ::
          {:ok, Zipper.t()} | :error
  def append_new_to_list(zipper, quoted, equality_pred \\ &Common.nodes_equal?/2) do
    if list?(zipper) do
      zipper
      |> find_list_item_index(fn value ->
        equality_pred.(value, quoted)
      end)
      |> case do
        nil ->
          append_to_list(zipper, quoted)

        _ ->
          {:ok, zipper}
      end
    else
      :error
    end
  end

  @doc """
  Prepends `quoted` to the list.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.prepend_to_list(zipper, 0)
      iex> Sourceror.to_string(zipper.node)
      "[0, 1, 2, 3]"

  See also `append_to_list/2`.
  """
  @spec prepend_to_list(Zipper.t(), quoted :: Macro.t()) :: {:ok, Zipper.t()} | :error
  def prepend_to_list(zipper, quoted) do
    if list?(zipper) do
      {:ok,
       zipper
       |> Common.maybe_move_to_single_child_block()
       |> Zipper.insert_child(quoted)}
    else
      :error
    end
  end

  @doc """
  Appends `quoted` to the list.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.append_to_list(zipper, 4)
      iex> Sourceror.to_string(zipper.node)
      "[1, 2, 3, 4]"

  See also `prepend_to_list/2`.
  """
  @spec append_to_list(Zipper.t(), quoted :: Macro.t()) :: {:ok, Zipper.t()} | :error
  def append_to_list(zipper, quoted) do
    if list?(zipper) do
      {:ok,
       zipper
       |> Common.maybe_move_to_single_child_block()
       |> Zipper.append_child(quoted)}
    else
      :error
    end
  end

  @spec remove_from_list(Zipper.t(), predicate :: (Zipper.t() -> boolean())) ::
          {:ok, Zipper.t()} | :error
  def remove_from_list(zipper, predicate) do
    zipper = Sourceror.Code.Common.maybe_move_to_single_child_block(zipper)

    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        case Zipper.down(zipper) do
          nil ->
            {:ok, zipper}

          zipper ->
            with {:ok, zipper} <- Common.move_right(zipper, predicate) do
              {:ok, Zipper.remove(zipper)}
            end
        end
      end)
      |> case do
        :error -> {:ok, zipper}
        {:ok, ^zipper} -> {:ok, zipper}
        {:ok, zipper} -> remove_from_list(zipper, predicate)
      end
    else
      :error
    end
  end

  @spec replace_in_list(Zipper.t(), predicate :: (Zipper.t() -> boolean()), term :: any()) ::
          {:ok, Zipper.t()} | :error
  def replace_in_list(zipper, predicate, value) do
    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        with zipper when not is_nil(zipper) <- Zipper.down(zipper),
             {:ok, zipper} <- Common.move_right(zipper, predicate) do
          {:ok, Sourceror.Code.Common.replace_code(zipper, value)}
        else
          nil -> :error
          :error -> :error
        end
      end)
      |> case do
        :error -> {:ok, zipper}
        {:ok, zipper} -> replace_in_list(zipper, predicate, value)
      end
    else
      :error
    end
  end

  @doc """
  Removes the item at the given index, returning `:error` if nothing is at that index.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.remove_index(zipper, 1)
      iex> Sourceror.to_string(zipper.node)
      "[1, 3]"
  """
  @spec remove_index(Zipper.t(), index :: non_neg_integer()) :: {:ok, Zipper.t()} | :error
  def remove_index(zipper, index) do
    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        with zipper when not is_nil(zipper) <-
               zipper |> Sourceror.Code.Common.maybe_move_to_single_child_block() |> Zipper.down(),
             {:ok, zipper} <- Common.move_right(zipper, index) do
          {:ok, Zipper.remove(zipper)}
        else
          nil -> :error
          :error -> :error
        end
      end)
    else
      :error
    end
  end

  @doc """
  Finds the index of the first list item that satisfies `pred`.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.List.find_list_item_index(zipper, fn z ->
      ...>   match?({:__block__, _, [2]}, z.node)
      ...> end)
      1

  See also `move_to_list_item/2`.
  """
  @spec find_list_item_index(Zipper.t(), (Zipper.t() -> boolean())) :: integer() | nil
  def find_list_item_index(zipper, pred) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        nil

      zipper ->
        find_index_right(zipper, pred, 0)
    end
  end

  @doc """
  Moves to the list item matching the given predicate.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.List.move_to_list_item(zipper, fn z ->
      ...>   match?({:__block__, _, [2]}, z.node)
      ...> end)
      iex> match?({:__block__, _, [2]}, result.node)
      true

  See also `find_list_item_index/2`.
  """
  @spec move_to_list_item(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_to_list_item(zipper, pred) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        do_move_to_list_item(zipper, pred)
    end
  end

  @doc """
  Maps over each item in the list, applying the given function.

  ## Examples

      iex> zipper = Sourceror.parse_string!("[1, 2, 3]") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.List.map(zipper, fn z ->
      ...>   {:ok, Sourceror.Code.Common.replace_code(z, "0")}
      ...> end)
      iex> Sourceror.to_string(zipper.node)
      "[0, 0, 0]"

  See also `move_to_list_item/2`.
  """
  @spec map(Zipper.t(), (Zipper.t() -> {:ok, Zipper.t()})) :: {:ok, Zipper.t()} | :error
  def map(zipper, fun) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        do_map(zipper, fun)
    end
  end

  defp do_map(zipper, fun) do
    case Sourceror.Code.Common.within(zipper, fun) do
      {:ok, zipper} ->
        case Zipper.right(zipper) do
          nil ->
            {:ok, zipper}

          right ->
            do_map(right, fun)
        end

      :error ->
        :error
    end
  end

  @doc "Moves to the list item matching the given predicate, assuming you are currently inside the list"
  def do_move_to_list_item(zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      zipper
      |> Zipper.right()
      |> case do
        nil ->
          :error

        right ->
          do_move_to_list_item(right, pred)
      end
    end
  end

  defp find_index_right(zipper, pred, index) do
    if pred.(Common.maybe_move_to_single_child_block(zipper)) do
      index
    else
      case Zipper.right(zipper) do
        nil ->
          nil

        zipper ->
          zipper
          |> find_index_right(pred, index + 1)
      end
    end
  end
end
