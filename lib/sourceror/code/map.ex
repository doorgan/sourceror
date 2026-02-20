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

defmodule Sourceror.Code.Map do
  @moduledoc """
  Utilities for working with maps.
  """

  require Sourceror.Code.Common
  alias Sourceror.Code.Common
  alias Sourceror.Zipper

  @doc """
  Puts a value at a path into a map, calling `updater` on the zipper at the value if the key is already present.

  ## Examples

      iex> zipper = Sourceror.parse_string!("%{foo: 1}") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.Map.put_in_map(zipper, [:bar], 2)
      iex> Sourceror.to_string(zipper.node) |> String.contains?("bar:")
      true

  See also `set_map_key/4`.
  """
  @spec put_in_map(
          Zipper.t(),
          list(term()),
          term(),
          (Zipper.t() -> {:ok, Zipper.t()} | :error) | nil
        ) ::
          {:ok, Zipper.t()} | :error
  def put_in_map(zipper, path, value, updater \\ nil) do
    updater = updater || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    do_put_in_map(zipper, path, value, updater)
  end

  defp do_put_in_map(zipper, [key], value, updater) do
    set_map_key(zipper, key, value, updater)
  end

  defp do_put_in_map(zipper, [key | rest], value, updater) do
    cond do
      Common.node_matches_pattern?(zipper, {:%{}, _, []}) ->
        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key | rest], value)
         )}

      Common.node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> Sourceror.Code.List.move_to_list_item(fn item ->
          if Sourceror.Code.Tuple.tuple?(item) do
            case Sourceror.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.nodes_equal?(first_elem, key)

              :error ->
                false
            end
          end
        end)
        |> case do
          :error ->
            format = map_keys_format(zipper)
            value = mappify(rest, value)

            {:ok,
             Zipper.append_child(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> Sourceror.Code.Tuple.tuple_elem(1)
            |> case do
              {:ok, zipper} ->
                do_put_in_map(zipper, rest, value, updater)

              :error ->
                :error
            end
        end

      true ->
        :error
    end
  end

  @doc """
  Puts a key into a map, calling `updater` on the zipper at the value if the key is already present.

  ## Examples

      iex> zipper = Sourceror.parse_string!("%{foo: 1}") |> Sourceror.Zipper.zip()
      iex> {:ok, zipper} = Sourceror.Code.Map.set_map_key(zipper, :bar, 2, fn z -> {:ok, z} end)
      iex> Sourceror.to_string(zipper.node) |> String.contains?("bar:")
      true

  See also `put_in_map/4`.
  """
  @spec set_map_key(Zipper.t(), term(), term(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          {:ok, Zipper.t()} | :error
  def set_map_key(zipper, key, value, updater) do
    cond do
      Common.node_matches_pattern?(zipper, {:%{}, _, []}) ->
        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key], value)
         )}

      Common.node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> Common.move_right(fn item ->
          if Sourceror.Code.Tuple.tuple?(item) do
            case Sourceror.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.nodes_equal?(first_elem, key)

              :error ->
                false
            end
          end
        end)
        |> case do
          :error ->
            format = map_keys_format(zipper)

            {:ok,
             Zipper.append_child(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> Sourceror.Code.Tuple.tuple_elem(1)
            |> case do
              {:ok, zipper} ->
                updater.(zipper)

              :error ->
                :error
            end
        end

      true ->
        :error
    end
  end

  defp map_keys_format(zipper) do
    case zipper.node do
      value when is_list(value) ->
        Enum.all?(value, fn
          {:__block__, meta, _} ->
            meta[:format] == :keyword

          _ ->
            false
        end)
        |> case do
          true ->
            :keyword

          false ->
            :map
        end

      _ ->
        :map
    end
  end

  @doc """
  Puts a value into nested maps at the given path.

  ## Examples

      iex> Sourceror.Code.Map.mappify([:foo, :bar], 1)
      {:%{}, [], [{{:__block__, [format: :keyword], [:foo]}, {:%{}, [], [{{:__block__, [format: :keyword], [:bar]}, 1}}]}}]}
  """
  def mappify([], value) do
    value
  end

  def mappify([key | rest], value) do
    format =
      if is_atom(key) do
        :keyword
      else
        :map
      end

    {:%{}, [], [{{:__block__, [format: format], [key]}, mappify(rest, value)}]}
  end
end
