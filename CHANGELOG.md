# Changelog for Sourceror v0.8

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.8.4 (2021-09-15)

### 1. Bug fixes

- [Sourceror] `get_range/1` now properly handles naked AST lists, like the ones
  coming from partial keyword lists, or stabs like `a -> b`.

## v0.8.3 (2021-09-13)

### 1. Bug fixes

- [Sourceror] `get_range/1` now handles partial keyword list syntax instead of
  crashing.

## v0.8.2 (2021-08-12)

### 1. Bug fixes

- [Sourceror.Zipper] `down/1` now correctly uses `nil` as the right siblings if
  the branch node has a single child.

## v0.8.1 (2021-07-03)

### 1. Bug fixes

- [Sourceror] `Sourceror.get_range/1` now correctly calculates the range when
  there is a comment in the same line as the node.

## v0.8.0 (2021-06-24)

### 1. Enhancements

- [Sourceror] Added `Sourceror.patch_string/2`
- [Sourceror] Added the `format: :splicing` option to `Sourceror.to_string/2`

### 2. Bug fixes

- [Sourceror] Now `Sourceror.to_string/2` won't produce invalid Elixir code
  when a keyword list element is at the beginning of a non-keyword list.
- [Sourceror] Now `Sourceror.get_range/1` will take the leading comments into
  account when calculating the range.

## v0.7.0 (2021-06-12)

The changelog for v0.7 releases can be found [in the v0.7
branch](https://github.com/doorgan/sourceror/blob/v0.7/CHANGELOG.md).
