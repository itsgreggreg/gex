defmodule Gex.CLI do

  def main(opts) do
    {switches, [action], _} = OptionParser.parse opts
    apply(Gex, :init, [switches])
  end

end
