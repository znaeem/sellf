(*****************************************)
(*                                       *)
(*  Constraint set for reasoning about   *)
(*  context variables                    *)
(*                                       *)
(*  Giselle Reis                         *)
(*  2013                                 *)
(*                                       *)
(*****************************************)

open ContextSchema (* Remove this dependency *)
open Types
open Term
open Prints
open Subexponentials

let i = ref 0;;

type ctx = string * int
type constraintpred = 
  | IN of terms * ctx * int
  | EMP of ctx
  | UNION of ctx * ctx * ctx
  | SETMINUS of ctx * terms * ctx
  | REQIN_UNB of terms * ctx (* printed as ":- not in(term, ctx)."*)
  | REQIN_LIN of terms * ctx (* printed as ":- not in(term, ctx). :- in(F, G), in(F', G), F != F'."*)
 
type constraintset = {
  mutable lst : constraintpred list;
}

let create predlst = {
  lst = predlst
}

let union set1 set2 = create (set1.lst @ set2.lst)

let times set1 set2 = List.concat (List.map (fun cst1 ->
  List.map (fun cst2 -> union cst1 cst2) set2
) set1)

(* TODO: check if this method is actually needed *)
let copy cst = create cst.lst

let isEmpty cst = (List.length cst.lst) == 0

let isIn f subexp ctx = 
  let index = ContextSchema.getIndex ctx subexp in
  create [IN(f, (subexp, index), 1)]
;;

(* TODO: decent error handling. *)
let inEndSequent f ctx = 
  let head = Term.getHeadPredicate f in
  let side = Term.getSide f in
  let main = Term.getConnectiveName f in
  let conDeclared s = Hashtbl.mem Subexponentials.conTbl s in
  List.fold_right (fun (s, i) acc -> 
    let conList = try Hashtbl.find Subexponentials.conTbl s with Not_found -> [] in
    if s = "gamma" || s = "infty" then acc
    else try match (getCtxSide s, conDeclared s, conList) with
      | (RIGHTLEFT, false, _) -> (isIn head s ctx) :: acc
      | (RIGHT, false, _) when side  = "r" -> (isIn head s ctx) :: acc
      | (LEFT, false, _) when side = "l" -> (isIn head s ctx) :: acc
      | (RIGHTLEFT, true, lst) when List.mem main lst -> (isIn head s ctx) :: acc
      | (RIGHT, true, lst) when side  = "r" && List.mem main lst -> (isIn head s ctx) :: acc
      | (LEFT, true, lst) when side = "l" && List.mem main lst ->(isIn head s ctx) :: acc
      | _ -> acc
      with _ -> acc
  ) (ContextSchema.getContexts ctx) []
;;

let insert f subexp oldctx newctx = 
  let oldindex = ContextSchema.getIndex oldctx subexp in
  let newindex = ContextSchema.getIndex newctx subexp in
  create [SETMINUS((subexp, newindex), f, (subexp, oldindex))]

let empty subexp ctx = 
  let index = ContextSchema.getIndex ctx subexp in
  create [EMP(subexp, index)]

(* Creates empty constraints for all linear contexts *)
let linearEmpty ctx = 
  let contexts = ContextSchema.getContexts ctx in
  let cstrlst = List.fold_right (fun (s, i) acc -> match type_of s with
    | AFF | LIN -> EMP(s, i) :: acc
    | REL | UNB -> acc
  ) contexts [] in
  create cstrlst

(* Creates the union constraints of linear contexts of newctx1 and newctx2
  resulting in contexts of ctx *)
let split ctx newctx1 newctx2 =
  let contexts = ContextSchema.getContexts ctx in
  let cstrlst = List.fold_right (fun (s, i) acc -> 
    let i1 = ContextSchema.getIndex newctx1 s in
    let i2 = ContextSchema.getIndex newctx2 s in
    if (i1 != i2) then
      UNION((s, i1), (s, i2), (s, i)) :: acc
    else acc
  ) contexts [] in
  create cstrlst

(* Creates the emptiness constraints for the bang rule *)
let bang ctx subexp = 
  let contexts = ContextSchema.getContexts ctx in
  let cstrlst = List.fold_right (fun (s, i) acc ->
    if s = subexp || (greater_than s subexp) then acc
    else EMP(s, i) :: acc
  ) contexts [] in
  create cstrlst

let requireIn f (subexp, i) = match type_of subexp with
  | AFF | LIN -> REQIN_LIN(f, (subexp, i))
  | REL | UNB -> REQIN_UNB(f, (subexp, i))

(* Several sets of constraints are created and a list of constraint sets is
returned *)
let initial ctx f = 
  let contexts = ContextSchema.getContexts ctx in
  (* Suppose the dual of f is in s, generates all the constraints *)
  let isHere (sub, i) dualf = 
    let empty = List.fold_right (fun (s, i) acc ->
      if s != sub then begin match type_of s with
        | LIN | AFF -> EMP(s, i) :: acc
        | UNB | REL -> acc
      end else acc
    ) contexts []
    in
    (requireIn dualf (sub, i)) :: empty
  in
  let cstrs = List.fold_right (fun c acc ->
    let formSide = Term.getSide (nnf (NOT f)) in
    (* Gamma and infty contexts aren't being processed. If the theory isn't bipole, this is wrong. *)
    if (fst(c)) = "gamma" || (fst(c)) = "infty" || not (Subexponentials.isSameSide (fst(c)) formSide) then acc
    else ( isHere c (nnf (NOT(f))) ) :: acc 
  ) contexts [] in
  List.map (fun set -> create set) cstrs

let predToTexString c = match c with
  | IN (t, c, n) -> 
    "$in(" ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c) ^ ", " ^ (string_of_int n) ^ ").$"
  | SETMINUS (c1, t, c0) ->
    "$minus(" ^ (ContextSchema.ctxToTex c1) ^ ", " ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c0) ^ ").$"
  | EMP (c) -> 
    "$emp(" ^ (ContextSchema.ctxToTex c) ^ ").$"
  | UNION (c1, c2, c3) -> 
    "$union(" ^ (ContextSchema.ctxToTex c1) ^ ", " ^ (ContextSchema.ctxToTex c2) ^ ", " ^ (ContextSchema.ctxToTex c3) ^ ").$"
  | REQIN_UNB (t, c) -> 
    "$requiredInUnb(" ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c) ^ ") (:- not in()).$"
  | REQIN_LIN (t, c) -> 
    "$requiredInLin(" ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c) ^ ") (:- not in(F, G). :- in(F, G), in(F', G), F != F'.).$"

let rec toTexString csts = 
  (List.fold_right (fun c str -> (predToTexString c) ^ "\n\n" ^ str) csts.lst "") 

let predToJaxString c = match c with
  | IN (t, c, n) -> 
    "in(" ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c) ^ ", " ^ (string_of_int n) ^ ")."
  | SETMINUS (c1, t, c0) ->
    "minus(" ^ (ContextSchema.ctxToTex c1) ^ ", " ^ (termToTexString t) ^ ", " ^ (ContextSchema.ctxToTex c0) ^ ")."
  | EMP (c) -> 
    "emp(" ^ (ContextSchema.ctxToTex c) ^ ")."
  | UNION (c1, c2, c3) -> 
    "union(" ^ (ContextSchema.ctxToTex c1) ^ ", " ^ (ContextSchema.ctxToTex c2) ^ ", " ^ (ContextSchema.ctxToTex c3) ^ ")."
  | _ -> ""
                                                                                                                         
let rec toJaxString csts = 
  let i = ref (-1) in
  let counter () = i := !i + 1; !i in
  (List.fold_right (fun c str ->
    let bl = if (counter() mod 3) = 0 then "\\\\" else " " in
    (predToJaxString c) ^ bl ^ str) 
  csts.lst "")

let predToString c = match c with
  | IN (t, c, n) -> 
    "in(\"" ^ (termToString t) ^ "\", " ^ (ContextSchema.ctxToStr c) ^ ", " ^ (string_of_int n) ^ ")."
  | SETMINUS (c1, t, c0) ->
    "minus(" ^ (ContextSchema.ctxToStr c1) ^ ", \"" ^ (termToString t) ^ "\", " ^ (ContextSchema.ctxToStr c0) ^ ")."
  | EMP (c) ->
    "emp(" ^ (ContextSchema.ctxToStr c) ^ ")."
  | UNION (c1, c2, c3) -> 
    "union(" ^ (ContextSchema.ctxToStr c1) ^ ", " ^ (ContextSchema.ctxToStr c2) ^ ", " ^ (ContextSchema.ctxToStr c3) ^ ")."
  | REQIN_UNB (t, c) -> 
    ":- #count{ I : in_unique(\"" ^ (termToString t) ^ "\", I, " ^ (ContextSchema.ctxToStr c) ^ ") } = 0."
  | REQIN_LIN (t, c) ->
    ":- #count{ I : in_unique(\"" ^ (termToString t) ^ "\", I, " ^ (ContextSchema.ctxToStr c) ^ ") } = 0.\n" ^ 
    ":- #count{ I : in_unique(\"" ^ (termToString t) ^ "\", I, " ^ (ContextSchema.ctxToStr c) ^ ") } > 1.\n" ^
    ":- in_unique(F, _, " ^ (ContextSchema.ctxToStr c) ^ "), F != \"" ^ (termToString t) ^ "\"."

let toString csts = 
  List.fold_right (fun c str -> 
    (predToString c) ^ "\n" ^ str
  ) csts.lst ""

let isUnion cstr = 
  match cstr with
  | UNION (_, _, _) -> true
  | _ -> false
  
let isIn cstr = 
  match cstr with
  | IN (_, _, _) -> true
  | _ -> false

let isEmp cstr = 
  match cstr with
  | EMP (_) -> true
  | _ -> false
  
let isMinus cstr = 
  match cstr with
  | SETMINUS (_, _, _) -> true
  | _ -> false
  
let isUnbounded cstr = 
  match cstr with
  | UNION (_, _, (s, _)) -> type_of s = UNB 
  | IN (_, (s, _), _) -> type_of s = UNB
  | EMP ((s, _)) -> type_of s = UNB
  | SETMINUS (_, _, (s, _)) -> type_of s = UNB
  | _ -> failwith "Error: unexpected constraint (isUnbounded)."
  
let isBounded cstr = not (isUnbounded cstr)
