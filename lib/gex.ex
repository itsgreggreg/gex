defmodule Gex do
  # folder to store repo information
  @gex_dir ".gex"
  # system dependent root directory
  @system_root Path.join(["/"])
  # initial contents of a gex repo
  @gex_init_tree [
      HEAD: "ref: refs/heads/master\n",
      config: "",
      objects: [],
      refs: [
        heads: [],
      ]
    ]

  @doc "Initializes an empty repository"
  def init(opts \\ []) do
    unless gex_dir do
      write_tree_to_gex_dir @gex_init_tree, File.cwd!, opts[:bare]
      GexConfig.set :core, bare: (opts[:bare] == true)
      IO.puts "Initialized empty Gex repository in #{gex_dir}"
    else
      IO.puts "Already in a Gex repository."
    end
  end

  @doc "Add files matching eatch `path` to the index."
  def add(paths) do
    assert_in_repo
    assert_repo_not_bare
    Enum.map(paths, &(files_at_path &1))
      |> List.flatten
      |> Enum.uniq
      |> assert_files_found(paths)
      # |> add_files_to_index
  end

  # Takes a tree describing directories and files and
  # writes those dirs and files to the gex dir.
  defp write_tree_to_gex_dir(tree, path, true) do
    write_tree_to_gex_dir(tree, path)
  end
  defp write_tree_to_gex_dir(tree, path, _) do
    File.mkdir!(@gex_dir)
    write_tree_to_gex_dir(tree, Path.join(path, @gex_dir))
  end
  defp write_tree_to_gex_dir(tree, path) do
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
  # or a file named 'config' that contains '[core]'
  # Returns the path if found
  # Returns nil if not found
  def gex_dir(path \\ File.cwd!) do
    gex_dir     = Path.join(path, @gex_dir)
    config_file = Path.join(path, "config")
    cond do
      File.dir? gex_dir -> gex_dir
      GexConfig.valid_file? config_file -> path
      path == @system_root -> nil
      true -> path |> Path.dirname |> gex_dir
    end
  end

  # Returns the path of the working directory
  def working_dir do
    Path.expand "../", gex_dir
  end

  # Make sure we are only working with files that are
  # relative to our working directory
  defp files_at_path(""), do: files_at_path(".")
  defp files_at_path("~"<>_ = path), do: files_at_path Path.expand(path)
  defp files_at_path("/"<>_ = path) do
    case String.contains? path, working_dir do
      true  -> path
        |> String.replace(working_dir, "")
        |> Path.relative
        |> files_at_path
      false -> [] # no files to add at this path
    end
  end
  defp files_at_path(path) do
    cond do
      ignore_path?(path)  -> []   # path ignored, no files to add
      File.regular?(path) -> path # add the file
      File.dir?(path)     ->      # recurse into dir
        for p <- File.ls!(path), do: files_at_path(Path.join(path, p))
      true -> [] # no files to add at this path
    end
  end

  # Make sure a file doesn't match an ignore.
  # Hardcoded for now
  defp ignore_path?(path) do
    Path.extname(path) in ~w|.git .gex|
  end

  # ## Errors
  # Used to halt execution if not in a gex repo
  def assert_in_repo, do: raise_if(!gex_dir, "Not in a gex repo.")

  # Used to halt execution if trying to add files to a bare repo
  def assert_repo_not_bare do
    raise_if(!GexConfig.load.core[:bare], "Not possible in a bare repo.")
  end

  # Used to halt if an action found no files
  def assert_files_found([], paths) do
    raise "pathspecs '#{Enum.join paths, " ,"}' did not match any files"
  end
  def assert_files_found(files, _), do: files

  # Raise a RuntimeError unless cond is true
  defp raise_if(true, msg), do: raise msg
  defp raise_if(false, _), do: :ok

end

defmodule GexConfig do
  # Determines if a path is a valid config file
  def valid_file?(path) do
    case File.read(path) do
      {:ok, contents} -> Regex.match?(~r/\[core\]/, contents)
      {:error, _}     -> false
    end
  end

  # Reads the config file in the gex directory and returns a GexConfig struct
  def load do
    Gex.assert_in_repo
    file = File.stream!(Path.join(Gex.gex_dir, "config"))
    # We go over ever line, parsing out config sections and key/vals
     (Enum.reduce file, {%{}, nil}, fn (line, {config, section}) ->
      cond do
                # matches [(sectionName)]
        match = Regex.run(~r/\[([\d\w]+)\]/, line) ->
                  {config, String.to_atom(List.last(match))}
                # matches (prop)=(val)
        match = Regex.run(~r/\s*(\w*)\s*=\s*([\w:\/.*+]*)/, line) ->
                  [_, prop, val] = match
                  props  = Map.get(config, section, []) ++
                           [{String.to_atom(prop), val}]
                  config = Map.put config, section, props
                  {config, section}
        true  -> {config, section} # skip, no match
      end
    end) |> elem(0) # Return the config we get back from reduce
  end

  # Sets and writes a value to the confige file
  def set(node, [{prop, val}]) do
    config = load
    unless Map.has_key?(config, node), do: config = Map.put(config, node, [])
    put_in(config[node][prop], val)|> dump
  end

  # Dumps a map to a config string
  defp dump(conf) when is_map(conf) do
      (for node <- Map.keys(conf) do
        ["[#{node}]"] ++
        (for {prop, val} <- conf[node] do
          "  #{prop}=#{val}"
        end)
      end)
      |> List.flatten
      |> Enum.join("\n")
      |> write
  end

  # Writes a string to the config file
  defp write(conf) do
    File.write!(Path.join(Gex.gex_dir, "config"), conf<>"\n")
  end
end

