(* Signature *)

type declaration = 
  | Axiom of Syntax.expr
  | Constr of Syntax.expr
  | Definition of Syntax.expr * Syntax.expr

type signature

val empty_signature : signature

val lookup_ty : Common.name -> signature -> Syntax.expr

val lookup_definition :
  Common.name -> signature -> Syntax.expr option

val add_axiom : Common.name -> Syntax.expr -> signature -> signature
val add_constr : Common.name -> Syntax.expr -> signature -> signature

val add_definition :
  Common.name -> Syntax.expr -> Syntax.expr -> signature -> signature

val mem : string -> signature -> bool

val combine : signature -> (string * declaration) list

val sig_fold : ('a -> Common.name * declaration -> 'a) -> 'a -> signature -> 'a

(* Context *)

type 'a ctx
val empty_context : 'a ctx
val extend : 'a ctx -> 'a -> 'a ctx
val lookup_idx : loc:Common.position -> int -> 'a ctx -> 'a
val ctx_fold : ('a -> 'b -> 'a) -> 'a -> 'b ctx -> 'a
type cctx = (Common.variable * Syntax.expr) ctx
val index : loc:Common.position -> Common.name -> cctx -> int
val lookup_idx_ty : loc:Common.position -> int -> cctx -> Syntax.expr
val lookup_idx_name : loc:Common.position -> int -> cctx -> Common.variable

(* Both *)

val names : signature * cctx -> string list