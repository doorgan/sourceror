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

defmodule Sourceror.Code.String do
  @moduledoc """
  Utilities for working with strings.
  """

  alias Sourceror.Zipper

  @doc """
  Returns true if the node represents a literal string, false otherwise.

  ## Examples

      iex> zipper = Sourceror.parse_string!("\\"hello\\"") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.String.string?(zipper)
      true
      iex> zipper = Sourceror.parse_string!("123") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.String.string?(zipper)
      false

  See also `update_string/2`.
  """
  @spec string?(Zipper.t()) :: boolean()
  def string?(zipper) do
    case zipper.node do
      v when is_binary(v) ->
        true

      {:__block__, meta, [v]} when is_binary(v) ->
        is_binary(meta[:delimiter])

      _ ->
        false
    end
  end

  @doc """
  Updates a node representing a string with the result of the given function.

  ## Examples

      iex> zipper = Sourceror.parse_string!("\\"hello\\"") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.String.update_string(zipper, fn str -> {:ok, str <> " world"} end)
      iex> Sourceror.to_string(zipper.node)
      "\\"hello world\\""

  See also `string?/1`.
  """
  @spec update_string(Zipper.t(), (String.t() -> {:ok, String.t()} | :error)) ::
          {:ok, Zipper.t()} | :error
  def update_string(zipper, func) do
    case zipper.node do
      v when is_binary(v) ->
        with {:ok, new_str} <- func.(v) do
          {:ok, Zipper.replace(zipper, new_str)}
        end

      {:__block__, meta, [v]} when is_binary(v) ->
        if is_binary(meta[:delimiter]) do
          with {:ok, new_str} <- func.(v) do
            {:ok, Zipper.replace(zipper, {:__block__, meta, [new_str]})}
          end
        else
          :error
        end

      _ ->
        :error
    end
  end
end
