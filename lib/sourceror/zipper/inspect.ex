defmodule Sourceror.Zipper.Inspect do
  @moduledoc """
  Provides `Sourceror.Zipper`'s implementation for the `Inspect` protocol.

  When inspecting a zipper, the default representation shows the current
  node and provides indicators of the surrounding context without displaying
  the full path, which can be very verbose for large ASTs.

      iex> alias Sourceror.Zipper, as: Z
      Sourceror.Zipper

      iex> code = \"""
      ...> def my_function do
      ...>   :ok
      ...> end\\
      ...> \"""

      iex> zipper = code |> Code.string_to_quoted!() |> Z.zip()
      #Sourceror.Zipper<
        #root
        {:def, [line: 1], [{:my_function, [line: 1], nil}, [do: :ok]]}
      >

      iex> zipper |> Z.next()
      #Sourceror.Zipper<
        {:my_function, [line: 1], nil}
        #...
      >

  This representation can be changed using `default_inspect_as/1` to set a
  global default or by using `:custom_options` with the `:zippers` key when
  inspecting. (See `Inspect.Opts` for more about inspect options.)

  Zippers can be inspected in these formats:

    * `:as_ast` (default, seen above) - display the current node as an AST
    * `:as_code` - display the current node formatted as code
    * `:raw` - display the raw `%Sourceror.Zipper{}` struct including the
      `:path`.

  Using the zipper defined above as an example:

      iex> zipper |> inspect(custom_options: [zipper: :as_code]) |> IO.puts()
      #Sourceror.Zipper<
        #root
        def my_function do
          :ok
        end
      >

      iex> zipper |> Z.next() |> inspect(custom_options: [zipper: :as_code]) |> IO.puts()
      #Sourceror.Zipper<
        my_function
        #...
      >

      iex> zipper |> Z.next() |> inspect(custom_options: [zipper: :raw], pretty: true) |> IO.puts()
      %Sourceror.Zipper{
        node: {:my_function, [line: 1], nil},
        path: %{
          parent: %Sourceror.Zipper{
            node: {:def, [line: 1], [{:my_function, [line: 1], nil}, [do: :ok]]},
            path: nil
          },
          left: nil,
          right: [[do: :ok]]
        }
      }

  """

  import Inspect.Algebra

  alias Sourceror.Zipper, as: Z

  @typedoc """
  Inspection formats for zippers.
  """
  @type inspect_as :: :as_ast | :as_code | :raw

  @doc false
  @spec inspect(Z.t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(zipper, opts) do
    inspect_as = Keyword.get_lazy(opts.custom_options, :zippers, &default_inspect_as/0)
    inspect(zipper, inspect_as, opts)
  end

  @doc false
  @spec inspect(Z.t(), inspect_as, Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(zipper, inspect_as, opts)

  def inspect(zipper, :as_ast, opts) do
    zipper.node
    |> to_doc(opts)
    |> inspect_opaque_zipper(zipper, opts)
  end

  def inspect(zipper, :as_code, opts) do
    zipper.node
    |> Sourceror.to_algebra(Map.to_list(opts))
    |> inspect_opaque_zipper(zipper, opts)
  end

  def inspect(zipper, :raw, opts) do
    open = color("%Sourceror.Zipper{", :map, opts)
    sep = color(",", :map, opts)
    close = color("}", :map, opts)
    list = [node: zipper.node, path: zipper.path]
    fun = fn kw, opts -> Inspect.List.keyword(kw, opts) end

    container_doc(open, list, close, opts, fun, separator: sep)
  end

  defp inspect_opaque_zipper(inner, zipper, opts) do
    opts = maybe_put_zipper_internal_color(opts)

    inner_content =
      [get_prefix(zipper, opts), inner, get_suffix(zipper, opts)]
      |> concat()
      |> nest(2)

    force_unfit(
      concat([
        color("#Sourceror.Zipper<", :map, opts),
        inner_content,
        line(),
        color(">", :map, opts)
      ])
    )
  end

  defp get_prefix(%Z{path: nil}, opts), do: concat([line(), internal("#root", opts), line()])

  defp get_prefix(%Z{path: %{left: [_ | _]}}, opts),
    do: concat([line(), internal("#...", opts), line()])

  defp get_prefix(_, _), do: line()

  defp get_suffix(%Z{path: %{right: [_ | _]}}, opts),
    do: concat([line(), internal("#...", opts)])

  defp get_suffix(_, _), do: empty()

  defp internal(string, opts), do: color(string, :zipper_internal, opts)

  # This prevents colorizing in contexts where no other syntax colors
  # are present, e.g. in a test. Is there a better way to check this?
  defp maybe_put_zipper_internal_color(%Inspect.Opts{syntax_colors: []} = opts), do: opts

  defp maybe_put_zipper_internal_color(%Inspect.Opts{syntax_colors: colors} = opts) do
    %{opts | syntax_colors: Keyword.put_new(colors, :zipper_internal, :light_black)}
  end

  @doc false
  def default_inspect_as do
    :persistent_term.get({__MODULE__, :inspect_as}, :as_ast)
  end

  @doc """
  Sets the default inspection format for zippers.

  ## Examples

  Consider the following zipper:

      iex> zipper
      #Sourceror.Zipper<
        #root
        {:def, [line: 1], [{:my_function, [line: 1], nil}, [do: :ok]]}
      >

      iex> Sourceror.Zipper.Inspect.default_inspect_as(:as_code)
      :ok
      iex> zipper
      #Sourceror.Zipper<
        #root
        def my_function do
          :ok
        end
      >

      iex> Sourceror.Zipper.Inspect.default_inspect_as(:raw)
      :ok
      iex> zipper
      %Sourceror.Zipper{
        node: {:def, [line: 1], [{:my_function, [line: 1], nil}, [do: :ok]]},
        path: nil
      }

  """
  @spec default_inspect_as(inspect_as) :: :ok
  def default_inspect_as(inspect_as) when inspect_as in [:as_ast, :as_code, :raw] do
    :persistent_term.put({__MODULE__, :inspect_as}, inspect_as)
  end
end

defimpl Inspect, for: Sourceror.Zipper do
  alias Sourceror.Zipper, as: Z
  defdelegate inspect(zipper, opts), to: Z.Inspect
end
