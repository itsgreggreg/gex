defmodule GexTest do
  use ExUnit.Case

  setup context do
    if context[:fresh_repo] do
      owd = File.cwd!
      test_path  = Path.join(owd, "._test")
      File.mkdir! test_path
      File.cd! test_path
      File.write! "_empty", ""
      File.write! "_foobar", "foobar\n"
      File.mkdir_p "src"
      File.write! Path.join("src", "test.exs"), "IO.puts(\"Elixir\")"
      Gex.init
      on_exit fn ->
        File.cd! owd
        File.rm_rf!("._test")
      end
    end
  end

  @tag :fresh_repo
  test "can init repo" do
    assert File.exists?(".gex")
    assert File.exists?(Path.join(".gex", "config"))
  end

  @tag :fresh_repo
  test "can add files" do
    Gex.add ["_empty"]
    assert File.exists?(Path.join [".gex", "objects",
        "e6", "9de29bb2d1d6434b8b29ae775ad8c2e48c5391"])
    Gex.add ["_foobar"]
    assert File.exists?(Path.join [".gex", "objects",
        "32", "3fae03f4606ea9991df8befbb2fca795e648fa"])
    index = File.stream! Path.join(".gex", "index")
    assert Enum.count(index) == 2
  end

  @tag :fresh_repo
  test "can add files while in a sub directory" do
    File.cd! "src"
    Gex.add ~w|test.exs|
    File.cd! "../"
    IO.inspect File.read!(".gex/index")
    index = File.stream! Path.join(".gex", "index")
    assert Enum.count(index) == 1
  end

  @tag :fresh_repo
  test "can add multiple files" do
    Gex.add ~w|_foobar _empty|
    index = File.stream! Path.join(".gex", "index")
    assert Enum.count(index) == 2
  end

  @tag :fresh_repo
  test "can load gex config" do
    assert GexConfig.load[:core][:bare] == "false"
  end

end
