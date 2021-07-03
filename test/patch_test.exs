defmodule SourcerorTest.PatchTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Patch

  describe "rename_call/2" do
    test "unqualified call" do
      original = ~S"a(foo)"
      expected = ~S"b(foo)"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_call(:b)

      assert expected == Sourceror.patch_string(original, patches)
    end

    test "qualified call" do
      original = ~S"String.to_atom(foo)"
      expected = ~S"String.to_existing_atom(foo)"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_call(:to_existing_atom)

      assert expected == Sourceror.patch_string(original, patches)
    end

    test "with call in new line" do
      original = ~S"""
      String.

      to_atom(foo)
      """

      expected = ~S"""
      String.

      to_existing_atom(foo)
      """

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_call(:to_existing_atom)

      assert expected == Sourceror.patch_string(original, patches)
    end

    test "only the last call on qualified calls" do
      original = ~S"A.b.c(foo)"
      expected = ~S"A.b.changed(foo)"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_call(:changed)

      assert expected == Sourceror.patch_string(original, patches)
    end

    test "calls with do block" do
      original = ~S"if foo do :ok end"
      expected = ~S"unless foo do :ok end"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_call(:unless)

      assert expected == Sourceror.patch_string(original, patches)
    end

    test "sigil" do
      original = ~S"~H(foo)"
      expected = ~S"~F(foo)"

      ast = Sourceror.parse_string!(original)

      patches = Sourceror.Patch.rename_call(ast, "F")
      assert expected == Sourceror.patch_string(original, patches)

      patches = Sourceror.Patch.rename_call(ast, :F)
      assert expected == Sourceror.patch_string(original, patches)

      patches = Sourceror.Patch.rename_call(ast, :sigil_F)
      assert expected == Sourceror.patch_string(original, patches)

      assert_raise ArgumentError, fn -> Sourceror.Patch.rename_call(ast, "nope") end
      assert_raise ArgumentError, fn -> Sourceror.Patch.rename_call(ast, :nope) end
      assert_raise ArgumentError, fn -> Sourceror.Patch.rename_call(ast, :sigil_nope) end
    end

    test "not a sigil" do
      original = ~S"sigil_s(<<45>>, [:foo])"
      expected = ~S"f(<<45>>, [:foo])"

      ast = Sourceror.parse_string!(original)

      patches = Sourceror.Patch.rename_call(ast, :f)
      assert expected == Sourceror.patch_string(original, patches)
    end
  end

  describe "rename_identifier/2" do
    test "renames the identifier" do
      original = ~S"foo"
      expected = ~S"bar"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_identifier(:bar)

      assert expected == Sourceror.patch_string(original, patches)
    end
  end

  describe "rename_kw_keys/2" do
    test "renames the kw key" do
      original = ~S"[a: b, c: d, e: f]"
      expected = ~S"[foo: b, c: d, bar: f]"

      patches =
        original
        |> Sourceror.parse_string!()
        |> Sourceror.Patch.rename_kw_keys(a: :foo, e: :bar)

      assert expected == Sourceror.patch_string(original, patches)
    end
  end
end
