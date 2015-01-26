defmodule Gex do

  # folder to store repo information
  @gex_dir ".gex"
  # system dependent root directory
  @system_root Path.join(["/"])

  @doc "Initializes an empty repository"
  def init(opts \\ []) do
    unless gex_path do
      File.mkdir @gex_dir
    else
      IO.puts "Already in a gex repository."
    end
  end

  # Serches up the directory tree for a @gex_dir
  # Returns the path if found
  # Returns nil if not found
  defp gex_path(path \\ File.cwd!) do
    if File.dir?( gp = Path.join(path, @gex_dir)) do
      gp
    else
      unless path == @system_root do
        path |> Path.dirname |> gex_path
      end
    end
  end

end
