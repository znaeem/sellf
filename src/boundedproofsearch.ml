(*
 * Proof seach without backchaining.
 * No restriction on what kind of formula is in the context.
 * It is a bounded proof search.
 * One-sided sequent, inital rule: |- not A, A
 * Using only the goals list.
 * goals and context are global variables.
 * Not using the clauses table.
 *
 * Giselle Machado Reis - 2012
 *)

open Basic
open Term
open ProofTree
open Context
open Sequent
open Prints

let unify = 
  let module Unify = 
    Unify.Make ( struct
      let instantiatable = Term.LOG
      let constant_like = Term.EIG
    end )
  in Unify.pattern_unify
;;

let failStack : (unit -> unit) Stack.t = Stack.create () ;;

let initProof formula =
  let ctx = Context.getInitial () in
  let empctx = Context.createEmpty () in
  let seq = Sequent.create ctx empctx (formula::[]) ASYN in
  ProofTree.create seq
;;

let copyCtxOutFromPremisseUn proof = match (ProofTree.getPremisses proof) with
  | [p] ->
    let sqp = ProofTree.getConclusion p in
    let outctx = Sequent.getCtxOut sqp in
    Sequent.setCtxOut (ProofTree.getConclusion proof) outctx
  | _ -> failwith "Error: found unary rule with more than one or no premisses."
;;

(* TODO: not really sure that this is what we need for question mark... *)
(* The formula added by the ?-rule should not be available below this point of the proof. *)
let copyCtxOutSpecialQst proof f sub = match (ProofTree.getPremisses proof) with
  | [p] ->
    let sqp = ProofTree.getConclusion p in
    let ctxout2 = Sequent.getCtxOut sqp in
    let ctxWithoutForm = Context.delete ctxout2 f sub in
    Sequent.setCtxOut (ProofTree.getConclusion proof) ctxWithoutForm
  | _ -> failwith "Error: found unary rule with more than one or no premisses."
;;

let file_name = ref "noname"  ;;

(* Proves a LL formula *)

(* h is the maximum height of the proof. Measured on the number of decide rules.  *)

let rec prove formula h suc fail = 
  let root = initProof formula in
  Stack.push fail failStack;
  prove_asyn root h (fun () ->
    let sq = ProofTree.getConclusion root in
    let ctxout = Sequent.getCtxOut sq in
    if (Context.isLinearEmpty ctxout) then begin
      (* TODO fix the relative path of this file *)
      let file = open_out ((!file_name)^".tex") in
      Printf.fprintf file "%s" (texFileHeader ());
      Printf.fprintf file "%s" (ProofTree.toTexString root);
      Printf.fprintf file "%s" (texFileFooter ());
      close_out file;
      file_name := "noname"; (* Resets file name so it is not overwritten *)
      suc ()
    end
    else begin
      if !verbose then begin
        print_endline ("Failed because out context is not empty...");
        print_endline (Context.toString ctxout);
      end;
      (Stack.pop failStack) ()
    end
  )

and prove_asyn proof h suc =
let conc = ProofTree.getConclusion proof in
match (Sequent.getCtxIn conc, Sequent.getCtxOut conc, Sequent.getGoals conc, Sequent.getPhase conc) with

  (* Decide *)
  | (inctx, _, [], ASYN) ->
    let ctx = Context.toPairs inctx in
    decide h ctx proof (fun () -> copyCtxOutFromPremisseUn proof; suc ())

  (* Asynchronous phase *)

  | (ctxin, ctxout, f::goals, ASYN) -> let f = Term.observe f in begin match f with

    | LOLLI (sub, f1, f2) -> 
      if !verbose then begin
        print_endline "-- Lolli:"; 
        print_endline (termToString (LOLLI(sub, f1, f2)));
        print_endline (Context.toString ctxin);
      end;
      let newctx = Context.add ctxin (nnf (NOT(f2))) (extract_str sub) in
      let sq = Sequent.create newctx ctxout (f1::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 
    (* Solves f1 and f2 with the same context *)
    | WITH (f1, f2) -> begin
      if !verbose then begin
        print_endline "-- With 1st:"; 
        print_endline (termToString (WITH(f1, f2)));
        print_endline (Context.toString ctxin);
      end;
      let sq = Sequent.create ctxin ctxout (f1::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> 
        if !verbose then begin
          print_endline "-- With 2nd:"; 
          print_endline (termToString (WITH(f1, f2)));
          print_endline (Context.toString ctxin);
        end;
        let sq2 = Sequent.create ctxin ctxout (f2::goals) ASYN in
        prove_asyn (ProofTree.update proof sq2) h (fun () ->
          match ProofTree.getPremisses proof with
            | p1::p2::[] -> 
              let ctxout1 = Sequent.getCtxOut (ProofTree.getConclusion p1) in
              let ctxout2 = Sequent.getCtxOut (ProofTree.getConclusion p2) in
              if (Context.equals ctxout1 ctxout2) then begin
                Sequent.setCtxOut (ProofTree.getConclusion proof) ctxout1;
                suc ()
              end
              else (Stack.pop failStack) ()
            | _ -> failwith "With rule with wrong number of premisses."
          )
        )
    end
 
    | PARR (f1, f2) -> 
      if !verbose then begin
        print_endline "-- Parr:"; 
        print_endline (termToString (PARR(f1, f2)));
        print_endline (Context.toString ctxin);
      end;
      let sq = Sequent.create ctxin ctxout (f1::f2::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 
    | QST (s, f) -> begin
      if !verbose then begin
        print_endline "-- Question mark:"; 
        print_endline (termToString (QST(s, f)));
        print_endline (Context.toString ctxin);
      end;
      match Term.observe s with
        | CONS(sub) ->
          let newctx = Context.add ctxin f sub in
          let sq = Sequent.create newctx ctxout goals ASYN in
          prove_asyn (ProofTree.update proof sq) h (fun () ->
            copyCtxOutSpecialQst proof f sub; suc ())
        | _ -> failwith "Not an exponential in question mark."
      end
 
    | FORALL (s, i, f) ->
      if !verbose then begin
        print_endline "-- Forall:"; 
        print_endline (termToString (FORALL(s, i, f)));
        print_endline (Context.toString ctxin);
      end;
      varid := !varid + 1;
      let new_var = VAR ({str = s; id = !varid; tag = Term.EIG; ts = 0; lts = 0}) in
      let newf = Norm.hnorm (APP (ABS (s, 1, f), [new_var])) in
      let sq = Sequent.create ctxin ctxout (newf::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
   
    | TOP -> 
      if !verbose then begin
        print_endline "-- Top:"; 
        print_endline (termToString TOP);
        print_endline (Context.toString ctxin);
      end;
      Context.markErasable ctxin;
      Sequent.setCtxOut (ProofTree.getConclusion proof) ctxin;
      ProofTree.close proof;
      suc ()
 
    | BOT -> 
      if !verbose then begin
        print_endline "-- Bottom:"; 
        print_endline (termToString BOT);
        print_endline (Context.toString ctxin);
      end;
      let sq = Sequent.create ctxin ctxout goals ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())

(*
    | NEW (s, t1) -> 
      if !verbose then begin
        print_endline "-- New subexponential:"; 
        print_endline (termToString (NEW(s, t1)));
        print_endline (Context.toString ctxin);
      end;
      varid := !varid + 1;
      let string_sub = "NSUBEXP"^(string_of_int !varid) in
      let new_cons = CONS string_sub in
      let newf = Norm.hnorm (APP (ABS (s, 1, t1), [new_cons])) in
      new_subexp string_sub;
      goals := newf :: t;
      let sq = SEQ(!context, !goals, ASYN) in
      activeseq := ProofTree.update !activeseq sq;
      prove_asyn h suc fail
*)

    (* R arrow up rule *)
    (* Positive formulas and literals *)
    | ADDOR (_, _)
    | TENSOR (_, _)
    | EXISTS(_, _, _)
    | BANG (_, _)
    | HBANG (_, _)
    | ONE
    | ZERO
    | COMP (_, _, _)
    | ASGN (_, _)
    | PRINT (_)
    | NOT(PRED(_, _, _))
    | PRED(_, _, _) ->
      if !verbose then begin
        print_endline "-- R arrow up:"; 
        print_endline (termToString (Term.observe f));
        print_endline (Context.toString ctxin);
      end;
      let newctx = Context.add ctxin f "$gamma" in
      let sq = Sequent.create newctx ctxout goals ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 
    (* Negated formulas *)
    (* Transform to negated normal form and try to prove them. *)
    | NOT(f) ->
      let negf = nnf (NOT(f)) in
      let sq = Sequent.create ctxin ctxout (negf::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 
    (* Things we are not yet solving *)
    (*
    | EQU (str, n, trm) -> print_endline "Not solving term equality yet."; fail
    | CUT -> print_endline "What should I do when encounter a cut?"; fail
    *)

    (* lambda terms *)
    | APP(head, arg1) -> 
      begin
        match (Norm.hnorm (APP( (Term.observe head), arg1))) with
        | f -> (match f with 
          | CONS(str) ->
            let p = (PRED (str, CONS(str), NEG)) in
            let newctx = Context.add ctxin p "$gamma" in
            let sq = Sequent.create newctx ctxout goals ASYN in
            prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
          | APP(CONS(str3), arg2) ->
            let p = (PRED(str3, APP(CONS(str3), arg2), NEG)) in
            let newctx = Context.add ctxin p "$gamma" in
            let sq = Sequent.create newctx ctxout goals ASYN in
            prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 	     | _ -> failwith "Error on the normalisation of an application."
        )
      end

    (*
    | ABS(s, i, t) -> 
      let newf = db2ptr f in
      let sq = Sequent.create ctxin ctxout (newf::goals) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) fail
    *)

    | f -> print_endline (termToString f); failwith " Solving not implemented for this case."
 
  end
  | _ -> failwith "Invalid sequent on asynschronous phase."

and prove_sync proof h suc = 
let conc = ProofTree.getConclusion proof in
match (Sequent.getCtxIn conc, Sequent.getCtxOut conc, Sequent.getGoals conc, Sequent.getPhase conc) with
  | (_, _, [], SYNC) -> failwith "Empty list of goals in synchronous phase."

  | (ctxin, ctxout, [goal], SYNC) -> let goal = Term.observe goal in begin match goal with

    (* R arrow down rule *)
    (* If a negative formula was found, go back to async phase *)     
    | LOLLI (sub, f1, f2) -> 
      begin 
      if !verbose then begin
        print_endline "-- R arrow down:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end;
      match Term.observe sub with
        | CONS(s) -> 
          let sq = Sequent.create ctxin ctxout [goal] ASYN in
          prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
        | _ -> failwith "Unitialized subexponential while solving lolli."
      end
    | WITH (_, _)
    | PARR (_, _)
    | QST (_, _)
    | FORALL (_, _, _)
    | TOP
    | BOT
    | PRED (_, _, _) (* All atoms are negative *)
    | NEW (_, _) ->
      if !verbose then begin
        print_endline "-- R arrow down:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end;
      let sq = Sequent.create ctxin ctxout [goal] ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) 
 
    (* Synchronous phase *)
 
    (* No rule for zero. Top must be in the context, decide on it and finish. *)
    | ZERO ->
      if !verbose then begin
        print_endline "-- Zero:";
        print_endline (termToString ZERO);
        print_endline (Context.toString ctxin);
      end;
      (Stack.pop failStack) ()
      (*
      let sq = Sequent.create ctxin ctxout (goals @ [f]) ASYN in
      prove_asyn (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
      *)

    | ADDOR (f1, f2) -> begin
      if !verbose then begin
        print_endline "-- O plus 1st:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end;
      (* Updates the proof tree for one in which the conclusion is f1 *)
      let sq = Sequent.create ctxin ctxout [f1] SYNC in
      Stack.push (fun () -> (
        if !verbose then begin
          print_endline "-- O plus 2st:"; 
          print_endline (termToString (Term.observe goal));
          print_endline (Context.toString ctxin);
        end; 
        ProofTree.setPremisses proof [];
        let sq = Sequent.create ctxin ctxout [f2] SYNC in
        prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) ) ) failStack;

      prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) 
    end
 
    | TENSOR (f1, f2) ->
      if !verbose then begin
        print_endline "-- Tensor 1st:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end; 
      let sq = Sequent.create ctxin ctxout [f1] SYNC in
      prove_sync (ProofTree.update proof sq) h (fun () ->
        (* Get out context of first branch and copy to the second as input *)
        match (ProofTree.getPremisses proof) with
          | [p] -> begin
            let ctxin2 = Sequent.getCtxOut (ProofTree.getConclusion p) in
            let sq2 = Sequent.create ctxin2 ctxout [f2] SYNC in
            if !verbose then begin
              print_endline "-- Tensor 2nd:"; 
              print_endline (termToString (Term.observe goal));
              print_endline (Context.toString ctxin2);
            end;
            prove_sync (ProofTree.update proof sq2) h ( fun () ->
              (* Get out context of second branch and propagate it to the conclusion *)
              match (ProofTree.getPremisses proof) with
                | p1::p2::[] -> 
                  let p = ProofTree.getConclusion p1 in
                  Sequent.setCtxOut (ProofTree.getConclusion proof) (Sequent.getCtxOut p);
                  suc ()
                | _ -> failwith "Tensor rule has wrong number of premisses."
              )
          end
            (* This is for the case when the second part of the tensor was
            tried, but failed already before. Just erase the failed branch *)
          | pa::pb::[] -> begin
            let ctxin2 = Sequent.getCtxOut (ProofTree.getConclusion pb) in
            let sq2 = Sequent.create ctxin2 ctxout [f2] SYNC in
            if !verbose then begin
              print_endline "-- Tensor 2nd: another attempt"; 
              print_endline (termToString (Term.observe goal));
              print_endline (Context.toString ctxin2);
            end;
            ProofTree.setPremisses proof [pb];
            prove_sync (ProofTree.update proof sq2) h ( fun () ->
              (* Get out context of second branch and propagate it to the conclusion *)
              match (ProofTree.getPremisses proof) with
                | p1::p2::[] -> 
                  let s = ProofTree.getConclusion p1 in
                  Sequent.setCtxOut (ProofTree.getConclusion proof) (Sequent.getCtxOut s);
                  suc ()
                | _ -> failwith "Tensor rule has wrong number of premisses."
              )
          end
          | x -> failwith "Tensor rule has wrong number of premisses."
        ) 
 
    | EXISTS (s, i, f) ->
      if !verbose then begin
        print_endline "-- Exists:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end;
      varid := !varid + 1;
      let new_var = V ({str = s; id = !varid; tag = Term.LOG; ts = 0; lts = 0}) in
      let ptr = PTR {contents = new_var} in
      let newf = Norm.hnorm (APP (ABS (s, 1, f), [ptr])) in
      let sq = Sequent.create ctxin ctxout [newf] SYNC in
      prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) (*fail*)
    
    | BANG (sub, f) -> 
      begin
        if !verbose then begin
          print_endline "-- Bang:"; 
          print_endline (termToString (Term.observe goal));
          print_endline (Context.toString ctxin);
        end;
        match Term.observe sub with
        | CONS(s) -> 
          let newctxin = Context.bangin ctxin s in
          let sq = Sequent.create newctxin ctxout [f] ASYN in
          prove_asyn (ProofTree.update proof sq) h ( fun () ->
            (* Changes the output context if bang returns successfully *)
            match ProofTree.getPremisses proof with
              | [p] -> 
                let bangctxout = Context.bangout ctxin s in
                let premissectxout = Sequent.getCtxOut (ProofTree.getConclusion p) in
                let newctxout = Context.merge bangctxout premissectxout in
                let conclusion = ProofTree.getConclusion proof in
                Sequent.setCtxOut conclusion newctxout;
                suc ()
              | _ -> failwith "Bang rule with none or more than one premisses."
          )
        | _ -> failwith "Not expected subexponential while solving positive formulas."
      end

(* TODO implement this when I have time
    | HBANG (sub, f) -> begin
      if !verbose then begin
        print_endline "-- Hat bang:"; 
        print_endline (termToString (Term.observe goal));
      end;
      match Term.observe sub with
        | CONS (s) -> ( try match Hashtbl.find !context s with
          | [] -> 
            if !verbose then print_endline ("Solved hbang "^s^".\n"); 
            goals := f :: t; 
            let sq = SEQ(!context, !goals, SYNC) in
            activeseq := ProofTree.update !activeseq sq;
            prove_asyn h suc fail 
          | _ -> 
            if !verbose then print_endline ("Failed in hbang rule "^s^".\n"); 
            fail
          with Not_found -> failwith ("Hbang applied on non-existing
          subexponential: "^s^"\n") 
            (*if !verbose then print_endline ("Solved hbang "^s^".\n"); 
            goals := f :: t; 
            let sq = SEQ(!context, !goals, SYNC) in
            activeseq := ProofTree.update !activeseq sq;
            prove_asyn h suc fail*)
        )
        | _ -> failwith "Not expected subexponential while solving positive formulas."
      end
*)

    | ONE -> 
      if !verbose then begin
        print_endline "-- ONE:"; 
        print_endline (termToString (Term.observe goal));
        print_endline (Context.toString ctxin);
      end;
      Sequent.setCtxOut (ProofTree.getConclusion proof) ctxin;
      ProofTree.close proof;
      suc ()

(* TODO: the proof should be closed when these are successful
    | COMP (ct, t1, t2) -> 
      if (solve_cmp ct t1 t2) then begin
        let sq = Sequent.create ctxin ctxout goals SYNC in
        prove_sync (ProofTree.update proof sq) h (copyCtxOutFromPremisseUn proof; suc) fail
      end   
      else fail
 
    | ASGN (t1, t2) -> 
      if (solve_asgn t1 t2) then begin
        let sq = Sequent.create ctxin ctxout goals SYNC in
        prove_sync (ProofTree.update proof sq) h (copyCtxOutFromPremisseUn proof; suc) fail
      end    
      else fail
*)

    | PRINT (t1) -> print_endline ""; print_string (termToString t1); print_endline "";
      let sq = Sequent.create ctxin ctxout [] SYNC in
      prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
 
 
    (* Initial rules *)
    (* NOTE: Since all atoms are considered negative, the initial rule can only
     * be applied to *negated* atoms (which are positive)
     * | PRED (str, terms, p) ->
      let pairs = Context.toPairs ctxin in
      initial (NOT(PRED(str, terms, p))) pairs proof suc *)
    | NOT(PRED (str, terms, p)) ->
      let pairs = Context.toPairs ctxin in
      initial (PRED(str, terms, p)) pairs proof suc
 
    (* Things we are not solving *)
    (*
    | EQU (str, n, trm) -> print_string "Not solving term equality yet."; fail
    | CUT -> print_string "What should I do when encounter a cut?"; fail
    *)

    (* lambda terms *)
    | APP(head, arg1) -> 
      begin
        match (Norm.hnorm (APP(head, arg1))) with
        | CONS(str) -> 
          let p = (PRED (str, CONS(str), NEG)) in
          let sq = Sequent.create ctxin ctxout [p] SYNC in
          prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
        | APP(CONS(str3), arg2) -> 
          let p = (PRED (str3, APP(CONS(str3), arg2), NEG)) in 
          let sq = Sequent.create ctxin ctxout [p] SYNC in
          prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ())
        | _ -> failwith "Error while normalizing lambda term."
      end
    
    (*
    | ABS(s, i, t) -> 
      let newf = db2ptr goal in
      let sq = Sequent.create ctxin ctxout [newf] SYNC in
      prove_sync (ProofTree.update proof sq) h (fun () -> copyCtxOutFromPremisseUn proof; suc ()) fail
    *)

    | f -> print_endline (termToString f); failwith " Solving not implemented for this case."
 
  end

  | (_, _, goals, SYNC) -> failwith "Sequent with more than one goal in synchronous phase."
  | _ -> failwith "Invalid sequent in synchronous phase."

(* ctx is the context in the form of a list of pairs. *)
and decide h ctx proof suc = 
  if (h <= 0) then begin
    if !verbose then print_endline "Failed because it's bounded.";
    ProofTree.setPremisses proof [];
    (Stack.pop failStack) ()
  end
  else begin
    match ctx with
      | [] -> (Stack.pop failStack) () (* No more formulas available to pick from the context. *)
      | (s, PRED(_,_,_)) :: tl -> decide h tl proof suc (* Cannot decide on negative literal, going on... *)
      | (s, form) :: tl ->
        let conc = ProofTree.getConclusion proof in
        let ctxin = Sequent.getCtxIn conc in
        let ctxout = Sequent.getCtxOut conc in
        let newctxin = Context.remove ctxin form s in
        let goals = (Term.observe form)::[] in
        if !verbose then begin
          print_endline "-- Decide:";
          print_int h; print_newline();
          print_endline (termToString (List.hd goals));
          print_endline (Context.toString ctxin);
        end;
        let sq = Sequent.create newctxin ctxout goals SYNC in
        let h1 = h - 1 in
        Stack.push (fun () -> 
          if !verbose then begin
            print_endline "Failed, deciding again...";
            print_endline "Available options: ";
            List.iter (fun (s, f) -> print_string ((termToString f)^" :: ")) tl;
            print_newline ()
          end;
          ProofTree.setPremisses proof [];
          decide h tl proof suc ) failStack;

        prove_sync (ProofTree.update proof sq) h1 suc
  end

(* Check if there is a unifiable atom in the ctx in. Remove this atom. Set this as the ctx out. *)
and initial f ctx proof suc = match ctx with
  | [] -> (Stack.pop failStack) () (* No unifiable formulas that work *)
  | (s, f1) :: tl -> 
    match (f, f1) with
    | (PRED(str, t, p), PRED(str1, t1, p1)) when str = str1 -> begin
      let bl = save_state () in
      try match unify t t1 with
        | () -> begin
          let conc = ProofTree.getConclusion proof in
          let ctxin = Sequent.getCtxIn conc in
          let newctx = Context.remove ctxin f1 s in
          Sequent.setCtxOut conc newctx;
          Stack.push (fun () -> restore_state bl; initial f tl proof suc) failStack;
          if !verbose then begin
            print_endline "-- Initial:"; 
            print_endline (termToString (Term.observe f));
            print_endline (Context.toString (Sequent.getCtxIn (ProofTree.getConclusion proof)));
          end;
          suc ()
        end
        with _ ->
          initial f tl proof suc
      end
    (* This case should never be used since pred is negative. 
    NOTE: proving NOT(PRED()) calls initial with the non-negated literal. *)
    (*
    |(NOT(PRED(str, t, p)), NOT(PRED(str1, t1, p1))) when str = str1 -> begin
      let bl = save_state () in
      try match unify t t1 with
        | () -> 
          let conc = ProofTree.getConclusion proof in
          let ctxin = Sequent.getCtxIn conc in
          let newctx = Context.remove ctxin f1 s in
          Sequent.setCtxOut conc newctx;
          Stack.push (fun () -> restore_state bl; initial f tl proof suc) failStack;
          suc ()
        with _ -> initial f tl proof suc
        end
    *)
    | _, _ -> initial f tl proof suc

;;
