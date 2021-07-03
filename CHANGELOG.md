# Changelog for Sourceror v0.8

## v0.8.1

### 1. Bug fixes

- [Sourceror] `Sourceror.get_range/1` now correctly calculates the range when
  there is a comment in the same line as the node.

## v0.8.0

### 1. Enhancements

- [Sourceror] Added `Sourceror.patch_string/2`
- [Sourceror] Added the `format: :splicing` option to `Sourceror.to_string/2`

### 2. Bug fixes

- [Sourceror] Now `Sourceror.to_string/2` won't produce invalid Elixir code
  when a keyword list element is at the beginning of a non-keyword list.
- [Sourceror] Now `Sourceror.get_range/1` will take the leading comments into
  account when calculating the range.

## v0.7

The changelog for v0.7 releases can be found [in the v0.7
branch](https://github.com/doorgan/sourceror/blob/v0.7/CHANGELOG.md).
