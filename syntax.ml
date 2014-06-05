(** Abstract syntax of internal expressions. *)

(** Universes are indexed by natural numbers. *)
type universe = int

(** Abstract syntax of expressions, where de Bruijn indices are used to represent
    variables. *)
type expr = expr' * Common.position
and expr' =
  | Var of int                   (* de Briujn index *)
  | Free of Common.variable	 (* an open variable (variables are unique *)
  | Const of Common.name	 (* something from the signature *)
  | Subst of substitution * expr (* explicit substitution *)
  | Universe of universe
  | Pi of abstraction
  | Lambda of abstraction
  | App of expr * expr
  | Ann of expr * expr

(** An abstraction [(x,t,e)] indicates that [x] of type [t] is bound in [e]. We also keep around
    the original name [x] of the bound variable for pretty-printing purposes. *)
and abstraction = Common.variable * expr * expr

(** Explicit substitutions. *)
and substitution =
  | Shift of int
  | Dot of expr * substitution

(** Expression constructors wrapped in "nowhere" positions. *)
let mk_var k = Common.nowhere (Var k)
let mk_subst s e = Common.nowhere (Subst (s, e))
let mk_universe u = Common.nowhere (Universe u)
let mk_pi a = Common.nowhere (Pi a)
let mk_arrow s t = mk_pi (Common.none (), s, t)
let mk_lambda a = Common.nowhere (Lambda a)
let mk_app e1 e2 = Common.nowhere (App (e1, e2))
let mk_const c = Common.nowhere (Const c)

(** The identity substiution. *)
let idsubst = Shift 0

(** [shift k e] shifts the indices in [e] by [k] places. *)
let shift k e = mk_subst (Shift k) e

(** [compose s t] composes explicit subtitutions [s] and [t], i.e.,
    we have [subst (compose s t) e = subst s (subst t e)]. *)
let rec compose s t =
  match s, t with
    | s, Shift 0 -> s
    | Dot (e, s), Shift m -> compose s (Shift (m - 1))
    | Shift m, Shift n -> Shift (m + n)
    | s, Dot (e, t) -> Dot (mk_subst s e, compose s t)

(** [subst s e] applies explicit substitution [s] in expression [e]. It does so
    lazily, i.e., it does just enough to expose the outermost constructor of [e]. *)
let subst =
  let rec subst s ((e', loc) as e) =
    match s, e' with
      | Shift m, Var k -> Var (k + m), loc
      | Dot (a, s), Var 0 -> subst idsubst a
      | Dot (a, s), Var k -> subst s (Var (k - 1), loc)
      | s, Subst (t, e) -> subst s (subst t e)
      | _, Const x -> e
      | _, Universe _ -> e
      | s, Pi a -> Pi (subst_abstraction s a), loc
      | s, Lambda a -> Lambda (subst_abstraction s a), loc
      | s, App (e1, e2) -> App (mk_subst s e1, mk_subst s e2), loc
      | s, Ann (e1, e2) -> Ann (mk_subst s e1, mk_subst s e2), loc
      | s, Free n -> e		(* is this correct? *)
  and subst_abstraction s (x, e1, e2) =
    let e1 = mk_subst s e1 in
    let e2 = mk_subst (Dot (mk_var 0, compose (Shift 1) s)) e2 in
      (x, e1, e2)
  in
    subst

(** [occurs k e] returns [true] when variable [Var k] occurs freely in [e]. *)
let rec occurs k (e, _) =
  match e with
    | Var m -> m = k
    | Free _ -> false
    | Const x -> false
    | Subst (s, e) -> occurs k (subst s e)
    | Universe _ -> false
    | Pi a -> occurs_abstraction k a
    | Lambda a -> occurs_abstraction k a
    | App (e1, e2) -> occurs k e1 || occurs k e2
    | Ann (e1, e2) -> occurs k e1 || occurs k e2

and occurs_abstraction k (_, e1, e2) =
  occurs k e1 || occurs (k + 1) e2

(** Replaces references to index k with free variable v *)
let rec db_to_var (k : int) (v : Common.variable) (e :expr) : expr =
  let f = db_to_var in
  let rec fsub n = function
    | Shift n -> Shift (n-1)
    | Dot (e, s) -> Dot (f n v e, fsub n s)
  in
  match e with
    | Var x, l when x = k -> Free v, l
    | Var x, l when x > k-> Var (x - 1), l
    | Var x, l -> Var x, l
    | Free v', l -> Free v', l
    | Const c, l -> Const c, l
    | Subst (s, e), l -> Subst (fsub k s, f k v e), l
    | Universe n, l -> Universe n, l
    | Pi (vv, e1, e2), l -> Pi(vv, f k v e1, f (k+1) v e2), l
    | Lambda (vv, e1, e2), l -> Lambda(vv, f k v e1, f (k+1) v e2), l
    | App (e1, e2), l -> App(f k v e1, f k v e2), l
    | Ann (e1, e2), l -> Ann(f k v e1, f k v e2), l

let rec top_db_to_var (v : Common.variable) (e :expr) : expr = 
  db_to_var 0 v e
(** Replaces instances of variable v as index 0.
    It is up-to the user, to abstract over v *)
let var_to_db (v : Common.variable) (e : expr) : expr =
  let rec fsub n = function 	(* TODO : fix *)
    | Shift n -> Shift n
    | Dot (e, s) -> Dot (f n e, fsub n s)
  and f n = function
    | Var k, l when k >= n -> Error.violation "This should not happen! (n must be, at least, one larger. Was e closed?)"
    | Var x, l -> Var x, l
    | Free v', l when Common.eq v v' -> Var n, l
    | Free v', l -> Free v', l
    | Const c, l -> Const c, l
    | Subst (s, e), l -> Printf.printf "PROBABLY WRONG IMPLEMENTATION" ; Subst (fsub n s, f n e), l
    | Universe n, l -> Universe n, l
    | Pi (v, e1, e2), l -> Pi(v, f n e1, f (n+1) e2), l
    | Lambda (v, e1, e2), l -> Lambda(v, f n e1, f (n+1) e2), l
    | App (e1, e2), l -> App(f n e1, f n e2), l
    | Ann (e1, e2), l -> Ann(f n e1, f n e2), l
  in
  f 0 e

let var (v : Common.variable) : expr = Common.nowhere (Free v)
 

(** A telescope returns all the binders (pi abstractions) at the beginning of a type.
    It returns a function that given a expression, returns a value  *)
type telescope = (Common.variable * expr) list

let rec get_telescope : expr -> telescope * expr = function
  | Pi (x, t, e),loc -> 
     let tel, rest = get_telescope (top_db_to_var x e) in
     (x, t)::tel, rest
  | Lambda _,_ -> Error.violation "Lambda found in a telescope, add?"
  | rest -> [], rest

let rec set_telescope (t : telescope) (e : expr) (f : Common.variable -> expr -> expr -> expr ) : expr =
  List.fold_left (fun e (x, t) -> f x t (var_to_db x e)) e t

(* Note: split and join head spine destroy location information, it'd
   be better to have a native spine based representation (TODO) *)

let rec split_head_spine (e, l) = match e with
  | App(e1, e2) -> let h, sp = split_head_spine e1 in h, (e2 :: sp)
  | _ -> (e, l), []

let join_head_spine h sp =
  List.fold_left (fun h sp -> Common.nowhere(App(h, sp))) h sp

(* Returns wether e constains the constant d in its head *)
let is_constr d e = 
    let h, _ = split_head_spine e in
    match h with
    | Const c, l -> d = c
    | _ -> false

