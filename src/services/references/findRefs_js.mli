(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

val find_local_refs :
  reader:State_reader.t ->
  options:Options.t ->
  profiling:Profiling_js.running ->
  file_key:File_key.t ->
  content:string ->
  line:int ->
  col:int ->
  (FindRefsTypes.find_refs_ok, string) result
