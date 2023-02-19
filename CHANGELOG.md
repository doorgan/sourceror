# Changelog for Sourceror v0.12

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.12.1 (2023-02-19)


### 1. Enhancements
  - [Sourceror] Added the option `quoted_to_algebra` to `to_string`, which
  allows the usage of other formatters like `FreedomFormatter`.
  - [Sourcderor] Now `to_string` uses the `locals_without_parens` from your
    project by default.

### 2. Bug fixes
  - [Sourceror] Fixed a bug that causes `get_rage` to crash on the AST for
    anonymous function calls.

### 1. Bug fixes
  - [Sourceror] `Sourceror.patch_string` now produces better results when
    patching a single line with a multiline replacement (Thanks to @zachallaun)
  - [Sourceror.Zipper] the concept of an "ended" zipper was removed, so now you
    can traverse the same zipper multiple times without having to manualy reset
    it (thanks to @novaugust)

## v0.12.0 (2023-02-04)

### 1. Bug fixes
  - [Sourceror] `Sourceror.patch_string` now produces better results when
    patching a single line with a multiline replacement (Thanks to @zachallaun)
  - [Sourceror.Zipper] the concept of an "ended" zipper was removed, so now you
    can traverse the same zipper multiple times without having to manualy reset
    it (thanks to @novaugust)


## v0.11.2 (2022-08-15)

The changelog for v0.11 releases can be found [in the 0.11
branch](https://github.com/doorgan/sourceror/blob/v0.11/CHANGELOG.md).
