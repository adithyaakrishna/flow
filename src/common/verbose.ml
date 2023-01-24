(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type t = {
  indent: int;
  depth: int;
  enabled_during_flowlib: bool;
  focused_files: string list option;
}
