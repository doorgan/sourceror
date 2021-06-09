defmodule Sourceror.TraversalState do
  @moduledoc """
  The state struct for Sourceror traversal functions.
  """
  import Sourceror.Utils.TypedStruct

  typedstruct do
    field :acc, term()
  end
end
