(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open ServerEnv
open Utils_js

(* combine error maps into a single error set and a filtered warning map
 *
 * This can be a little expensive for large repositories and can take a couple of seconds.
 * Therefore there are a few things we want to do:
 *
 * 1. Memoize the result in env. This means subsequent calls to commands like `flow status` can
 *    be fast
 * 2. Eagerly calculate `collate_errors` after init or a recheck, so that the server still has
 *    the init or recheck lock. If we improve how clients can tell if a server is busy or stuck
 *    then we can probably relax this.
 * 3. Throw away the collated errors when lazy mode adds more dependents or dependencies to the
 *    checked set
 * *)
let regenerate ~reader =
  let open Errors in
  let loc_of_aloc = Parsing_heaps.Reader.loc_of_aloc ~reader in
  let add_suppression_warnings checked unused warnings =
    (* For each unused suppression, create an warning *)
    let all_locs = Error_suppressions.all_unused_locs unused in
    let warnings =
      Loc_collections.LocSet.fold
        (fun loc warnings ->
          let source_file =
            match Loc.source loc with
            | Some x -> x
            | None -> File_key.SourceFile "-"
          in
          (* In lazy mode, dependencies are modules which we typecheck not because we care about
           * them, but because something important (a focused file or a focused file's dependent)
           * needs these dependencies. Therefore, we might not typecheck a dependency's dependents.
           *
           * This means there might be an unused suppression comment warning in a dependency which
           * only shows up in lazy mode. To avoid this, we'll just avoid raising this kind of
           * warning in any dependency. *)
          if not (CheckedSet.mem_dependency source_file checked) then
            let err =
              let msg = Error_message.EUnusedSuppression loc in
              Flow_error.error_of_msg ~trace_reasons:[] ~source_file msg
              |> Flow_error.make_error_printable
            in
            let file_warnings =
              FilenameMap.find_opt source_file warnings
              |> Base.Option.value ~default:ConcreteLocPrintableErrorSet.empty
              |> ConcreteLocPrintableErrorSet.add err
            in
            FilenameMap.add source_file file_warnings warnings
          else
            warnings)
        all_locs
        warnings
    in
    Error_suppressions.CodeLocSet.fold
      (fun (code, loc) warnings ->
        let source_file =
          match Loc.source loc with
          | Some x -> x
          | None -> File_key.SourceFile "-"
        in
        let err =
          Error_message.ECodelessSuppression (loc, code)
          |> Flow_error.error_of_msg ~trace_reasons:[] ~source_file
          |> Flow_error.make_error_printable
        in
        let file_warnings =
          FilenameMap.find_opt source_file warnings
          |> Base.Option.value ~default:ConcreteLocPrintableErrorSet.empty
          |> ConcreteLocPrintableErrorSet.add err
        in
        FilenameMap.add source_file file_warnings warnings)
      (Error_suppressions.universally_suppressed_codes unused)
      warnings
  in
  let acc_fun
      (type a)
      ~options
      suppressions
      (f : File_key.t -> ConcreteLocPrintableErrorSet.t -> a -> a)
      filename
      file_errs
      (errors, suppressed, unused) =
    let root = Options.root options in
    let file_options = Some (Options.file_options options) in
    let (file_errs, file_suppressed, unused) =
      file_errs
      |> Flow_error.concretize_errors loc_of_aloc
      |> Flow_error.make_errors_printable
      |> Error_suppressions.filter_suppressed_errors ~root ~file_options suppressions ~unused
    in
    let errors = f filename file_errs errors in
    let suppressed = List.rev_append file_suppressed suppressed in
    (errors, suppressed, unused)
  in
  let collate_duplicate_providers =
    let pos = Loc.{ line = 1; column = 0 } in
    let f module_name provider acc duplicate =
      let conflict = Loc.{ source = Some duplicate; start = pos; _end = pos } in
      let err =
        Error_message.EDuplicateModuleProvider { module_name; provider; conflict }
        |> Flow_error.error_of_msg ~trace_reasons:[] ~source_file:duplicate
        |> Flow_error.make_error_printable
      in
      Errors.ConcreteLocPrintableErrorSet.add err acc
    in
    let f module_name (provider, duplicates) acc =
      let provider = Loc.{ source = Some provider; start = pos; _end = pos } in
      Nel.fold_left (f module_name provider) acc duplicates
    in
    SMap.fold f
  in
  fun ~options env ->
    MonitorRPC.status_update ~event:ServerStatus.Collating_errors_start;
    let { local_errors; duplicate_providers; merge_errors; warnings; suppressions } = env.errors in
    let collated_errorset =
      collate_duplicate_providers duplicate_providers ConcreteLocPrintableErrorSet.empty
    in
    let acc_err_fun = acc_fun ~options suppressions (fun _ -> ConcreteLocPrintableErrorSet.union) in
    let (collated_errorset, collated_suppressed_errors, unused) =
      (collated_errorset, [], suppressions)
      |> FilenameMap.fold acc_err_fun local_errors
      |> FilenameMap.fold acc_err_fun merge_errors
    in
    let acc_warn_fun = acc_fun ~options suppressions FilenameMap.add in
    let (warnings, collated_suppressed_errors, unused) =
      (FilenameMap.empty, collated_suppressed_errors, unused)
      |> FilenameMap.fold acc_warn_fun warnings
    in
    let collated_warning_map = add_suppression_warnings env.checked_files unused warnings in
    { collated_errorset; collated_warning_map; collated_suppressed_errors }

let get_with_separate_warnings_no_profiling ~reader ~options env =
  let collated_errors =
    match !(env.collated_errors) with
    | None ->
      let collated_errors = regenerate ~reader ~options env in
      env.collated_errors := Some collated_errors;
      collated_errors
    | Some collated_errors -> collated_errors
  in
  let { collated_errorset; collated_warning_map; collated_suppressed_errors } = collated_errors in
  (collated_errorset, collated_warning_map, collated_suppressed_errors)

let get_with_separate_warnings ~profiling ~reader ~options env =
  Profiling_js.with_timer ~timer:"CollateErrors" profiling ~f:(fun () ->
      get_with_separate_warnings_no_profiling ~reader ~options env
  )

(* combine error maps into a single error set and a single warning set *)
let get ~profiling ~reader ~options env =
  Profiling_js.with_timer ~timer:"CollateErrors" profiling ~f:(fun () ->
      Errors.(
        let (errors, warning_map, suppressed_errors) =
          get_with_separate_warnings_no_profiling ~reader ~options env
        in
        let warnings =
          FilenameMap.fold
            (fun _key -> ConcreteLocPrintableErrorSet.union)
            warning_map
            ConcreteLocPrintableErrorSet.empty
        in
        (errors, warnings, suppressed_errors)
      )
  )
