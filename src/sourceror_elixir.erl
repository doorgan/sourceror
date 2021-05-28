%% Main entry point for Elixir functions. All of those functions are
%% private to the Elixir compiler and reserved to be used by Elixir only.
-module(sourceror_elixir).
-export([string_to_tokens/5, tokens_to_quoted/3, 'string_to_quoted!'/5]).
-include("sourceror_elixir.hrl").
-define(system, 'Elixir.System').

%% Top level types
%% TODO: Remove char_list type on v2.0
-export_type([charlist/0, char_list/0, nonempty_charlist/0, struct/0, as_boolean/1, keyword/0, keyword/1]).
-type charlist() :: string().
-type char_list() :: string().
-type nonempty_charlist() :: nonempty_string().
-type as_boolean(T) :: T.
-type keyword() :: [{atom(), any()}].
-type keyword(T) :: [{atom(), T}].
-type struct() :: #{'__struct__' := atom(), atom() => any()}.

%% Converts a given string (charlist) into quote expression

string_to_tokens(String, StartLine, StartColumn, File, Opts) when is_integer(StartLine), is_binary(File) ->
  case sourceror_elixir_tokenizer:tokenize(String, StartLine, StartColumn, [{file, File} | Opts]) of
    {ok, _Tokens} = Ok ->
      Ok;
    {error, {Line, Column, {ErrorPrefix, ErrorSuffix}, Token}, _Rest, _SoFar} ->
      Location = [{line, Line}, {column, Column}],
      {error, {Location, {to_binary(ErrorPrefix), to_binary(ErrorSuffix)}, to_binary(Token)}};
    {error, {Line, Column, Error, Token}, _Rest, _SoFar} ->
      Location = [{line, Line}, {column, Column}],
      {error, {Location, to_binary(Error), to_binary(Token)}}
  end.

tokens_to_quoted(Tokens, File, Opts) ->
  handle_parsing_opts(File, Opts),

  try sourceror_elixir_parser:parse(Tokens) of
    {ok, Forms} ->
      {ok, Forms};
    {error, {Line, _, [{ErrorPrefix, ErrorSuffix}, Token]}} ->
      {error, {parser_location(Line), {to_binary(ErrorPrefix), to_binary(ErrorSuffix)}, to_binary(Token)}};
    {error, {Line, _, [Error, Token]}} ->
      {error, {parser_location(Line), to_binary(Error), to_binary(Token)}}
  after
    erase(elixir_parser_file),
    erase(elixir_parser_columns),
    erase(elixir_token_metadata),
    erase(elixir_literal_encoder)
  end.

parser_location({Line, Column, _}) ->
  [{line, Line}, {column, Column}];
parser_location(Meta) ->
  Line =
    case lists:keyfind(line, 1, Meta) of
      {line, L} -> L;
      false -> 0
    end,

  case lists:keyfind(column, 1, Meta) of
    {column, C} -> [{line, Line}, {column, C}];
    false -> [{line, Line}]
  end.

'string_to_quoted!'(String, StartLine, StartColumn, File, Opts) ->
  case string_to_tokens(String, StartLine, StartColumn, File, Opts) of
    {ok, Tokens} ->
      case tokens_to_quoted(Tokens, File, Opts) of
        {ok, Forms} ->
          Forms;
        {error, {Line, Error, Token}} ->
          elixir_errors:parse_error(Line, File, Error, Token)
      end;
    {error, {Line, Error, Token}} ->
      elixir_errors:parse_error(Line, File, Error, Token)
  end.

to_binary(List) when is_list(List) -> elixir_utils:characters_to_binary(List);
to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8).

handle_parsing_opts(File, Opts) ->
  LiteralEncoder =
    case lists:keyfind(literal_encoder, 1, Opts) of
      {literal_encoder, Fun} -> Fun;
      false -> false
    end,
  TokenMetadata = lists:keyfind(token_metadata, 1, Opts) == {token_metadata, true},
  Columns = lists:keyfind(columns, 1, Opts) == {columns, true},
  put(elixir_parser_file, File),
  put(elixir_parser_columns, Columns),
  put(elixir_token_metadata, TokenMetadata),
  put(elixir_literal_encoder, LiteralEncoder).