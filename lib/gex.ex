defmodule Gex do

  # folder to store repo information
  @gex_dir ".gex"
  # system dependent root directory
  @system_root Path.join(["/"])

  @doc "Initializes an empty repository"
  def init(opts \\ []) do
    unless gex_path do
      File.mkdir @gex_dir
      # A keyword list that gets converted into a tree
      # of directories and files needed to init a gex repo.
      gex_init_tree = [
        HEAD: "ref: refs/heads/master\n",
        # If `--bare` was passed, write to the Git config indicating
        # that the repository is bare. If `--bare` was not passed,
        # write to the Git config saying the repository is not bare.
        # config: GexConfig.to_string([
        #            core: [ "": [ bare: opts.bare === true ]]
        #         ]),
        objects: [],
        refs: [
          heads: [],
        ]
      ]
      write_tree_to_gex_dir(gex_init_tree)
    else
      IO.puts "Already in a gex repository."
    end
  end

  # Takes a tree describing directories and files and
  # writes those dirs and files to the gex dir.
  defp write_tree_to_gex_dir(tree, path \\ gex_path) do
    for key <- Keyword.keys(tree) do
      path = Path.join(path, Atom.to_string(key))
      case tree[key] do
        # If it is a string, write it as a file
        file when is_binary(file) ->
          File.write!(path, file)
        # If it is a list, make the dir and
        # recurse into it
        tree when is_list(tree) ->
          unless File.exists?(path), do: File.mkdir(path)
          write_tree_to_gex_dir(tree, path)
      end
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


defmodule GexConfig do
  defstruct core: []

  def to_string do

  end
end
