# Changelog for Sourceror v0.9

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.9.0 (2021-12-04)

### 1. Enhancements

- [Sourceror] `to_string/2` now supports options for `Code.quoted_to_algebra`, like `locals_without_parens`
- [Sourceror] `get_range/2` no longer considers comments when calculating the range. This can be enabled by passing the `include_comments: true` option
- [Sourceror.Patch] Introduced `Sourceror.Patch` with utilities to generate patches for the most common rewriting operations
- [Sourceror.Identifier] `Sourceror.Identifier` is now public


## v0.8.0 (2021-06-24)

The changelog for v0.8 releases can be found [in the v0.8
branch](https://github.com/doorgan/sourceror/blob/v0.8/CHANGELOG.md).
