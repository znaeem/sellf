type 'a option = NONE | SOME of 'a

(* Each logical variable is identified by this number. 
 * A new logical variable should increment one in this identifier. *)
let varid = ref 0 ;;

(*Type for the types of terms. The user can define a kind, which is a basic 
type, or use the pre-defined types such as for integers, lists and predicates, 
composing them using the ->.*)
type types =
| TBASIC of basicTypes
| ARR of types * types (* type node *)
and basicTypes =
| TKIND of string (* Kind names *)
| TINT            (* Int type *)
| TSTRING
| TPRED           (* Predicate type "o" *)
| TSUBEX
| TLIST of basicTypes

(* Polarity of atoms *)
type polarity = 
| POS
| NEG
;;

(*Propositions are atoms, equalities, and logical connectives.*)
type terms = 
| PRED of string * terms * polarity (* G: name of the predicate (string) and head (terms) *)
| EQU of string * int * terms (* G: equality *)
| TOP
| ONE
| BOT
| ZERO
| NOT of terms
| COMP of compType * terms * terms
| ASGN of terms * terms
| PRINT of terms
| CUT
| TENSOR of terms * terms
| ADDOR of terms * terms
| PARR of terms * terms
| LOLLI of terms * terms * terms
| BANG of terms * terms
| HBANG of terms * terms
| QST of terms * terms
| WITH of terms * terms
| FORALL of string * int * terms
| EXISTS of string * int * terms
| CLS of clType * terms * terms
| VAR of var
| DB of int        (*This seems necessary for head normalization procedure.*)
| INT of int
| CONS of string
| STRING of string
(*| LIST of lists*)
| APP of terms * terms list
| ABS of string * int * terms
| PLUS  of terms * terms
| MINUS of terms * terms
| TIMES of terms * terms 
| DIV of terms * terms
| SUSP of terms * int * int * env
| PTR  of ptr
| NEW of string * terms
| BRACKET of terms
and ptr = in_ptr ref
and in_ptr = V of var | T of terms
and env = envitem list
and envitem = Dum of int | Binding of terms * int
and compType =
| EQ | LESS | GEQ | GRT | LEQ | NEQ
and clType =
| DEF | LOL
and
tag =  (*VN: Tag for variables: either an eigenvariable or a logical variable.
The logical variable points to a term. This is used to instantiate the variable
when performing unification.*)
EIG | CONST  | LOG
and 
var = {
  str : string;
  id  : int ; (* Only used for hashing *)
  tag : tag ;
  ts  : int ; (* Always zero for constants in Bedwyr *)
  lts : int
}

(* Four types of subexponentials described by a string *)
type subexp = 
| UNB (* unbounded: contraction and weakening *)
| AFF (* affine: weakening *)
| REL (* relevant: contraction *)
| LIN (* linear *)

let fVarC x = match x with
| "$test" -> 10
| _ -> 0;;

let varName x y = "$"^x^(string_of_int y);;

(* Functions to get the elements of an implication *)
(* TODO: check if this is used. *)
let rec getHead t = match t with
  | LOLLI(s, t1, t2) -> t1
  | ABS(s, i, t1) -> getHead t1
  | _ -> failwith "Impossible to get head. Formula is not -o."

let rec getBody t = match t with
  | LOLLI(s, t1, t2) -> t2
  | ABS(s, i, t1) -> getBody t1
  | _ -> failwith "Impossible to get body. Formula is not -o."

let rec tCheckAuxList term = TINT

(* Syntatic equality XXX: not working, do not use. *)
let rec equals t1 t2 = match (t1, t2) with
  | (VAR{str=s1; id=i1; tag=t1}, VAR{str=s2; id=i2; tag=t2}) 
    when s1 = s2 && i1 = i2 && t1 = t2 -> true
  | (PRED(str1, t1, _), PRED(str2, t2, _)) -> 
    if str1 = str2 then equals t1 t2
    else false
  | (NOT(t1), NOT(t2)) -> equals t1 t2
  | (TENSOR(t11, t12), TENSOR(t21, t22)) -> equals t11 t12 && equals t21 t22
  | (ADDOR(t11, t12), ADDOR(t21, t22)) -> equals t11 t12 && equals t21 t22
  | (PARR(t11, t12), PARR(t21, t22)) -> equals t11 t12 && equals t21 t22
  | (WITH(t11, t12), WITH(t21, t22)) -> equals t11 t12 && equals t21 t22
  | (BANG(s1, t1), BANG(s2, t2)) -> equals s1 s2 && equals t1 t2
  | (HBANG(s1, t1), HBANG(s2, t2)) -> equals s1 s2 && equals t1 t2
  | (QST(s1, t1), QST(s2, t2)) -> equals s1 s2 && equals t1 t2
  | (LOLLI(s1, t11, t12), LOLLI(s2, t21, t22)) -> 
    equals s1 s2 && equals t11 t12 && equals t21 t22
  (* TODO forall exists*)
  | (INT(i1), INT(i2)) -> i1 = i2
  | (CONS(s1), CONS(s2)) -> s1 = s2
  | (STRING(s1), STRING(s2)) -> s1 = s2
  | (_, _) -> false
(* G: Not sure if I need a case for these... *)
(*
| APP of terms * terms list
| ABS of string * int * terms
| PLUS  of terms * terms
| MINUS of terms * terms
| TIMES of terms * terms 
| DIV of terms * terms
| SUSP of terms * int * int * env
| PTR  of ptr
| NEW of string * terms
| BRACKET of terms
*)

(****************** Signature ***********************)
(*
 * Hashtables and functions to store the kinds and types declared in the .sig
 * file and the rules.
 *)

(* Hashtable with the kind *)
let kTbl = Hashtbl.create 100 ;;
(* Hashtable with the types*)
let tTbl = Hashtbl.create 100 ;;
(* Hashtable with the rules*)
(* TODO: check if this is being used. *)
let rTbl = Hashtbl.create 100 ;;

(* Need to add "o" as a pre-defined kind *)
Hashtbl.add kTbl "o" (TPRED);;
(* Example of a type *)
Hashtbl.add tTbl "$example" (ARR ( TBASIC (TINT), TBASIC (TINT) ));;
(* Example of a rule: $example :- 1.   *)
Hashtbl.add rTbl "$example" (CLS (DEF, PRED ("$example", CONS ("$example"), NEG), ONE ) );;

let addTTbl hash name entry = Hashtbl.add hash name entry ;; 

let notInTbl hash entry = 
	let l = (Hashtbl.find_all hash entry) in
	   if List.length l == 0 then NONE           (* kind not in table*)
       else SOME (entry)       		             (* kind in table *)

let addKTbl hash entry = 
	match entry with
	| TINT -> NONE
	| TPRED -> NONE
	| TKIND (k) -> (match (notInTbl hash k) with
		        | NONE -> Hashtbl.add hash k (TKIND (k)); NONE
			| SOME (k1) -> SOME (k1))
	| _ -> NONE
;;

(******************************************************)

(*Function that takes a term and returns a pair with the head of the term and the list of arguments.*)
let rec term2list term = 
let rec num_arg t = match t with
  | APP (t1, t2) -> 1 + (num_arg t1)
  | _ -> 0
in
let rec term2listaux term n =
  if n > 0 then 
  begin
    match term with
    | APP(t1, t2) -> let (head, args) = (term2listaux t1 (n-1)) in 
         (head, List.append  args [t2] )  
    | _ -> failwith "ERROR: Expected an application when transforming a term into a list of terms."
  end
  else (term, [])
in
let n = num_arg term in 
term2listaux term n

(*Function that receives a head and a list of arguments and transforms it to a term.*)
let rec list2term head args = 
  match args with
  | [] ->  head
  | term1 :: body -> list2term (APP(head, term1)) body

(* Extracts the string from a CONS *)
let extract_str c = match c with
  | CONS(str) -> str
  | _ -> failwith "Trying to extract the string for the worng term or this case is not implemented."

let rec eq t1 t2 =
  match t1,t2 with
    (* Compare leafs *)
    | DB i1, DB i2 -> i1 = i2
   (* | NB i1, NB i2 -> i1=i2*)
    | PTR {contents=V v1}, PTR {contents=V v2} -> v1==v2
    (* Ignore Ptr. It's an implementation artifact *)
    | _, PTR {contents=T t2} -> eq t1 t2
    | PTR {contents=T t1}, _ -> eq t1 t2
    (* Propagation *)
    | APP (h1,l1), APP (h2,l2) ->
        List.length l1 = List.length l2 &&
        List.fold_left2
          (fun test t1 t2 -> test && eq t1 t2)
          true (h1::l1) (h2::l2)
    | ABS (_,n,t1), ABS (_,m,t2) -> n = m && eq t1 t2
    | VAR _, _ | _, VAR _ -> assert false
    | SUSP (t,ol,nl,e), SUSP (tt,oll,nll,ee) ->
        ol = oll && nl = nll && eq t tt &&
          List.fold_left2
            (fun test e1 e2 ->
               test && match e1,e2 with
                 | Dum i, Dum j when i = j -> true
                 | Binding (t,i), Binding (tt,j) when i=j && eq t tt -> true
                 | _ -> false)
            true e ee
    | _ -> false


let rec observe = function
  | PTR {contents=T d} -> observe d
  | PTR {contents=V v} -> VAR v
  | t -> t

let rec deref = function
  | PTR {contents=T t} -> deref t
  | t -> t

let lambda n t =
  assert (n>=0) ;
  if n=0 then t else
    let rec aux n t =
      match t with
        | ABS (_,n',t') -> aux (n+n') t'
        | _ -> ABS ("*",n,t)
    in
      aux n t


let susp t ol nl e = SUSP (t,ol,nl,e)

(*let rec app a b = list2term a b*)

let app a b = if b = [] then a else match observe a with
  | APP(a,c) -> APP (a,c @ b)
  | _ -> APP (a,b)

let db n = DB n

let rec remove_abs clause = 
  match clause with
    | ABS (str, i, t) -> remove_abs t
    | _ -> clause

(*Function that assigns de Bruijn numbers to variables.*)
let rec deBruijn_aux flag fVarC nABS body =   
  match body with
  | VAR v  ->
    begin
      match (fVarC v.str) with
        | (id, _, 0) -> (*VN: Case when the variable is bounded by a FORALL*)
             let (idNew, _, _ ) = fVarC v.str in
             let v2 = {str = v.str; id = idNew; tag = v.tag; ts = v.ts; lts = v.lts} in VAR v2
        | (id, nABS1, 1) -> (*VN: Case when the variable is bounded by an abstraction*) 
           if flag then DB(id + nABS1) 
           else let (idNew, _, _ ) = fVarC v.str in
             let v2 = {str = v.str; id = idNew; tag = v.tag; ts = v.ts; lts = v.lts} in VAR v2
        | _ -> failwith "Impossible case reached in the De Bruijn Auxiliary."
    end
   (*| LIST (lists) -> LIST (deBruijnList lists fVarC)*)
  | APP (term1, term2) -> 
     APP (deBruijn_aux flag fVarC nABS term1, List.map (deBruijn_aux flag fVarC nABS) term2)
  | ABS (str, i, body1) -> 
     let fVarCNew x = 
     begin match x with
       | x when x = str ->  (1, 0, 1)
       | x -> let (id, nABS_rest, tABS) = fVarC x in (id, nABS_rest + 1, tABS)
     end
     in ABS (str, 1, deBruijn_aux flag fVarCNew (nABS + 1) body1)
  | PLUS (int1, int2) -> PLUS (deBruijn_aux flag fVarC nABS int1, deBruijn_aux flag fVarC nABS int2)
  | MINUS (int1, int2) -> MINUS (deBruijn_aux flag fVarC nABS int1, deBruijn_aux flag fVarC nABS int2)
  | TIMES (int1, int2) -> TIMES (deBruijn_aux flag fVarC nABS int1, deBruijn_aux flag fVarC nABS int2) 
  | DIV (int1, int2) -> DIV (deBruijn_aux flag fVarC nABS int1, deBruijn_aux flag fVarC nABS int2)
  | TENSOR (body1, body2) -> TENSOR (deBruijn_aux flag fVarC nABS body1, deBruijn_aux flag fVarC nABS body2)
  | ADDOR (body1, body2) -> ADDOR (deBruijn_aux flag fVarC nABS body1, deBruijn_aux flag fVarC nABS body2)
  | LOLLI (sub, body1, body2) -> LOLLI (deBruijn_aux flag fVarC nABS sub, deBruijn_aux flag fVarC nABS body1, deBruijn_aux flag fVarC nABS body2)
  | BANG (sub, body1) -> BANG (deBruijn_aux flag fVarC nABS sub, deBruijn_aux flag fVarC nABS body1) 
  | HBANG (sub, body1) -> HBANG (deBruijn_aux flag fVarC nABS sub, deBruijn_aux flag fVarC nABS body1) 
  | WITH (body1, body2) -> WITH (deBruijn_aux flag fVarC nABS body1, deBruijn_aux flag fVarC nABS body2)
  | BRACKET (body1) -> BRACKET (deBruijn_aux flag fVarC nABS body1)
  | FORALL (str, _, body1) -> 
     let fVarCNew x = 
     begin match x with
       | x when x = str ->  (1, 0, 1)
       | x -> let (id, nABS_rest, tABS) = fVarC x in (id, nABS_rest + 1, tABS)
     end
     (*let (idOld, nABS, tABS) =  fVarC str in
  			let fVarCNew x = (match x with
       | x when x = str ->  (idOld + 1, nABS, 0)
       | x -> fVarC x)*)
  			(*in FORALL(str, idOld, deBruijn_aux flag fVarCNew nABS body1)*)
     in FORALL (str, 1, deBruijn_aux flag fVarCNew (nABS + 1) body1)
  | NEW (str, body1) -> 
     let fVarCNew x = 
     begin match x with
       | x when x = str ->  (1, 0, 1)
       | x -> let (id, nABS_rest, tABS) = fVarC x in (id, nABS_rest + 1, tABS)
     end
     (*let (idOld, nABS, tABS) =  fVarC str in
        let fVarCNew x = (match x with
       | x when x = str ->  (idOld + 1, nABS, 0)
       | x -> fVarC x)*)
        (*in FORALL(str, idOld, deBruijn_aux flag fVarCNew nABS body1)*)
     in NEW (str, deBruijn_aux flag fVarCNew (nABS + 1) body1)
  | PRED (srt, terms, p) ->  PRED (srt, deBruijn_aux flag fVarC nABS terms, p)
  | EQU (str, _, terms) -> 
     let (id, nABS, tABS) =  fVarC str in 
     EQU (str, id, deBruijn_aux flag fVarC nABS terms)
  | CLS(tp, t1, t2) -> CLS(tp, deBruijn_aux flag fVarC nABS t1, deBruijn_aux flag fVarC nABS t2)
  | COMP(comp, t1, t2) -> COMP(comp, deBruijn_aux flag fVarC nABS t1, deBruijn_aux flag fVarC nABS t2)
  | ASGN(t1, t2) -> ASGN(deBruijn_aux flag fVarC nABS t1, deBruijn_aux flag fVarC nABS t2)
  | PRINT(t1) -> PRINT(deBruijn_aux flag fVarC nABS t1)
  | x -> x

let rec collect_free_variables clause =
  let rec collect_free_variables_list freeVar bVar lst = 
    begin
      match lst with
      | [] -> failwith "[ERROR] Collecting free variables from an empty list. (term.ml collect_free_variables)"
      | [t] -> collect_free_variables_aux freeVar bVar t
      | t :: body ->  
          let freeVar1 = collect_free_variables_aux freeVar bVar t in 
          collect_free_variables_list freeVar1 bVar body
    end
  and
  collect_free_variables_aux freeVar bVar clause = 
    begin
      match observe clause with
        | VAR v  when List.mem v.str freeVar || List.mem v.str bVar-> freeVar
        | VAR v  -> v.str :: freeVar
        | PRED(_, t1, _) -> collect_free_variables_aux freeVar bVar t1
        | TOP | ONE | BOT | ZERO | CUT | DB _ | INT _ | CONS _ | STRING _ | SUSP _ -> freeVar
        | EQU(_, _, t1) | PRINT(t1) -> collect_free_variables_aux freeVar bVar t1
        | FORALL(str, _, t1) | EXISTS(str, _, t1) 
        | ABS(str, _, t1) | NEW (str, t1) -> collect_free_variables_aux freeVar (str :: bVar) t1
        | APP(t1, t2) -> let freeVar1 = collect_free_variables_aux freeVar bVar t1 in
                                collect_free_variables_list freeVar1 bVar t2 
        | DIV (t1, t2)  | TIMES (t1, t2) | MINUS (t1, t2) | PLUS (t1, t2) 
        | TENSOR(t1, t2) | ADDOR(t1, t2) | COMP(_, t1, t2) | ASGN (t1,t2) 
        | WITH(t1,t2) | CLS(_, t1, t2) | BANG(t1, t2) | HBANG(t1, t2) 
        | PARR(t1, t2) | QST(t1, t2) -> 
          let freeVar1 = collect_free_variables_aux freeVar bVar t1 in 
          let freeVar2 = collect_free_variables_aux freeVar1 bVar t2 in 
          freeVar2
        | LOLLI (subex, t1, t2)  -> 
          let freeVar1 = collect_free_variables_aux freeVar bVar subex in 
          let freeVar2 = collect_free_variables_aux freeVar1 bVar t1 in
          let freeVar3 = collect_free_variables_aux freeVar2 bVar t2 in
            freeVar3
        | BRACKET (t) -> collect_free_variables_aux freeVar bVar t
        | NOT (t) -> collect_free_variables_aux freeVar bVar t
        | _ -> failwith "Not expected term in 'collect_free_variables_aux', term.ml"
    end
  in 
  collect_free_variables_aux [] [] clause


module Hint = struct
  module M = Map.Make(struct type t = int let compare = compare end)
  let var_names = ref M.empty
  let add var name =
    var_names := M.add var.id name !var_names ;
    Gc.finalise (fun v -> var_names := M.remove v.id !var_names) var
  let find var =
    M.find var.id !var_names
end

let fresh_id =
  let c = ref 0 in
    fun () -> incr c ; !c

(** Generate a fresh variable, attach a naming hint to it. *)
let fresh ?name ~lts ~ts tag =
  let v = {str="_";id=fresh_id();tag=tag;ts=ts;lts=lts} in
    begin match name with
      | Some name -> Hint.add v name
      | None -> ()
    end ;
    PTR (ref (V v))

module NS = Map.Make(struct type t = string let compare = compare end)
type namespace = terms NS.t

(** [symbols] is used to obtain the exact same variable term for
  * representing all occurrences of that variable -- used by the parser. *)
let symbols = ref NS.empty

let save_namespace () = !symbols
let restore_namespace s = symbols := s

(** Get the unique variable attached to that name, preserving sharing.
  * The variable is created if it does not exist. *)
let get_var_by_name ~tag ~ts ~lts name =
  try
    NS.find name !symbols
  with
    | Not_found ->
        assert (name <> "") ;
        let lts = 0 in
        let t = fresh tag ~ts ~lts ~name in
          symbols := NS.add name t !symbols ;
          t

(* Same as [get_var_by_name] but infers the tag from the name and sets both
 * levels to 0. *)
let atom name =
  let tag = match name.[0] with
    | 'A'..'Z' -> LOG
    | _ -> CONST
  in
    get_var_by_name ~ts:0 ~lts:0 ~tag name

let get_var x = match observe x with
  | VAR v -> v
  | _ -> assert false

(** Raise Not_found if not naming hint is attached to the variable. *)
let get_hint v =
  let v = get_var v in
  try
    Hint.find v
  with
    | Not_found ->
        begin match v.tag with
          | LOG-> "H"
          | EIG -> "h"
          | CONST -> "c"
        end

(** Find an unique name for [v] (based on a naming hint if there is one)
  * and registers it in the symbols table. *)
let get_name var =
  let var = deref var in
  let existing_name =
    NS.fold
      (fun key value x ->
         (* Do NOT use [eq] instead of [=] here, otherwise it will follow
          * references -- notice that the term in the table has been changed by
          * bindings too.
          * Suppose you bind Y to 1,
          * the initial value representing Y would be [eq] to 1,
          * and could thus take the name 1, depending on the order in which the
          * table is traversed. *)
         if value = var then Some key else x)
      !symbols
      None
  in
    match existing_name with
      | Some n -> n
      | None ->
          let prefix = get_hint var in
          let rec lookup suffix =
            let name =
              if suffix < 0 then prefix else prefix ^ string_of_int suffix
            in
              if NS.mem name !symbols then
                lookup (suffix+1)
              else begin
                symbols := NS.add name var !symbols ;
                name
              end
          in
            lookup (-1)

let dummy = let n = -1 in PTR(ref(V {str="_"; id=n;ts=n;lts=n;tag=CONST }))

(** [get_dummy_name prefix] finds a free name starting with [prefix] and
  * registers it. If [start] is not provided, the attempted suffixes will be
  * "", "0", "1", etc. If it is provided it will be used as the first suffix to
  * try. *)
let get_dummy_name ?(start=(-1)) prefix =
  let rec lookup suffix =
    let name =
      if suffix < 0 then prefix else prefix ^ string_of_int suffix
    in
      if NS.mem name !symbols then
        lookup (suffix+1)
      else begin
        symbols := NS.add name dummy !symbols ;
        name
      end
  in
    lookup start

(** List of [n] new dummy names, most recent first. *)
let get_dummy_names ?(start=(-1)) n prefix =
  let rec aux i =
    if i=0 then [] else
      let tl = aux (i-1) in
        (get_dummy_name ~start prefix)::tl
  in
    List.rev (aux n)

let is_free name =
  not (NS.mem name !symbols)

let free n =
  symbols := NS.remove n !symbols

(** {1 Copying} *)

(** [copy ()] instantiates a copier, that copies terms,
  * preserving sharing inside the set of copied terms.
  * Input terms should be normalized. *)
let copy_eigen () =
  let tbl = Hashtbl.create 100 in
  fun ?(passive=false) tm ->
  let rec cp tm = match observe tm with
    | VAR v when v.tag = EIG ->
        begin try Hashtbl.find tbl v with
          | Not_found ->
              if passive then tm else
                let v' = { v with id = fresh_id () } in
                let x = PTR (ref (V v')) in
                  begin try Hint.add v' (Hint.find v) with _ -> () end ;
                  Hashtbl.add tbl v x ;
                  x
        end
    | VAR v -> tm
    | APP (a,l) -> APP (cp a, List.map cp l)
    | ABS (str,n,b) -> ABS (str, n, cp b)
    | DIV (t1,t2) -> DIV (cp t1, cp t2)
    | TIMES (t1,t2) -> TIMES (cp t1, cp t2)
    | MINUS (t1,t2) -> MINUS (cp t1, cp t2)
    | PLUS (t1,t2) -> PLUS (cp t1, cp t2)
    | STRING (t1) -> STRING (t1)
    | INT (t1) -> INT (t1)
    | CONS (t1) -> CONS (t1)
    (*| LIST (t1) -> LIST(t1)*)
    (*| NB i*) | DB i as x -> x
    | SUSP _ | PTR _ -> assert false
    | t -> failwith "Unexpected case. (term.ml copy_eigen)"
  in
    cp tm

(** {1 Convenience} *)

let string text = get_var_by_name ~tag:CONST ~lts:0 ~ts:0 text

let binop s a b = APP ((atom s),[a;b])

let db n = DB n

let app a b = if b = [] then a else match observe a with
  | APP(a,c) -> APP (a,c @ b)
  | _ -> APP (a,b)

let susp t ol nl e = SUSP (t,ol,nl,e)

let plus l = match l with
  | [t1;t2] -> PLUS(t1,t2)
  | _ -> failwith "ERROR: Expected two elements in a plus."

let minus l = match l with
  | [t1;t2] -> MINUS(t1,t2)
  | _ -> failwith "ERROR: Expected two elements in a plus."

let times l = match l with
  | [t1;t2] -> TIMES(t1,t2)
  | _ -> failwith "ERROR: Expected two elements in a times."

let div l = match l with
  | [t1;t2] -> DIV(t1,t2)
  | _ -> failwith "ERROR: Expected two elements in a times."


(*let get_nablas x =
  let rec nb l t = match observe t with
    | Var _ -> l
    | App (h,ts) -> List.fold_left nb (nb l h) ts
    | Lam (n,t') -> nb l t'
    | DB _ -> l
    | NB i -> if List.mem i l then l else i::l
    | Susp _ | Ptr _ -> assert false
  in
    nb [] x*)

module Notations =
struct
  let (%=) = eq
  let (!!) = observe
  let (//) = lambda
  let (^^) = app
end

let fresh_name name =
  let v = fresh ~name:name CONST ~lts:0 ~ts:0 in
  get_name v
