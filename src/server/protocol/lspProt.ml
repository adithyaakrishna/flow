(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type client_id = int

type error_kind =
  | ExpectedError
  | UnexpectedError

type error_info = error_kind * string * Utils.callstack

type metadata = {
  (* when did this work-item get triggered? *)
  start_wall_time: float;
  (* What was the thing that triggered this work-item *)
  start_json_truncated: Hh_json.json;
  (* What was the state of the server at the time the work-item was triggered? *)
  (* Might be None e.g. if the server was down at the time or if we don't know *)
  start_server_status: ServerStatus.status option;
  start_watcher_status: FileWatcherStatus.status option;
  (* And what was the state of the lspCommand client? Is optional only to save *)
  (* space in the obvious cases that don't need explanation. *)
  start_lsp_state: string option;
  start_lsp_state_reason: string option;
  (* If handling the workitem resulted in error, what was that error? *)
  error_info: error_info option;
  (* If the workitem was handled on the server, how long did it take there? *)
  server_profiling: Profiling_js.finished option;
  (* and if it had work done on the client, how long there? *)
  client_duration: float option;
  (* Did the handler for this workitem provide any extra data? *)
  extra_data: (string * Hh_json.json) list;
  (* The logging context for the server *)
  server_logging_context: FlowEventLogger.logging_context option;
  (* LSP method (e.g. 'textDocument/completion') *)
  lsp_method_name: string;
  (* If we're tracking an interaction in the lsp process, this is the id of the interaction *)
  interaction_tracking_id: int option;
  (* JSON-RPC id of corresponding LSP request *)
  lsp_id: Lsp.lsp_id option;
}

(** For LSP work-items, we keep metadata about requests, to help us log better telemetry.
    After the work has been handled, we fill out the second part of the metadata.
 *)
let empty_metadata =
  {
    start_wall_time = 0.0;
    start_server_status = None;
    start_watcher_status = None;
    start_json_truncated = Hh_json.JSON_Object [];
    start_lsp_state = None;
    start_lsp_state_reason = None;
    error_info = None;
    server_profiling = None;
    client_duration = None;
    extra_data = [];
    server_logging_context = None;
    lsp_method_name = "";
    interaction_tracking_id = None;
    lsp_id = None;
  }

type request =
  | Subscribe
  | LspToServer of Lsp.lsp_message
  | LiveErrorsRequest of Lsp.DocumentUri.t

type request_with_metadata = request * metadata

(* requests, notifications, responses from client *)

let string_of_request = function
  | Subscribe -> "subscribe"
  | LspToServer msg -> Printf.sprintf "lspToServer %s" (Lsp_fmt.denorm_message_to_string msg)
  | LiveErrorsRequest uri -> Printf.sprintf "liveErrorsRequest %s" (Lsp.DocumentUri.to_string uri)

let string_of_request_with_metadata (request, _) = string_of_request request

let json_of_request =
  Hh_json.(
    function
    | (Subscribe, _) -> JSON_Object [("method", JSON_String "subscribe")]
    | (LspToServer _, metadata) -> metadata.start_json_truncated
    | (LiveErrorsRequest uri, metadata) ->
      JSON_Object
        [
          ("method", JSON_String "liveErrorsRequest");
          ("params", JSON_Object [("uri", JSON_String (Lsp.DocumentUri.to_string uri))]);
          ("trigger", metadata.start_json_truncated);
        ]
  )

(* Why is the server sending us a list of errors *)
type errors_reason =
  | End_of_recheck  (** Sending all the errors at the end of the recheck *)
  | Recheck_streaming  (** Streaming errors during recheck *)
  | Env_change
      (** Sometimes the env changes, which influences which errors we send to
          the lsp. For example, we only send warnings for open files. When a
          file is opened or closed, we have to recalculate which warnings to
          send and send the updated set. *)
  | New_subscription
      (** The persistent client just subscribed to errors, so was sent the
          initial error list *)

type error_response_kind =
  | Canceled_error_response
  | Errored_error_response

type live_errors_failure = {
  live_errors_failure_kind: error_response_kind;
  live_errors_failure_reason: string;
  live_errors_failure_uri: Lsp.DocumentUri.t;
}

type live_errors_response = {
  live_diagnostics: Lsp.PublishDiagnostics.diagnostic list;
  live_errors_uri: Lsp.DocumentUri.t;
}

type response =
  | LspFromServer of Lsp.lsp_message option
  | LiveErrorsResponse of (live_errors_response, live_errors_failure) result
  | UncaughtException of {
      request: request;
      exception_constructor: string;
      stack: string;
    }

type response_with_metadata = response * metadata

type recheck_stats = {
  dependent_file_count: int;
  changed_file_count: int;
  top_cycle: (File_key.t * int) option;  (** name of cycle leader, and size of cycle *)
}

type telemetry_from_server =
  | Init_summary of { duration: float }
  | Recheck_summary of {
      stats: recheck_stats;
      duration: float;
    }
  | Command_summary of {
      name: string;
      duration: float;
    }

type notification_from_server =
  | Errors of {
      diagnostics: Lsp.PublishDiagnostics.diagnostic list Lsp.UriMap.t;
      errors_reason: errors_reason;
    }
  | StartRecheck
  | EndRecheck of ServerProt.Response.lazy_stats
  | ServerExit of Exit.t  (** only used for the subset of exits which client handles *)
  | Please_hold of (ServerStatus.status * FileWatcherStatus.status)
  | Telemetry of telemetry_from_server

type message_from_server =
  | RequestResponse of response_with_metadata
  | NotificationFromServer of notification_from_server

let string_of_response = function
  | LspFromServer None -> "lspFromServer None"
  | LspFromServer (Some msg) ->
    Printf.sprintf "lspFromServer %s" (Lsp_fmt.denorm_message_to_string msg)
  | LiveErrorsResponse (Ok { live_diagnostics; live_errors_uri; _ }) ->
    let (errors, warnings, others) =
      Base.List.fold_left
        ~f:(fun (errors, warnings, others) { Lsp.PublishDiagnostics.severity; _ } ->
          match severity with
          | Some Lsp.PublishDiagnostics.Error -> (errors + 1, warnings, others)
          | Some Lsp.PublishDiagnostics.Warning -> (errors, warnings + 1, others)
          | Some Lsp.PublishDiagnostics.Information
          | Some Lsp.PublishDiagnostics.Hint
          | None ->
            (errors, warnings, others + 1))
        ~init:(0, 0, 0)
        live_diagnostics
    in
    Printf.sprintf
      "liveErrorsResponse OK (%d errors, %d warnings, %d other) %s"
      errors
      warnings
      others
      (Lsp.DocumentUri.to_string live_errors_uri)
  | LiveErrorsResponse
      (Error { live_errors_failure_kind; live_errors_failure_reason; live_errors_failure_uri }) ->
    Printf.sprintf
      "liveErrorsResponse %s %s %s"
      (match live_errors_failure_kind with
      | Canceled_error_response -> "CANCELED"
      | Errored_error_response -> "ERRORED")
      live_errors_failure_reason
      (Lsp.DocumentUri.to_string live_errors_failure_uri)
  | UncaughtException { request; exception_constructor; stack } ->
    Printf.sprintf
      "UncaughtException %s in handling `%s`: %s"
      exception_constructor
      (string_of_request request)
      stack

type message_from_server_mapper = {
  of_live_errors_failure: message_from_server_mapper -> live_errors_failure -> live_errors_failure;
  of_live_errors_response:
    message_from_server_mapper -> live_errors_response -> live_errors_response;
  of_message_from_server: message_from_server_mapper -> message_from_server -> message_from_server;
  of_notification:
    message_from_server_mapper -> notification_from_server -> notification_from_server;
  of_response: message_from_server_mapper -> response -> response;
}

let default_message_from_server_mapper ~(lsp_mapper : Lsp_mapper.t) =
  let open Lsp_mapper in
  {
    of_live_errors_failure =
      (fun _mapper { live_errors_failure_kind; live_errors_failure_reason; live_errors_failure_uri } ->
        let live_errors_failure_uri =
          lsp_mapper.of_document_uri lsp_mapper live_errors_failure_uri
        in
        { live_errors_failure_kind; live_errors_failure_reason; live_errors_failure_uri });
    of_live_errors_response =
      (fun _mapper { live_diagnostics; live_errors_uri } ->
        let live_diagnostics =
          Base.List.map ~f:(lsp_mapper.of_diagnostic lsp_mapper) live_diagnostics
        in
        let live_errors_uri = lsp_mapper.of_document_uri lsp_mapper live_errors_uri in
        { live_diagnostics; live_errors_uri });
    of_message_from_server =
      (fun mapper message ->
        match message with
        | RequestResponse (response, metadata) ->
          RequestResponse (mapper.of_response mapper response, metadata)
        | NotificationFromServer notification ->
          NotificationFromServer (mapper.of_notification mapper notification));
    of_notification =
      (fun _mapper notif ->
        match notif with
        | Errors { diagnostics; errors_reason } ->
          let diagnostics =
            Lsp.UriMap.fold
              (fun uri diags acc ->
                let uri = lsp_mapper.of_document_uri lsp_mapper uri in
                let diags = Base.List.map ~f:(lsp_mapper.of_diagnostic lsp_mapper) diags in
                Lsp.UriMap.add uri diags acc)
              diagnostics
              Lsp.UriMap.empty
          in
          Errors { diagnostics; errors_reason }
        | StartRecheck -> StartRecheck
        | EndRecheck stats -> EndRecheck stats
        | ServerExit exit_status -> ServerExit exit_status
        | Please_hold (server_status, file_watcher_status) ->
          Please_hold (server_status, file_watcher_status)
        | Telemetry t -> Telemetry t);
    of_response =
      (fun mapper response ->
        match response with
        | LspFromServer lsp ->
          LspFromServer (Base.Option.map ~f:(lsp_mapper.of_lsp_message lsp_mapper) lsp)
        | LiveErrorsResponse (Ok live_errors_response) ->
          LiveErrorsResponse (Ok (mapper.of_live_errors_response mapper live_errors_response))
        | LiveErrorsResponse (Error live_errors_failure) ->
          LiveErrorsResponse (Error (mapper.of_live_errors_failure mapper live_errors_failure))
        | UncaughtException { request; exception_constructor; stack } ->
          UncaughtException { request; exception_constructor; stack });
  }
