(** Toplevel. *)

open Ctx

(** Should the interactive shell be run? *)
let interactive_shell = ref true

(** The command-line wrappers that we look for. *)
let wrapper = ref (Some ["rlwrap"; "ledit"])

(** The usage message. *)
let usage = "Usage: total [option] ... [file] ..."

(** The help text printed when [Help.] is used. *)
let help_text = "Toplevel commands:
Axiom <ident> : <expr>.                 assume variable <ident> has type <expr>
Definition <indent> := <expr>.          define <ident> to be <expr>
Definition <indent> : <expr> := <expr>. define <ident> of type <expr> to be <expr>
Check <expr>                            infer the type of expression <expr>
Eval <expr>.                            normalize expression <expr>
Context.                                print current contex    
Help.                                   print this help
Quit.                                   exit

Syntax:
Type k                                  the k-th universe, e.g. Type 42
fun x : e1 => e2                        function abstraction
forall x : e1, e2                       dependent product
e1 e2                                   application
e1 : e2                                 type annotation
" ;;

(** A list of files to be loaded and run. *)
let files = ref []

(** Add a file to the list of files to be loaded, and record whether it should
    be processed in interactive mode. *)
let add_file interactive filename = (files := (filename, interactive) :: !files)

(** A list of command-line wrappers to look for. *)
let wrapper = ref (Some ["rlwrap"; "ledit"])

(** Command-line options *)
let options = Arg.align [
  ("--wrapper",
    Arg.String (fun str -> wrapper := Some [str]),
    "<program> Specify a command-line wrapper to be used (such as rlwrap or ledit)");
  ("--no-wrapper",
    Arg.Unit (fun () -> wrapper := None),
    " Do not use a command-line wrapper");
  ("-v",
    Arg.Unit (fun () ->
      print_endline ("total " ^ Version.version ^ "(" ^ Sys.os_type ^ ")");
      exit 0),
    " Print version information and exit");
  ("-V",
   Arg.Int (fun k -> Print.verbosity := k),
   "<int> Set verbosity level");
  ("-n",
    Arg.Clear interactive_shell,
    " Do not run the interactive toplevel");
  ("-l",
    Arg.String (fun str -> add_file false str),
    "<file> Load <file> into the initial environment");
  ("--db",
   Arg.Set Config.pretty_print_db,
  " Use De Bruinj indices when pretty printing");
  ("--nm",
   Arg.Clear Config.pretty_print_db,
  " Use names when pretty printing (default)");
  ("--arron",
   Arg.Set Config.pretty_print_arrow,
  " Use -> for non-dependent function types when pretty printing (default)");
  ("--arroff",
   Arg.Clear Config.pretty_print_arrow,
  " Use forall for non-dependent function types when pretty printing");
  ("--debug", 
   Arg.Unit (fun _ -> Print.verbosity := Print.debug_verbosity),
   " Print additional debug info (potential very verbose)");
]

(** Treat anonymous arguments as files to be run. *)
let anonymous str =
  add_file true str;
  interactive_shell := false

(** Parser wrapper that reads extra lines on demand. *)
let parse parser lex =
  try
    parser Lexer.token lex
  with
  | Parser.Error ->
      Error.syntax ~loc:(Lexer.position_of_lex lex) ""
  | Failure "lexing: empty token" ->
      Error.syntax ~loc:(Lexer.position_of_lex lex) "unrecognised symbol."

(** [exec_cmd sigma d] executes toplevel directive [d] in context [sigma]. It prints the
    result if in interactive mode, and returns the new context. *)
let rec exec_cmd interactive sigma (d, loc) =
  let ctx_from sigma = (sigma, Ctx.empty_context) in
  let ctx = ctx_from sigma in
  match d with
    | Input.Eval e ->
      let e = Desugar.desugar sigma e in
      let t = Norm.nf ctx (Typing.infer ctx e) in
      let e = Norm.nf ctx e in
      if interactive then
         Format.printf "    = %t@\n    : %t@."
		       (Print.expr ctx e)
		       (Print.expr ctx (Norm.nf ctx t)) ;
        sigma
    | Input.Context ->
      List.iter
        (function
          | (x, Axiom t) ->
            Format.printf "@[%s : %t@]@." x (Print.expr (ctx_from sigma) t)
          | (x, Constr (t, n)) ->
            Format.printf "@[(%d)%s : %t@]@." n x (Print.expr (ctx_from sigma) t)
          | (x, Elim el) ->
            Format.printf "@[%s : %t@]@." x (Print.expr (ctx_from sigma) el.t)
          | (x, Definition (t, e)) ->
            Format.printf "@[%s = %t@]@\n    : %t@." x (Print.expr (ctx_from sigma) e) (Print.expr (ctx_from sigma) t))
	(combine sigma);
      sigma
    | Input.Axiom (x, t) ->
      let t = Desugar.desugar sigma t in
      let _ =  Typing.infer_universe (ctx_from sigma) t in
        if interactive then
          Format.printf "%s is assumed.@." x ;
        add_axiom x t sigma
    | Input.Definition (x, ann,  e) ->
       let ctx = ctx_from sigma in
       if Ctx.mem x sigma then Error.typing ~loc "%s already exists" x ;
       let e = Desugar.desugar sigma e in
       let t = Typing.infer ctx e in
       (match ann with
	| None -> ()
	| Some t' when Typing.equal (ctx_from sigma) (Desugar.desugar sigma t') t -> ()
	| Some t' -> Error.typing ~loc "%s has type@ %t@ but@ %t@ was expected"
				 x (Print.expr ctx t) (Print.expr ctx (Desugar.desugar sigma t'))) ;
       if interactive then
         Format.printf "%s is defined.@." x ;
       add_definition x (Norm.nf ctx t) e sigma
    | Input.Check e ->
      let e = Desugar.desugar sigma e in
      let t = Typing.infer (ctx_from sigma) e in
        Format.printf "%t@\n    : %t@." (Print.expr (ctx_from sigma) e) (Print.expr (ctx_from sigma) t) ;
        sigma
    | Input.Inductive (x, t, cs) ->
       if Ctx.mem x sigma then Error.typing ~loc "%s aleardy exists" x ;
       let t = Desugar.desugar sigma t in
       let sigma = Inductive.elab_type_constr sigma x t in
       let cs = List.fold_left
       		  (fun cs' (c, t) ->
       		   if c == x then Error.typing ~loc "constructor %s clashes with type name" c ;
       		   if List.mem_assoc c cs' then Error.typing ~loc "%s aleardy exists" c ;
       		   if Ctx.mem c sigma then Error.typing ~loc "%s aleardy exists" c ;
       		   (c, Desugar.desugar sigma t)::cs')
       		  [] cs
       in
       let sigma = Inductive.validate_constrs sigma x t cs in
       let sigma = Inductive.elim sigma x t cs in
       if interactive then
       	 Format.printf "%s is defined@." x ;
       sigma
    | Input.Help ->
      print_endline help_text ; sigma
    | Input.Quit -> exit 0

(** Load directives from the given file. *)
and use_file sigma (filename, interactive) =
  let cmds = Lexer.read_file (parse Parser.directives) filename in
    List.fold_left (exec_cmd interactive) sigma cmds

(** Interactive toplevel *)
let toplevel sigma =
  let eof = match Sys.os_type with
    | "Unix" | "Cygwin" -> "Ctrl-D"
    | "Win32" -> "Ctrl-Z"
    | _ -> "EOF"
  in
  print_endline Version.logo;
  print_endline ("Version: " ^ Version.version);
  print_endline ("[Type " ^ eof ^ " to exit or \"Help.\" for help.]");
  try
    let sigma = ref sigma in
    while true do
      try
        let cmds = Lexer.read_toplevel (parse Parser.directives) () in
        sigma := List.fold_left (exec_cmd true) !sigma cmds
      with
        | Error.Error err -> Print.error err
        | Sys.Break -> prerr_endline "Interrupted."
    done
  with End_of_file -> ()

(** Main program *)
let main =
  Sys.catch_break true;
  (* Parse the arguments. *)
  Arg.parse options anonymous usage;
  (* Attempt to wrap yourself with a line-editing wrapper. *)
  if !interactive_shell then
    begin match !wrapper with
      | None -> ()
      | Some lst ->
          let n = Array.length Sys.argv + 2 in
          let args = Array.make n "" in
            Array.blit Sys.argv 0 args 1 (n - 2);
            args.(n - 1) <- "--no-wrapper";
            List.iter
              (fun wrapper ->
                 try
                   args.(0) <- wrapper;
                   Unix.execvp wrapper args
                 with Unix.Unix_error _ -> ())
              lst
    end;
  (* Files were listed in the wrong order, so we reverse them *)
  files := List.rev !files;
  (* Set the maximum depth of pretty-printing, after which it prints ellipsis. *)
  Format.set_max_boxes 42 ;
  Format.set_ellipsis_text "..." ;
  try
    (* Run and load all the specified files. *)
    let sigma = List.fold_left use_file empty_signature !files in
    if !interactive_shell then toplevel sigma
  with
    Error.Error err -> Print.error err; exit 1
