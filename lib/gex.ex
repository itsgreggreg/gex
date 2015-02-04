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
        heads: [ master: "" ],
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
    # TODO: conflicts
    assert_in_repo
    assert_repo_not_bare
    Enum.map(paths, &(files_at_path &1))
      |> List.flatten
      |> Enum.sort
      |> Enum.uniq
      |> assert_files_found(paths)
      |> add_files_to_index
  end

  @doc "Create a commit object from the index"
  def commit do
    #TODO conflicts
    assert_in_repo
    assert_repo_not_bare
    parent_hash = Gex.Refs.hash_at_ref("HEAD")
    read_index
      |> write_trees_from_index      # returns hash of root tree
      |> assert_something_to_commit
      |> write_commit([parent_hash], "this is the commit message")
      |> Gex.Refs.update_ref("HEAD")
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

  defp add_files_to_index(paths) do
    additions = for path <- paths do
      full_path = Path.join(working_dir, path)
      contents  = File.read! full_path
      size      = File.stat!(full_path).size
      hash      = hash_object(contents, size)
      write_object(hash, contents)
      {String.to_atom("0"<>path), hash}
    end
    index = Keyword.merge read_index, additions
    write_index index
  end

  # Writes a blob to the objects folder
  def write_object(hash, contents) do
    {dir, name} = String.split_at hash, 2
    path = Path.join [gex_dir, "objects", dir]
    File.mkdir_p! path
    File.write! Path.join(path,name), contents
    hash
  end

  ## The Index
  # The index in Gex is a lightweight version of the index in Git.
  # The index is the place where you mark files as changed.
  # On a fresh checkout, with no changes or new files in your working
  # directory the index will contain only references to the exact files
  # in your working directory. When you make a change to a file or add
  # a new file nothing immediately happens but once you `add` that file
  # with `git add *file*` you create an `object` in the `object_store` and
  # either update that file's entry in the index, or add a new entry
  # in the case it's a new file. That's it, that's all the index does.
  # Terminology:
  # A file that...
  # is not in the index at all: New/Untracked
  # the same version as what's in the index: Committed/Unchanged
  # is a different version from what's in the index: Changed/Unstaged
  # is in the index but not reachable by any commit: Staged
  # in the index and reachable by a commit: Committed/Unchanged

  ## Workings of the index
  # Each line of the index represents a file version
  # On disk the lines look like:
  # (40bytes hash-of-contents)(1byte status)(variable-len path)
  #  -> 8a418dc51f76644d4ac1ee88b011ab5f52ace83a0file1.txt
  # In memory the index is represented as a key/value store with
  # statuspath being the key and hash the value
  #  -> {:"0file1.txt", "8a418dc51f76644d4ac1ee88b011ab5f52ace83a"}
  # that way we can look up files by path quickly

  # Reads the index file to memory
  def read_index do
    index_path = Path.join gex_dir, "index"
    unless File.exists?(index_path), do: File.write(index_path, "")
    index_file = File.stream!(index_path)
    (for line <- index_file do
      line = String.rstrip line, ?\n
      case String.split_at(line, 40) do
        {hash, id} -> {String.to_atom(id), hash}
        _          -> [] # no match, ignore
      end
    end) |> List.flatten
  end

  # Takes an in memory representation of the index and
  # writes it to disk.
  def write_index(index) do
    str = for {id, hash} <- index, into: "" do
     "#{hash}#{id}\n"
    end
    File.write Path.join(gex_dir, "index"), str
  end

  # Takes in in memory index returned by read_index
  # and writes it and all it's sub trees to the object store
  def write_trees_from_index(index) do
    trees = Enum.reduce index, [], fn ({id, hash}, acc) ->
      {mode, path} = String.split_at(Atom.to_string(id), 1)
      path_parts = Path.split(path)++[hash]
      merge_path_parts(acc, path_parts)
    end
    hash_trees(trees)
  end

  def hash_trees(tree) do
    tree_object = for {key, val} <- tree, into: "" do
      case key do
        :"@@blobs" ->
          for blob <- tree[:"@@blobs"], into: "" do
            {hash, file_name} = String.split_at(blob, 40)
            "blob #{hash} #{file_name}\n"
          end
        _tree      ->
          "tree #{hash_trees(tree[key])} #{key}\n"
      end
    end
    hash = hash_object(tree_object, String.length(tree_object))
    write_object(hash, tree_object)
  end

  # Merges a list of path parts into a keyword list tree
  # takes: [], ["one", "two", "three", *blobHash*]
  # returns: [one: [two: ["@@blobs": "three/blobHash"]]]
  def merge_path_parts(tree, [blob, hash]) do
    Keyword.put tree, :"@@blobs",
       (Keyword.get(tree, :"@@blobs", []) ++ [hash<>blob])
  end
  def merge_path_parts(tree, [part | rest]) do
    part = String.to_atom(part)
    sub  = Keyword.get(tree, part, [])
    Keyword.put(tree, part, merge_path_parts(sub, rest))
  end


  def write_commit(hash, parents, message) do
    file = "commit #{hash}\n" <> (for parent <- parents, into: "" do
      "parent #{parent}\n"
    end) <>
    "date #{inspect :erlang.localtime}\n" <>
    message <> "\n"

    hash_object(file, String.length(file)) |> write_object(file)
  end



  # Produces a git-compatable object hash
  def hash_object(contents, size) do
    :crypto.hash(:sha, "blob #{size}\0#{contents}")
      |> :crypto.bytes_to_integer
      |> Integer.to_string(16)
      |> String.downcase
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

  # Make sure we are only working with paths that are
  # relative to our working directory
  defp files_at_path(""),            do: files_at_path "."
  defp files_at_path("."<>_ = path), do: files_at_path Path.expand(path)
  defp files_at_path("~"<>_ = path), do: files_at_path Path.expand(path)
  defp files_at_path("/"<>_ = path)  do
    case String.contains? path, working_dir do
      true  -> path
        |> String.replace(working_dir, "")
        |> Path.relative
        |> do_files_at_path
      false -> [] # no files to add at this path
    end
  end
  defp files_at_path(path) do
      Path.join(File.cwd!, path)
      |> String.replace(working_dir, "")
      |> Path.relative
      |> do_files_at_path
  end

  # Assuming the path given is relative to working_dir, collect
  # all files under it
  defp do_files_at_path(path) do
    full_path = Path.join(working_dir, path)
    cond do
      ignore_path?(path)       -> []   # path ignored, no files to add
      File.regular?(full_path) -> path # add the file
      File.dir?(full_path)     ->      # recurse into dir
        for p <- File.ls!(full_path), do: do_files_at_path(Path.join(path, p))
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

  # Raise a runtime error if trying to commit the tree HEAD points to
  def assert_something_to_commit(hash) do
    IO.inspect hash
    last_commit = Gex.Refs.hash_at_ref("HEAD")
    #TODO read the root tree of a commit and compare to hash
    case hash == Gex.Refs.hash_at_ref("HEAD") do
      true  -> raise "Nothing to commit"
      false -> hash
    end
  end

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

defmodule Gex.Refs do
  @moduledoc """
  Module for handling refs
  """

  def hash_at_ref("HEAD") do
    file = File.read!(Path.join(Gex.gex_dir, "HEAD"))
    case String.starts_with? file, "ref:" do
      false -> file
      true  ->
        [_, ref] = String.split file, " "
        File.read!(Path.join(Gex.gex_dir, String.strip(ref)))
    end
  end

  def update_ref(hash, "HEAD") do
    file = File.read!(Path.join(Gex.gex_dir, "HEAD"))
    case String.starts_with? file, "ref:" do
      false -> File.write!(Path.join(Gex.gex_dir, "HEAD"), hash)
      true  ->
        [_, ref] = String.split file, " "
        File.write!(Path.join(Gex.gex_dir, String.strip(ref)), hash)
    end
  end

end
