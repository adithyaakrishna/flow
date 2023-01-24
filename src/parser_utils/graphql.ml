(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Utils_js

type error =
  | InvalidTaggedTemplate
  | InvalidGraphQL

(**
 * GraphQL spec references:
 * Comment: https://spec.graphql.org/June2018/#sec-Comments
 * Ignored tokens (includes commas): https://spec.graphql.org/June2018/#sec-Source-Text.Ignored-Tokens
 *)
let comment_regexp = Str.regexp "^[ \t\n\r,]*#.*"

(**
 * GraphQL spec references:
 * OperationType: https://spec.graphql.org/June2018/#OperationType
 * FragmentDefinition: https://spec.graphql.org/June2018/#FragmentDefinition
 * Whitespace: https://spec.graphql.org/June2018/#sec-White-Space
 * Ignored tokens: (includes commas) https://spec.graphql.org/June2018/#sec-Source-Text.Ignored-Tokens
 * Name: https://spec.graphql.org/June2018/#Name
 *)
let name_regexp =
  Str.regexp
    "^[ \t\n\r,]*\\(query\\|mutation\\|subscription\\|fragment\\)[ \t\n\r,]+\\([_A-Za-z][_0-9A-Za-z]*\\)"

let extract_module_name quasi ~module_prefix =
  let open Flow_ast.Expression.TemplateLiteral in
  match quasi with
  | ( _,
      {
        quasis = [(_, { Element.value = { Element.cooked; raw = _ }; tail = true })];
        expressions = [];
        comments = _;
      }
    ) ->
    (* Remove GraphQL line comments first. *)
    let comment_free = Str.global_replace comment_regexp "" cooked in
    if Str.string_match name_regexp comment_free 0 then
      let name = Str.matched_group 2 comment_free in
      let module_name = spf "%s.graphql" name in
      let prefix = Option.value ~default:"" module_prefix in
      Ok (prefix ^ module_name)
    else
      Error InvalidGraphQL
  | _ -> Error InvalidTaggedTemplate
