# Changelog for Sourceror v1.0

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.2.1 (2024-05-23)

### 1. Bug fixes
- [Sourceror] Fixed line/column metadata for map literals.

## v1.2.0 (2024-05-22)

### 1. Enhancements
- [Sourceror.Zipper] Added `subtree/1` to get a zipper for the current node.

## v1.1.0 (2024-05-09)

### 1. Bug fixes
- [Sourceror] Fix trailing comments being misplaced

## v1.0.3 (2024-04-12)

### 1. Bug fixes

- [Sourceror] Fix `Sourceror.get_range` for interpolation nodes inside
  strings and charlists

## v1.0.2 (2024-03-13)

### 1. Bug fixes

- [Sourceror] Fix `Sourceror.get_range` for binaries
- [Sourceror] Fix `Sourceror.get_range` for `do`/`end` blocks that have
  `end_of_expression` metadata

## v1.0.1 (2024-01-04)

### 1. Bug fixes

- [Sourceror] Fix `Sourceror.get_range` returning incorrect ranges for
  anonymous functions with empty bodies

## v1.0.0 (2023-12-28)

### 1. Bug fixes

- [Sourceror] Add support for Elixir 1.16

## v0.13.0 (2023-08-23)

The changelog for v0.14 releases can be found [in the 0.14
branch](https://github.com/doorgan/sourceror/blob/v0.14/CHANGELOG.md).
