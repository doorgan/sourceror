defmodule Sourceror.PostwalkState do
  @moduledoc """
  The state struct for `Sourceror.postwalk/3`.
  """
  import Sourceror.Utils.TypedStruct

  typedstruct do
    field :acc, term()
    field :line_correction, integer(), required?: true, default: 0
  end
end
