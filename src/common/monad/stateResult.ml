(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(* This monad is a combination of the State and the Result monads
   (for lack of a generic state monad Transformer that could have
   been applied instead).
*)

module type State = sig
  type t
end

module type S = sig
  type s

  type ('a, 'b) r = ('a, 'b) result

  type ('a, 'b) t = s -> ('a, 'b) r * s

  include Base.Monad.S2 with type ('a, 'b) t := ('a, 'b) t

  val put : s -> (unit, 'b) t

  val get : (s, 'b) t

  val option : ('a -> ('c, 'b) t) -> 'a option -> ('c option, 'b) t

  val modify : (s -> s) -> (unit, 'b) t

  val error : 'b -> ('a, 'b) t

  val run : s -> ('a, 'b) t -> ('a, 'b) r * s
end

module Make (S : State) : S with type s = S.t = struct
  type s = S.t

  type ('a, 'b) r = ('a, 'b) result

  type ('a, 'b) t = S.t -> ('a, 'b) r * S.t

  include Base.Monad.Make2 (struct
    type nonrec ('a, 'b) t = ('a, 'b) t

    let bind m ~f s =
      let (x, s') = m s in
      match x with
      | Error _ as x -> (x, s')
      | Ok x -> f x s'

    let map = `Define_using_bind

    let return x s = (Ok x, s)
  end)

  let put s _ = (Ok (), s)

  let get s = (Ok s, s)

  let modify f = get >>= fun st -> put (f st)

  let option f = function
    | Some x -> f x >>| Base.Option.some
    | None -> return None

  let error x s = (Error x, s)

  let run x m = m x
end
