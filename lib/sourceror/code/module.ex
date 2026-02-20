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

defmodule Sourceror.Code.Module do
  @moduledoc "Utilities for working with Elixir modules"
  require Sourceror.Code.Common
  alias Sourceror.Code.Common
  alias Sourceror.Zipper

  @doc """
  Moves the zipper to a defmodule call.

  ## Examples

      iex> zipper = Sourceror.parse_string!("defmodule Foo do\\nend") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Module.move_to_defmodule(zipper)
      iex> match?({:defmodule, _, _}, result.node)
      true

  See also `move_to_defmodule/2`.
  """
  @spec move_to_defmodule(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def move_to_defmodule(zipper) do
    Sourceror.Code.Function.move_to_function_call_in_current_scope(zipper, :defmodule, 2)
  end

  @doc """
  Moves the zipper to a specific defmodule call.

  ## Examples

      iex> zipper = Sourceror.parse_string!("defmodule Foo do\\nend") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Module.move_to_defmodule(zipper, Foo)
      iex> match?({:defmodule, _, _}, result.node)
      true

  See also `move_to_defmodule/1`.
  """
  @spec move_to_defmodule(Zipper.t(), module()) :: {:ok, Zipper.t()} | :error
  def move_to_defmodule(zipper, module) do
    Sourceror.Code.Function.move_to_function_call(
      zipper,
      :defmodule,
      2,
      fn zipper ->
        case Sourceror.Code.Function.move_to_nth_argument(zipper, 0) do
          {:ok, zipper} ->
            Sourceror.Code.Common.nodes_equal?(zipper, module)

          _ ->
            false
        end
      end
    )
  end

  @doc """
  Moves the zipper to the body of a module that `use`s the provided module (or one of the provided modules).

  ## Examples

      iex> zipper = Sourceror.parse_string!("defmodule Foo do\\n  use Bar\\nend") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Module.move_to_module_using(zipper, Bar)
      iex> match?({:defmodule, _, _}, result.node)
      true

  See also `move_to_use/2`.
  """
  @spec move_to_module_using(Zipper.t(), module | list(module)) :: {:ok, Zipper.t()} | :error
  def move_to_module_using(zipper, [module]) do
    move_to_module_using(zipper, module)
  end

  def move_to_module_using(zipper, [module | rest] = one_of_modules)
      when is_list(one_of_modules) do
    case move_to_module_using(zipper, module) do
      {:ok, zipper} ->
        {:ok, zipper}

      :error ->
        move_to_module_using(zipper, rest)
    end
  end

  def move_to_module_using(zipper, module) do
    with {:ok, mod_zipper} <- move_to_defmodule(zipper),
         {:ok, mod_zipper} <- Sourceror.Code.Common.move_to_do_block(mod_zipper),
         {:ok, _} <- move_to_use(mod_zipper, module) do
      {:ok, mod_zipper}
    else
      _ ->
        :error
    end
  end

  @doc """
  Moves the zipper to the `use` statement for a provided module.

  ## Examples

      iex> zipper = Sourceror.parse_string!("defmodule Foo do\\n  use Bar\\nend") |> Sourceror.Zipper.zip()
      iex> {:ok, mod} = Sourceror.Code.Module.move_to_defmodule(zipper)
      iex> {:ok, body} = Sourceror.Code.Common.move_to_do_block(mod)
      iex> {:ok, result} = Sourceror.Code.Module.move_to_use(body, Bar)
      iex> match?({:use, _, _}, result.node)
      true

  See also `move_to_module_using/2`.
  """
  def move_to_use(zipper, [module]), do: move_to_use(zipper, module)

  def move_to_use(zipper, [module | rest]) do
    case move_to_use(zipper, module) do
      {:ok, zipper} -> {:ok, zipper}
      _ -> move_to_use(zipper, rest)
    end
  end

  def move_to_use(zipper, module) do
    Sourceror.Code.Function.move_to_function_call_in_current_scope(
      zipper,
      :use,
      [1, 2],
      fn call ->
        Sourceror.Code.Function.argument_matches_predicate?(
          call,
          0,
          &Sourceror.Code.Common.nodes_equal?(&1, module)
        )
      end
    )
  end

  @doc """
  Move to an attribute definition inside a module.

  ## Example

  Given this module:

      defmodule MyAppWeb.Endpoint do
        @doc "My App Endpoint"

        @session_options [
          store: :cookie,
          ...
        ]
      end

  You can move into `@doc` attribute with:

      Sourceror.Code.Module.move_to_attribute_definition(zipper, :doc)

  Or you can move into `@session_options` constant with:

      Sourceror.Code.Module.move_to_attribute_definition(zipper, :session_options)

  ## Examples

      iex> zipper = Sourceror.parse_string!("defmodule Foo do\\n  @doc \\"Hello\\"\\nend") |> Sourceror.Zipper.zip()
      iex> {:ok, result} = Sourceror.Code.Module.move_to_attribute_definition(zipper, :doc)
      iex> match?({:@, _, [{:doc, _, _}]}, result.node)
      true
  """
  @spec move_to_attribute_definition(Zipper.t(), atom()) :: {:ok, Zipper.t()} | :error
  def move_to_attribute_definition(zipper, name) when is_atom(name) do
    with {:ok, zipper} <- Sourceror.Code.Module.move_to_defmodule(zipper),
         {:ok, zipper} <- Common.move_to_do_block(zipper),
         {:ok, zipper} <- Common.move_to_pattern(zipper, {:@, _, [{^name, _, _}]}) do
      {:ok, zipper}
    else
      _ ->
        :error
    end
  end

  @doc """
  Returns true if the zipper is at a module alias.

  ## Examples

      iex> zipper = Sourceror.parse_string!("Foo.Bar") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Module.module?(zipper)
      true
      iex> zipper = Sourceror.parse_string!("123") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Module.module?(zipper)
      false
  """
  def module?(zipper) do
    Common.node_matches_pattern?(zipper, {:__aliases__, _, [_ | _]})
  end

  @doc """
  Checks if the value is a module that matches a given predicate.

  ## Examples

      iex> zipper = Sourceror.parse_string!("Foo.Bar") |> Sourceror.Zipper.zip()
      iex> Sourceror.Code.Module.module_matching?(zipper, fn mod -> mod == Foo.Bar end)
      true
  """
  def module_matching?(zipper, pred) do
    zipper =
      zipper
      |> Sourceror.Code.Common.maybe_move_to_single_child_block()

    case zipper.node do
      {:__aliases__, _, parts} ->
        pred.(Module.concat(parts))

      value when is_atom(value) ->
        pred.(value)

      _ ->
        false
    end
  end
end
