(** Normalization of expressions. *)

open Syntax
open Ctx

(** [norm env e] evaluates expression [e] in environment [env] to a weak head normal form,
    while [norm weak:false env e] evaluates to normal form. *)
let norm ?(weak=false) =
  let rec norm (sigma, gamma as ctx) ((e', loc) as e) =
    match e' with
      | Var k -> e
      | Const x ->
        (match lookup_definition x sigma with
          | None -> e
          | Some e -> norm ctx e)
      | Universe _ -> e
      | Pi a -> 
        Pi (norm_abstraction ctx a), loc
      | Lambda a -> Lambda (norm_abstraction ctx a), loc
      | Subst (s, e) -> norm ctx (subst s e)
      | Ann (e1, e2) -> 
	 Ann (norm ctx e1, norm ctx e2), loc
      | App (e1, e2) ->
        let (e1', _) as e1 = norm ctx e1 in
          (match e1' with
            | Lambda (x, t, e) -> norm ctx (mk_subst (Dot (e2, idsubst)) e)
            | Var _ | Const _ | App _ -> 
              let e2 = (if weak then e2 else norm ctx e2) in 
                App (e1, e2), loc
	    | Ann (e1, t) -> norm ctx (App (e1, e2), loc) (* This removes the annotation, is this correct? *)
            | Subst _ | Universe _ | Pi _ -> Error.runtime ~loc:(snd e2) "Function expected")
  and norm_abstraction (sigma, gamma as ctx) ((x, t, e) as a) =
    if weak
    then a
    else (x, norm ctx t, norm (sigma, extend gamma (x, t)) e)
  in
    norm

(** [nf ctx e] computes the normal form of expression [e]. *)
let nf ctx e = norm ~weak:false ctx e

(** [whnf ctx e] computes the weak head normal form of expression [e]. *)
let whnf ctx e = norm ~weak:true ctx e

