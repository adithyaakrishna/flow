(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

val type_at_pos :
  cx:Context.t ->
  file_sig:File_sig.With_Loc.t ->
  typed_ast:(ALoc.t, ALoc.t * Type.t) Flow_ast.Program.t ->
  omit_targ_defaults:bool ->
  evaluate_type_destructors:Ty_normalizer_env.evaluate_type_destructors_mode ->
  max_depth:int ->
  verbose_normalizer:bool ->
  File_key.t ->
  int ->
  int ->
  (Loc.t * Ty.elt option) * (string * Hh_json.json) list

val dump_types :
  evaluate_type_destructors:Ty_normalizer_env.evaluate_type_destructors_mode ->
  Context.t ->
  File_sig.With_Loc.t ->
  (ALoc.t, ALoc.t * Type.t) Flow_ast.Program.t ->
  (Loc.t * string) list

val coverage :
  cx:Context.t ->
  typed_ast:(ALoc.t, ALoc.t * Type.t) Flow_ast.Program.t ->
  force:bool ->
  trust:bool ->
  File_key.t ->
  string ->
  (Loc.t * Coverage_response.expression_coverage) list
