(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Utils_js

val init :
  profiling:Profiling_js.running ->
  workers:MultiWorkerLwt.worker list option ->
  Options.t ->
  (bool (* libs_ok *) * ServerEnv.env) Lwt.t

val calc_deps :
  options:Options.t ->
  profiling:Profiling_js.running ->
  components:File_key.t Nel.t list ->
  FilenameSet.t ->
  File_key.t Nel.t list Lwt.t

(* incremental typecheck entry point *)
val recheck :
  profiling:Profiling_js.running ->
  options:Options.t ->
  workers:MultiWorkerLwt.worker list option ->
  updates:CheckedSet.t ->
  files_to_force:CheckedSet.t ->
  changed_mergebase:bool option ->
  missed_changes:bool ->
  will_be_checked_files:CheckedSet.t ref ->
  ServerEnv.env ->
  ((profiling:Profiling_js.finished -> unit Lwt.t) * LspProt.recheck_stats * ServerEnv.env) Lwt.t

(* initial (full) check *)
val full_check :
  profiling:Profiling_js.running ->
  options:Options.t ->
  workers:MultiWorkerLwt.worker list option ->
  ?focus_targets:FilenameSet.t ->
  ServerEnv.env ->
  (ServerEnv.env * string option) Lwt.t

(* The following are exposed only for testing purposes. Not meant for general consumption. *)

type determine_what_to_recheck_result =
  | Determine_what_to_recheck_result of {
      to_merge: CheckedSet.t;
      to_check: CheckedSet.t;
      (* union of to_merge and to_check *)
      to_merge_or_check: CheckedSet.t;
      components: File_key.t Nel.t list;
      recheck_set: FilenameSet.t;
      sig_dependent_files: FilenameSet.t;
      all_dependent_files: FilenameSet.t;
    }

val debug_determine_what_to_recheck :
  profiling:Profiling_js.running ->
  options:Options.t ->
  sig_dependency_graph:FilenameGraph.t ->
  implementation_dependency_graph:FilenameGraph.t ->
  freshparsed:CheckedSet.t ->
  unchanged_checked:CheckedSet.t ->
  unchanged_files_to_force:CheckedSet.t ->
  dirty_direct_dependents:FilenameSet.t ->
  determine_what_to_recheck_result Lwt.t

val debug_include_dependencies_and_dependents :
  options:Options.t ->
  profiling:Profiling_js.running ->
  unchanged_checked:CheckedSet.t ->
  input:CheckedSet.t ->
  implementation_dependency_graph:FilenameGraph.t ->
  sig_dependency_graph:FilenameGraph.t ->
  sig_dependent_files:FilenameSet.t ->
  all_dependent_files:FilenameSet.t ->
  (CheckedSet.t * CheckedSet.t * CheckedSet.t * File_key.t Nel.t list * FilenameSet.t) Lwt.t

val include_dependencies_and_dependents :
  options:Options.t ->
  profiling:Profiling_js.running ->
  unchanged_checked:CheckedSet.t ->
  input:CheckedSet.t ->
  implementation_dependency_graph:Utils_js.FilenameGraph.t ->
  sig_dependency_graph:Utils_js.FilenameGraph.t ->
  sig_dependent_files:Utils_js.FilenameSet.t ->
  all_dependent_files:Utils_js.FilenameSet.t ->
  (CheckedSet.t * CheckedSet.t * CheckedSet.t * File_key.t Nel.t list * Utils_js.FilenameSet.t)
  Lwt.t
