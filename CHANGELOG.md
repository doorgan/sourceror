# Changelog for Sourceror v0.11

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.11.2 (2022-08-15)

### 1. Bug fixes
  - [Sourceror] `Sourceror.parse` now handles files with only comments (Thanks
    to @NickNeck)
  - [Sourceror] Fixed warnings about missing modules in compatibility mode
    modules (Thanks to @NickNeck)


## v0.11.1 (2022-04-07)

### 1. Bug fixes
  [Sourceror.Zipper] Zipper functions to work with ended zippers (Thanks to @NickNeck)


## v0.11.0 (2022-04-03)

### 1. Enhancements

- [Sourceror.Zipper] Added `skip` (Thanks to @NickNeck)
- [Sourceror.Zipper] Added a `direction` to `zip` (Thanks to @NickNeck)

### 2. Bug fixes

- [Sourceror] Comments are no longer misplaced for `:__block__` nodes
  with trailing comments
- [Sourceror] Blocks with trailing comments are no longer force-formatted with
  parenthesis.

## v0.10.0 (2022-02-06)

The changelog for v0.10 releases can be found [in the 0.10
branch](https://github.com/doorgan/sourceror/blob/v0.10/CHANGELOG.md).
