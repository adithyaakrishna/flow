(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

val subst :
  Context.t -> ?use_op:Type.use_op -> ?force:bool -> Type.t Subst_name.Map.t -> Type.t -> Type.t

val subst_class_bindings :
  Context.t ->
  ?use_op:Type.use_op ->
  ?force:bool ->
  Type.t Subst_name.Map.t ->
  Type.class_binding list ->
  Type.class_binding list

val subst_destructor :
  Context.t ->
  ?use_op:Type.use_op ->
  ?force:bool ->
  Type.t Subst_name.Map.t ->
  Type.destructor ->
  Type.destructor
