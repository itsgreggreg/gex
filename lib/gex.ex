defmodule GexConfig do
  defstruct core: []

  # Dumps a GexConfig struct to a string
  def to_string(conf) do
    if core = conf.core do
       "[core]\n" <> for {key, val} <- core, into: "" do
         "  #{key} = #{val}\n"
       end
    end
  end

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
    file = File.stream!(Path.join(Gex.gex_path, "config"))
    # We go over ever line, parsing out config sections and key/vals
    {config, _} = Enum.reduce file, {%GexConfig{}, nil}, fn (line, {config, section}) ->
      cond do
                # matches [(sectionName)]
        match = Regex.run(~r/\[([\d\w]+)\]/, line) ->
                  {config, String.to_atom(List.last(match))}
                # matches (prop)=(val)
        match = Regex.run(~r/\s*(\w*)\s*=\s*([\w:\/.*+]*)/, line) ->
                  [_, prop, val] = match
                  props  = Map.get(config, section) ++ [{String.to_atom(prop), val}]
                  config = Map.put config, section, props
                  {config, section}
        true  -> {config, section}
      end
    end
    config
  end
end

defmodule Gex do
  # folder to store repo information
  @gex_dir ".gex"
  # system dependent root directory
  @system_root Path.join(["/"])

  @doc "Initializes an empty repository"
  def init(opts \\ []) do
    unless gex_path do
      unless opts[:bare], do: File.mkdir!(@gex_dir)
      if opts[:bare], do: File.write!("config", "[core]")
      # A keyword list that gets converted into a set of
      # directories and files needed to init a gex repo.
      gex_init_tree = [
        HEAD: "ref: refs/heads/master\n",
        config: GexConfig.to_string(%GexConfig{
                   :core => [ bare: opts[:bare] == true ]}),
        objects: [],
        refs: [
          heads: [],
        ]
      ]
      write_tree_to_gex_dir(gex_init_tree)
      IO.puts "Initialized empty Gex repository in #{gex_path}"
    else
      IO.puts "Already in a Gex repository."
    end
  end

  @doc "Add files matching `path` to the index."
  def add(path) do
    assert_in_repo
    assert_repo_not_bare


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
  # or a file named 'config' that contains '[core]'
  # Returns the path if found
  # Returns nil if not found
  def gex_path(path \\ File.cwd!) do
    gex_dir     = Path.join(path, @gex_dir)
    config_file = Path.join(path, "config")
    cond do
      File.dir? gex_dir -> gex_dir
      GexConfig.valid_file? config_file -> path
      path == @system_root -> nil
      true -> path |> Path.dirname |> gex_path
    end
  end

  # Used to halt execution if not in a gex repo
  def assert_in_repo do
    case gex_path do
      nil -> raise(RuntimeError, message: "Not in a gex repo.")
      _   -> :ok
    end
  end

  # Used to halt execution if trying to add files to a bare repo
  def assert_repo_not_bare do
    case GexConfig.load.core[:bare] do
      true -> raise(RuntimeError, message: "You cannot add files to a bare repo.")
      _    -> :ok
    end
  end

end


