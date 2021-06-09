# Changelog for Sourceror v0.6.0

This release introduces some **breaking changes**, as the way comments are
handled by the library has been fundamentally changed.

## v0.6.0

### 1. Enhancements
  * [Sourceror] - `to_string` no longer requires line number corrections to
    produce properly formatted code.
  * [Sourceror] - Added `prewalk/2` and `prewalk/3`.
  * [Sourceror] - `parse_string` won't warn on unnecesary quotes.
  * [Sourceror.TraversalState] - `Sourceror.PostwalkState` was renamed to
    `Sourceror.TraversalState` to make it more generic for other kinds of
    traversals.

### 2. Removals
  * [Sourceror] - `get_line_span` was removed in favor of using `get_range` and
    calculating the difference from the range start and end lines.
  * [Sourceror.TraversalState] - `line_correction` field was removed as it is no
    longer needed.

### 3. Bug fixes
  * [Sourceror] - `get_range` now properly returns ranges that map a node to
    it's actual start and end positions in the original source code.

## v0.5.0

The changelog for v0.5 releases can be found [in the v0.5.0
tag](https://github.com/doorgan/sourceror/blob/v0.5.0/CHANGELOG.md).
