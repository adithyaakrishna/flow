(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module Ast = Flow_ast
open Reason
open Loc_collections
open Name_def
open Dependency_sigs
module EnvMap = Env_api.EnvMap
module EnvSet = Flow_set.Make (Env_api.EnvKey)

module Tarjan =
  Tarjan.Make
    (struct
      include Env_api.EnvKey

      let to_string (_, l) = ALoc.debug_to_string l
    end)
    (EnvMap)
    (EnvSet)

type element =
  | Normal of Env_api.EnvKey.t
  | Resolvable of Env_api.EnvKey.t
  | Illegal of {
      loc: Env_api.EnvKey.t;
      reason: ALoc.t virtual_reason;
      recursion: ALoc.t Nel.t;
    }

type result =
  | Singleton of element
  | ResolvableSCC of element Nel.t
  | IllegalSCC of (element * ALoc.t virtual_reason * ALoc.t Nel.t) Nel.t

module Make (Context : C) (FlowAPIUtils : F with type cx = Context.t) = struct
  module FindDependencies : sig
    val depends : Context.t -> Env_api.env_info -> ALoc.t -> Name_def.def -> ALoc.t Nel.t EnvMap.t

    val recursively_resolvable : Name_def.def -> bool
  end = struct
    (* This analysis consumes variable defs and returns a map representing the variables that need to be
       resolved before we can resolve this def.

       Consider for example the program

         1: var x = 42;
         2: type T = typeof x;

       And let's specifically look at the def `TypeAlias(type T = typeof x)`, which will be one of the
       defs generated by the analysis in `name_def.ml`. Given this def, the question that this module
       answers is what variable definitions need to be resolved before the `TypeAlias` def itself can be resolved.

       We can see that the type alias depends on reading `x`, so in order to actually resolve the type alias, we
       first need to know the type of `x`. In order to do that, we need to have resolved the writes that (according
       to the name_resolver) reach this reference to `x`. That's what this analysis tells us--it will traverse the
       TypeAlias def, find the read of `x`, and add the writes to `x` that reach that read to the set of defs that need to
       be resolved before the type alias can be resolved. We'll ultimately use this to figure out the correct ordering
       of nodes.

       The actual output of this analysis is a map, whose keys are the locations of variables whose defs need to be resolved
       before this def can be. The values of this map are the locations within the def itself that led us to those variable definitions--
       in this case, the result will be [def of `x`] => [dereference of `x`]. This information is included for good error messages eventually,
       but the more important bit for the correctness of the analysis is the keys of the map--it may be easier to think of the map
       as a set and ignore the values.
    *)

    (* Helper class for the dependency analysis--traverse the AST nodes
       in a def to determine which variables appear *)
    class use_visitor cx ({ Env_api.env_values; env_entries; _ } as env) init =
      object (this)
        inherit [ALoc.t Nel.t EnvMap.t, ALoc.t] Flow_ast_visitor.visitor ~init as super

        val mutable this_ = None

        method this_ = this_

        method set_this_ this_' = this_ <- this_'

        method add ~why t =
          this#update_acc (fun uses ->
              EnvMap.update
                t
                (function
                  | None -> Some (Nel.one why)
                  | Some locs -> Some (Nel.cons why locs))
                uses
          )

        method find_writes ~for_type loc =
          let write_locs =
            try Env_api.write_locs_of_read_loc env_values loc with
            | Not_found ->
              FlowAPIUtils.add_output cx Error_message.(EInternal (loc, MissingEnvRead loc));
              []
          in
          let writes = Base.List.concat_map ~f:(Env_api.writes_of_write_loc ~for_type) write_locs in
          let refinements =
            Base.List.concat_map ~f:(Env_api.refinements_of_write_loc env) write_locs
          in
          let rec writes_of_refinement refi =
            let open Env_api.Refi in
            match refi with
            | InstanceOfR ((_loc, _) as exp)
            | LatentR { func = (_loc, _) as exp; _ } ->
              ignore (this#expression exp)
            | AndR (l, r)
            | OrR (l, r) ->
              writes_of_refinement l;
              writes_of_refinement r
            | NotR r -> writes_of_refinement r
            | TruthyR
            | NullR
            | UndefinedR
            | MaybeR
            | IsArrayR
            | BoolR _
            | FunctionR
            | NumberR _
            | ObjectR
            | StringR _
            | SentinelR _
            | SymbolR _
            | SingletonBoolR _
            | SingletonStrR _
            | SingletonNumR _
            | PropExistsR _ ->
              ()
          in
          Base.List.iter ~f:writes_of_refinement refinements;
          writes

        (* In order to resolve a def containing a variable read, the writes that the
           Name_resolver determines reach the variable must be resolved *)
        method! identifier ((loc, _) as id) =
          let writes = this#find_writes ~for_type:false loc in
          Base.List.iter ~f:(this#add ~why:loc) writes;
          id

        method! type_identifier_reference ((loc, _) as id) =
          let writes = this#find_writes ~for_type:true loc in
          Base.List.iter ~f:(this#add ~why:loc) writes;
          id

        (* In order to resolve a def containing a variable read, the writes that the
           Name_resolver determines reach the variable must be resolved *)
        method! yield loc yield =
          let writes = this#find_writes ~for_type:false loc in
          Base.List.iter ~f:(this#add ~why:loc) writes;
          super#yield loc yield

        (* In order to resolve a def containing a variable write, the
           write itself should first be resolved *)
        method! pattern_identifier ?kind:_ ((loc, _) as id) =
          (* Ignore cases that don't have bindings in the environment, like `var x;`
             and illegal or unreachable writes. *)
          (match EnvMap.find_opt (Env_api.OrdinaryNameLoc, loc) env_entries with
          | Some Env_api.(AssigningWrite _ | GlobalWrite _ | EmptyArrayWrite _) ->
            this#add ~why:loc (Env_api.OrdinaryNameLoc, loc)
          | Some Env_api.NonAssigningWrite
          | None ->
            ());
          id

        method! binding_type_identifier ((loc, _) as id) =
          (* Unconditional, unlike the above, because all binding type identifiers should
             exist in the environment. *)
          this#add ~why:loc (Env_api.OrdinaryNameLoc, loc);
          id

        method! this_expression loc this_ =
          Base.Option.iter
            ~f:(fun this_loc -> this#add ~why:loc (Env_api.OrdinaryNameLoc, this_loc))
            this#this_;
          super#this_expression loc this_

        (* Skip names in function parameter types (e.g. declared functions) *)
        method! function_param_type (fpt : ('loc, 'loc) Ast.Type.Function.Param.t) =
          let open Ast.Type.Function.Param in
          let (_, { annot; _ }) = fpt in
          let _annot' = this#type_ annot in
          fpt

        method! member_property_identifier (id : (ALoc.t, ALoc.t) Ast.Identifier.t) = id

        method! typeof_member_identifier ident = ident

        method! member_type_identifier (id : (ALoc.t, ALoc.t) Ast.Identifier.t) = id

        method! pattern_object_property_identifier_key ?kind:_ id = id

        method! enum_member_identifier id = id

        method! object_key_identifier (id : (ALoc.t, ALoc.t) Ast.Identifier.t) = id

        (* For classes/functions that are known to be fully annotated, we skip property bodies *)
        method function_def ~fully_annotated (expr : ('loc, 'loc) Ast.Function.t) =
          let { Ast.Function.params; body; predicate; return; tparams; _ } = expr in
          let open Flow_ast_mapper in
          let _ = this#function_params params in
          let _ =
            if fully_annotated then
              (this#type_annotation_hint return, body)
            else
              (return, this#function_body_any body)
          in
          let _ = map_opt this#predicate predicate in
          let _ = map_opt this#type_params tparams in
          ()

        method! class_
            _
            ( { Ast.Class.id = ident; tparams; extends; implements; body; class_decorators; _ } as
            cls
            ) =
          let open Flow_ast_mapper in
          let new_this =
            match ident with
            | Some (loc, _) -> Some loc
            | None -> None
          in

          let this_' = this#this_ in
          this#set_this_ new_this;
          let _ = this#class_body body in
          this#set_this_ this_';

          let _ = map_opt this#class_identifier ident in
          let _ = map_opt this#type_params tparams in
          let _ = map_opt (map_loc this#class_extends) extends in
          let _ = map_opt this#class_implements implements in
          let _ = map_list this#class_decorator class_decorators in
          cls

        method class_body_annotated (cls_body : ('loc, 'loc) Ast.Class.Body.t) =
          let open Ast.Class.Body in
          let (_, { body; comments = _ }) = cls_body in
          Base.List.iter ~f:this#class_element_annotated body;
          cls_body

        method class_element_annotated (elem : ('loc, 'loc) Ast.Class.Body.element) =
          let open Ast.Class.Body in
          match elem with
          | Method (_, meth) -> this#class_method_annotated meth
          | Property (_, prop) -> this#class_property_annotated prop
          | PrivateField (_, field) -> this#class_private_field_annotated field

        method class_method_annotated (meth : ('loc, 'loc) Ast.Class.Method.t') =
          let open Ast.Class.Method in
          let { kind = _; key; value = (_, value); static = _; decorators; comments = _ } = meth in
          let _ = Base.List.map ~f:this#class_decorator decorators in
          let _ = this#object_key key in
          let _ = this#function_def ~fully_annotated:true value in
          ()

        method class_property_annotated (prop : ('loc, 'loc) Ast.Class.Property.t') =
          let open Ast.Class.Property in
          let { key; value = _; annot; static = _; variance = _; comments = _ } = prop in
          let _ = this#object_key key in
          let _ = this#type_annotation_hint annot in
          ()

        method class_private_field_annotated (prop : ('loc, 'loc) Ast.Class.PrivateField.t') =
          let open Ast.Class.PrivateField in
          let { key; value = _; annot; static = _; variance = _; comments = _ } = prop in
          let _ = this#private_name key in
          let _ = this#type_annotation_hint annot in
          ()
      end

    (* For all the possible defs, explore the def's structure with the class above
       to find what variables have to be resolved before this def itself can be resolved *)
    let depends cx ({ Env_api.providers; _ } as env) id_loc =
      let visitor = new use_visitor cx env EnvMap.empty in
      let depends_of_node mk_visit state =
        visitor#set_acc state;
        let node_visit () = mk_visit visitor in
        visitor#eval node_visit ()
      in
      let depends_of_tparams_map tparams_map =
        depends_of_node (fun visitor ->
            ALocMap.iter
              (fun loc _ -> visitor#add ~why:loc (Env_api.OrdinaryNameLoc, loc))
              tparams_map
        )
      in
      (* depends_of_annotation and of_expression take the `state` parameter from
         `depends_of_node` above as an additional currried parameter. *)
      let depends_of_annotation tparams_map anno state =
        state
        |> depends_of_tparams_map tparams_map
        |> depends_of_node (fun visitor -> ignore @@ visitor#type_annotation anno)
      in
      let depends_of_expression expr =
        depends_of_node (fun visitor -> ignore @@ visitor#expression expr)
      in
      let depends_of_fun fully_annotated tparams_map function_ =
        depends_of_node
          (fun visitor -> visitor#function_def ~fully_annotated function_)
          (depends_of_tparams_map tparams_map EnvMap.empty)
      in
      let depends_of_class
          fully_annotated
          {
            Ast.Class.id = ident;
            body;
            tparams;
            extends;
            implements;
            class_decorators;
            comments = _;
          } =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let this_' = visitor#this_ in
            begin
              match ident with
              | Some (loc, _) -> visitor#set_this_ (Some loc)
              | None -> ()
            end;
            let _ =
              if fully_annotated then
                visitor#class_body_annotated body
              else
                visitor#class_body body
            in
            visitor#set_this_ this_';
            let _ = map_opt (map_loc visitor#class_extends) extends in
            let _ = map_opt visitor#class_implements implements in
            let _ = map_list visitor#class_decorator class_decorators in
            let _ = map_opt visitor#type_params tparams in
            ())
          EnvMap.empty
      in
      let depends_of_declared_class
          {
            Ast.Statement.DeclareClass.id = _;
            tparams;
            body;
            extends;
            mixins;
            implements;
            comments = _;
          } =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let _ = map_opt visitor#type_params tparams in
            let _ = map_loc visitor#object_type body in
            let _ = map_opt (map_loc visitor#generic_type) extends in
            let _ = map_list (map_loc visitor#generic_type) mixins in
            let _ = map_opt visitor#class_implements implements in
            ())
          EnvMap.empty
      in
      let depends_of_alias { Ast.Statement.TypeAlias.tparams; right; _ } =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let _ = map_opt visitor#type_params tparams in
            let _ = visitor#type_ right in
            ())
          EnvMap.empty
      in
      let depends_of_opaque { Ast.Statement.OpaqueType.tparams; impltype; supertype; _ } =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let _ = map_opt visitor#type_params tparams in
            let _ = map_opt visitor#type_ impltype in
            let _ = map_opt visitor#type_ supertype in
            ())
          EnvMap.empty
      in
      let depends_of_tparam tparams_map (_, { Ast.Type.TypeParam.bound; variance; default; _ }) =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let _ = visitor#type_annotation_hint bound in
            let _ = visitor#variance_opt variance in
            let _ = map_opt visitor#type_ default in
            ())
          (depends_of_tparams_map tparams_map EnvMap.empty)
      in
      let depends_of_interface { Ast.Statement.Interface.tparams; extends; body; _ } =
        depends_of_node
          (fun visitor ->
            let open Flow_ast_mapper in
            let _ = map_opt visitor#type_params tparams in
            let _ = map_list (map_loc visitor#generic_type) extends in
            let _ = map_loc visitor#object_type body in
            ())
          EnvMap.empty
      in
      let depends_of_hint_node state = function
        | AnnotationHint (tparams_map, anno) -> depends_of_annotation tparams_map anno state
        | ValueHint exp_nodes ->
          Nel.fold_left (fun state e -> depends_of_expression e state) state exp_nodes
      in
      let depends_of_root state = function
        | Annotation { annot; tparams_map; _ } -> depends_of_annotation tparams_map annot state
        | Value exp -> depends_of_expression exp state
        | For (_, exp) -> depends_of_expression exp state
        | Contextual (_, hint) ->
          (match hint with
          | Hint_api.Hint_None -> state
          | Hint_api.Hint_Placeholder -> state
          | Hint_api.Hint_t hint_node
          | Hint_api.Hint_Decomp (_, hint_node) ->
            depends_of_hint_node state hint_node)
        | Catch -> state
      in
      let depends_of_selector state = function
        | Computed exp
        | Default exp ->
          depends_of_expression exp state
        | Elem _
        | Prop _
        | ObjRest _
        | ArrRest _ ->
          state
      in
      let depends_of_lhs id_loc lhs_member_expression =
        (* When looking at a binding def, like `x = y`, in order to resolve this def we need
             to have resolved the providers for `x`, as well as the type of `y`, in order to check
             the type of `y` against `x`. So in addition to exploring the RHS, we also add the providers
             for `x` to the set of dependencies. *)
        match lhs_member_expression with
        | None ->
          if not @@ Provider_api.is_provider providers id_loc then
            let { Provider_api.providers; _ } =
              Base.Option.value_exn (Provider_api.providers_of_def providers id_loc)
            in
            Base.List.fold
              ~init:EnvMap.empty
              ~f:(fun acc { Provider_api.reason = r; _ } ->
                let key = Reason.poly_loc_of_reason r in
                EnvMap.update
                  (Env_api.OrdinaryNameLoc, key)
                  (function
                    | None -> Some (Nel.one id_loc)
                    | Some locs -> Some (Nel.cons id_loc locs))
                  acc)
              providers
          else
            EnvMap.empty
        | Some e -> depends_of_expression e EnvMap.empty
      in
      let depends_of_binding bind =
        let state = depends_of_lhs id_loc None in
        let rec rhs_loop bind state =
          match bind with
          | Root root -> depends_of_root state root
          | Select (selector, binding) ->
            let state = depends_of_selector state selector in
            rhs_loop binding state
        in
        rhs_loop bind state
      in
      let depends_of_update lhs =
        let state = depends_of_lhs id_loc lhs in
        match lhs with
        | Some _ -> (* assigning to member *) state
        | None ->
          (* assigning to identifier *)
          let visitor = new use_visitor cx env state in
          let writes = visitor#find_writes ~for_type:false id_loc in
          Base.List.iter ~f:(visitor#add ~why:id_loc) writes;
          visitor#acc
      in
      let depends_of_op_assign lhs rhs =
        let lhs =
          match lhs with
          | (_, Ast.Pattern.Expression e) -> Some e
          | _ -> None
        in
        (* reusing depends_of_update, since the LHS of an op-assign is handled identically to an update *)
        let state = depends_of_update lhs in
        depends_of_expression rhs state
      in
      let depends_of_member_assign member_loc member rhs =
        let state =
          depends_of_node (fun visitor -> ignore @@ visitor#member member_loc member) EnvMap.empty
        in
        depends_of_expression rhs state
      in
      function
      | Binding binding -> depends_of_binding binding
      | RefiExpression exp
      | ChainExpression (_, exp) ->
        depends_of_expression exp EnvMap.empty
      | Update { lhs_member; _ } -> depends_of_update lhs_member
      | MemberAssign { member_loc; member; rhs; _ } ->
        depends_of_member_assign member_loc member rhs
      | OpAssign { lhs; rhs; _ } -> depends_of_op_assign lhs rhs
      | Function { synthesizable_from_annotation; function_; function_loc = _; tparams_map } ->
        depends_of_fun synthesizable_from_annotation tparams_map function_
      | Class { fully_annotated; class_; class_loc = _ } -> depends_of_class fully_annotated class_
      | DeclaredClass (_, decl) -> depends_of_declared_class decl
      | TypeAlias (_, alias) -> depends_of_alias alias
      | OpaqueType (_, alias) -> depends_of_opaque alias
      | TypeParam (tparams_map, tparam) -> depends_of_tparam tparams_map tparam
      | ThisTypeParam (tparams_map, _) -> depends_of_tparams_map tparams_map EnvMap.empty
      | Interface (_, inter) -> depends_of_interface inter
      | GeneratorNext (Some { return_annot; tparams_map; _ }) ->
        depends_of_annotation tparams_map return_annot EnvMap.empty
      | GeneratorNext None -> EnvMap.empty
      | Enum _ ->
        (* Enums don't contain any code or type references, they're literal-like *) EnvMap.empty
      | Import _ -> (* same with all imports *) EnvMap.empty

    (* Is the variable defined by this def able to be recursively depended on, e.g. created as a 0->1 tvar before being
       resolved? *)
    let recursively_resolvable =
      let rec bind_loop b =
        match b with
        | Root (Annotation _ | Catch) -> true
        | Root (For _ | Value _ | Contextual _) -> false
        | Select ((Computed _ | Default _), _) -> false
        | Select (_, b) -> bind_loop b
      in
      function
      | Binding bind -> bind_loop bind
      | GeneratorNext _
      | TypeAlias _
      | OpaqueType _
      | TypeParam _
      | ThisTypeParam _
      | Function { synthesizable_from_annotation = true; _ }
      | Interface _
      (* Imports are academic here since they can't be in a cycle anyways, since they depend on nothing *)
      | Import { import_kind = Ast.Statement.ImportDeclaration.(ImportType | ImportTypeof); _ }
      | Import
          {
            import =
              Named { kind = Some Ast.Statement.ImportDeclaration.(ImportType | ImportTypeof); _ };
            _;
          }
      | Class { fully_annotated = true; _ }
      | DeclaredClass _ ->
        true
      | RefiExpression _
      | ChainExpression _
      | Update _
      | MemberAssign _
      | OpAssign _
      | Function { synthesizable_from_annotation = false; _ }
      | Enum _
      | Import _
      | Class { fully_annotated = false; _ } ->
        false
  end

  let dependencies cx env (kind, loc) (def, _, _, _) acc =
    let depends = FindDependencies.depends cx env loc def in
    EnvMap.update
      (kind, loc)
      (function
        | None -> Some depends
        | Some _ ->
          failwith
            (Utils_js.spf
               "Duplicate name defs for the same location %s"
               (ALoc.debug_to_string ~include_source:true loc)
            ))
      acc

  let build_graph cx env map = EnvMap.fold (dependencies cx env) map EnvMap.empty

  let build_ordering cx env map =
    let graph = build_graph cx env map in
    let order_graph = EnvMap.map (fun deps -> EnvMap.keys deps |> EnvSet.of_list) graph in
    let roots = EnvMap.keys order_graph |> EnvSet.of_list in
    let sort =
      try Tarjan.topsort ~roots order_graph |> List.rev with
      | Not_found ->
        let all =
          EnvMap.values order_graph
          |> List.map EnvSet.elements
          |> List.flatten
          |> EnvSet.of_list
          |> EnvSet.elements
          |> Base.List.map ~f:(fun (_, l) -> ALoc.debug_to_string ~include_source:false l)
          |> String.concat ","
        in
        let roots =
          EnvSet.elements roots
          |> Base.List.map ~f:(fun (_, l) -> ALoc.debug_to_string ~include_source:true l)
          |> String.concat ","
        in
        failwith (Printf.sprintf "roots: %s\n\nall: %s" roots all)
    in
    let result_of_scc (fst, rest) =
      let element_of_loc (kind, loc) =
        let (def, _, _, reason) = EnvMap.find (kind, loc) map in
        if EnvSet.mem (kind, loc) (EnvMap.find (kind, loc) order_graph) then
          if FindDependencies.recursively_resolvable def then
            Resolvable (kind, loc)
          else
            let depends = EnvMap.find (kind, loc) graph in
            let recursion = EnvMap.find (kind, loc) depends in
            Illegal { loc = (kind, loc); reason; recursion }
        else
          Normal (kind, loc)
      in
      match rest with
      | [] -> Singleton (element_of_loc fst)
      | _ ->
        let component = (fst, rest) in
        if
          Base.List.for_all
            ~f:(fun m ->
              let (def, _, _, _) = EnvMap.find m map in
              FindDependencies.recursively_resolvable def)
            (fst :: rest)
        then
          ResolvableSCC (Nel.map element_of_loc component)
        else
          let elements =
            Nel.map
              (fun (kind, loc) ->
                let (_, _, _, reason) = EnvMap.find (kind, loc) map in
                let depends = EnvMap.find (kind, loc) graph in
                let edges =
                  EnvMap.fold
                    (fun k v acc ->
                      if
                        k != (kind, loc)
                        && Nel.mem
                             ~equal:(fun k1 k2 -> Env_api.EnvKey.compare k1 k2 = 0)
                             k
                             component
                      then
                        Nel.to_list v @ acc
                      else
                        acc)
                    depends
                    []
                  |> Nel.of_list_exn
                in
                (element_of_loc (kind, loc), reason, edges))
              component
          in
          IllegalSCC elements
    in
    Base.List.map ~f:result_of_scc sort
end

module DummyFlow (Context : C) = struct
  type cx = Context.t

  let add_output _ ?trace _ = ignore trace
end

module Make_Test_With_Cx (Context : C) = Make (Context) (DummyFlow (Context))
