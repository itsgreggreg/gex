defmodule GexTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
  end

  setup do
    File.write! "_empty", ""
    File.write! "_foobar", "foobar\n"
    on_exit fn ->
      File.rm! "_empty"
      File.rm! "_foobar"
    end
  end

  test "can calculate correct git hashes" do
    assert Gex.hash_file("_empty") ==
        "E69DE29BB2D1D6434B8B29AE775AD8C2E48C5391"
    assert Gex.hash_file("_foobar") ==
        "323FAE03F4606EA9991DF8BEFBB2FCA795E648FA"
  end
end
