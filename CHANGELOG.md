# Changelog for Sourceror v0.4

## v0.4

### 1. Enhancements

  * [Sourceror] - Add `Sourceror.get_meta/1`, `Sourceror.get_args/1`,
    `Sourceror.get_line/2`, `Sourceror.get_column/2` and
    `Sourceror.get_end_line/2`.
  * [Sourceror] - Add `Sourceror.update_args/2`.
  * [Sourceror] - Add `Sourceror.get_start_position/2`,
    `Sourceror.get_end_position/2`, `Sourceror.get_range/1` and
    `Sourceror.get_line_span`.
  * [Sourceror] - Add `Sourceror.compare_positions/2`.
  * [Sourceror] - `Sourceror.correct_lines/3` now corrects comments line
    numbers, preserving the relative numbers from the associated node.
  * [Sourceror.Comments] - `Sourceror.Comments.extract_comments/1` now preserves
    the comments line numbers.

### 2. Bug Fixes
  * [Sourceror] - Now `Sourceror.postwalk/3` correctly propagates line
    corrections to parent nodes.
  * [Sourceror] - Now `Sourceror.postwalk/3` corrects end line numbers(`end`,
    `closing`, `end_of_expression`) appropiately.
