(* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *  
 *                                                                      * 
 * CODE FOR PROVING COHERENCE OF SEQUENT SYSTEMS' SPECIFICATION         *
 *                                                                      *
 * NOTE:                                                                *
 * - the predicates that map object-level formulas to meta-level        *
 *   atoms are 'lft' and 'rght'                                         *
 * - formulas from the object logic have type 'form'                    *
 * - terms from the object logic have type 'term'                       *
 * - specification formulas are saved on the context $infty             *
 * - procedures to check cut and initial coherence                      *
 *                                                                      *
 * Giselle Machado Reis - 2011                                          *
 *                                                                      *
  * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *)

open Term
open Boundedproofsearch
open Prints
open TypeChecker
(*open Staticpermutationcheck (* because I am reusing the list of cuts *)*)

let cutcoherent = ref true ;;
let initcoherent = ref true ;;

(* The specifications of each connective are stored in a hash 
 * The key is the name of the predicate representing the connective *)
let lr_hash : ((string, (terms option * terms option)) Hashtbl.t) ref = ref (Hashtbl.create 100) ;;

let initialize () = 
  cutcoherent := true;
  initcoherent := true;
  Hashtbl.clear !lr_hash ;;

(* Operation for the case that there is more than one specification for one side *)
let addLSpec str t = try match Hashtbl.find !lr_hash str with
  | (NONE, SOME(r)) -> Hashtbl.replace !lr_hash str (SOME(t), SOME(r))
  | (SOME(l), SOME(r)) -> Hashtbl.replace !lr_hash str (SOME(ADDOR(l, t)), SOME(r)) 
  with Not_found -> Hashtbl.add !lr_hash str (SOME(t), NONE)

let addRSpec str t = try match Hashtbl.find !lr_hash str with
  | (SOME(l), NONE) -> Hashtbl.replace !lr_hash str (SOME(l), SOME(t))
  | (SOME(l), SOME(r)) -> Hashtbl.replace !lr_hash str (SOME(l), SOME(ADDOR(r, t))) 
  with Not_found -> Hashtbl.add !lr_hash str (NONE, SOME(t))

let getFirstArgName p = match p with
  | APP(CONS(n), lst) -> begin match lst with
    | CONS(s) :: t -> s
    | APP(CONS(s), _) :: t -> s
    | _ -> failwith "Error while getting the name of a connective. Are you sure
    this is a introduction rule specification?"
  end
  | _ -> failwith "Function is not an application."

let processIntroRule t = 
  let rec getPred f = match f with 
    | TENSOR(NOT(prd), spc) -> prd
    | ABS(s, i, t) -> getPred t
    | NOT(prd) -> prd
    | _ -> failwith "Not expected formula in specification."
  in
  let rec getSpec f = match f with
    | TENSOR(NOT(prd), spc) -> spc
    | ABS(s, i, t) -> ABS(s, i, getSpec t)
    | NOT(prd) -> TOP (* Specification has no body. *)
    | _ -> failwith "Not expected formula in specification."
  in
  let (p, s) = getPred t, getSpec t in
  match p with
    | PRED("lft", p, _) -> addLSpec (getFirstArgName p) s
    | PRED("rght", p, _) -> addRSpec (getFirstArgName p) s
    | PRED("mlft", p, _) -> addLSpec (getFirstArgName p) s
    | PRED("mrght", p, _) -> addRSpec (getFirstArgName p) s
    | _ -> failwith "Valid predicates are 'lft' or 'right' or 'mlft' or 'mrght'."
;;

(* Procedure to actually check the coherence of a system *)

let system_name = ref "" ;;

let checkInitCoher str (t1, t2) =
  file_name := ((!system_name)^"_initCoh_"^str); 
  (* Put axiom formulas on the context *)
  Context.clearInitial ();
  List.iter (fun e -> Context.store e "$infty") !ids;

  let f0 = match (t1, t2) with
    | (SOME(tt1), NONE) ->
      let bt1 = QST(CONS("$infty"), tt1) in
      deBruijn true bt1
    | (NONE, SOME(tt2)) ->
      let bt2 = QST(CONS("$infty"), tt2) in
      deBruijn true bt2
    | (SOME(tt1), SOME(tt2)) ->
      let bt1 = QST(CONS("$infty"), tt1) in
      let bt2 = QST(CONS("$infty"), tt2) in
      (* Assign deBruijn indices correctly, after the two formulas are joined *)
      deBruijn true (PARR(bt1, bt2))
  in
  (* print_endline "Proving initial coherence of:";
  print_endline (termToString bt1);
  print_endline (termToString bt2); *)
  (* Replace abstractions by universal quantifiers *)
  let f = abs2forall f0 in
  prove f 4 (fun () ->
          print_string ("====> Connective "^str^" is initial-coherent.\n"); ()
        )  
        (fun () ->
          initcoherent := false;
          print_string ("x===> Connective "^str^" is not initial-coherent.\n");
        )
;;

let checkDuality str (t1, t2) =
  file_name := ((!system_name)^"_cutCoh_"^str); 
  (* Put cut formulas on the context *)
  Context.clearInitial ();
  List.iter (fun e -> Context.store e "$infty") !cutRules;

  let f0 = match (t1, t2) with
    | (SOME(tt1), NONE) ->
      let nt1 = deMorgan (NOT(tt1)) in
      deBruijn true nt1
    | (NONE, SOME(tt2)) ->
      let nt2 = deMorgan (NOT(tt2)) in
      deBruijn true nt2
    | (SOME(tt1), SOME(tt2)) ->
      let nt1 = deMorgan (NOT(tt1)) in
      let nt2 = deMorgan (NOT(tt2)) in
      (* Assign deBruijn indices correctly, after the two formulas are joined *)
      deBruijn true (PARR(nt1, nt2))
  in
  (* print_endline "Proving cut coherence of:";
  print_endline (termToString nt1);
  print_endline (termToString nt2); *)
  (* Replace abstractions by universal quantifiers *)
  let f = abs2forall f0 in
  prove f 4 (fun () ->
          print_string ("====> Connective "^str^" has dual specification.\n"); ()
        )  
        (fun () ->
          cutcoherent := false;
          print_string ("x===> Connective "^str^" does not have dual specifications.\n");
        )
;;

(* TODO: put proper system name *)
let cutCoherence () =
  system_name := "proofsTex/proof";
  Hashtbl.iter checkDuality !lr_hash;
  if !cutcoherent then print_string "\nTatu coud prove that the system is cut coherent.\n"
  else print_string "\nThe system is NOT cut coherent.\n";
;;

let initialCoherence () =
  system_name := "proofsTex/proof";
  Hashtbl.iter checkInitCoher !lr_hash;
  if !initcoherent then print_string "\nTatu could prove that the system is initial coherent.\n"
  else print_string "\nThe system is NOT initial coherent.\n"
;;

