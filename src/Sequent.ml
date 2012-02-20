(* Giselle Machado Reis - 2012 *)

(************************** SEQUENTS ************************)

open Term
open Context
open Prints

type phase = 
  | ASYN
  | SYNC

let print_phase p = match p with
  | ASYN -> print_string "asyn"
  | SYNC -> print_string "sync"
;;

module Sequent = 
  struct

  type sequent = {
    mutable ctxin : Context.context;
    mutable ctxout : Context.context;
    mutable goals : terms list;
    pol : phase
  }

  let create () = {
    ctxin = Context.createEmpty ();
    ctxout = Context.createEmpty ();
    goals = [];
    pol = SYNC
  }

  let create phase = {
    ctxin = Context.createEmpty ();
    ctxout = Context.createEmpty ();
    goals = [];
    pol = phase;
  }

  let create ci co lf ph = {
    ctxin = ci;
    ctxout = co;
    goals = lf;
    pol = ph
  }

  let getPhase seq = seq.pol

  let setGoal seq f = seq.goals <- [f]
  let setGoals seq lf = seq.goals <- lf
  let getGoals seq = seq.goals

  let setCtxIn seq ic = seq.ctxin <- ic
  let getCtxIn seq = seq.ctxin

  let setCtxOut seq oc = seq.ctxout <- oc
  let getCtxOut seq = seq.ctxout

  let addGoal seq f = seq.goals <- f::seq.goals

(*
  let isEqual s1 s2 = match s1, s2 with
    | SEQ(ht1, tl1, ph1), SEQ(ht2, tl2, ph2) -> ht1 = ht2 && tl1 = tl2 && ph1 = ph2 
    | SEQM(ht1, tl1, ph1), SEQM(ht2, tl2, ph2) -> ht1 = ht2 && tl1 = tl2 && ph1 = ph2 
    | EMPSEQ, EMPSEQ -> true
    | _, _ -> false
*)

  let toString seq = match seq.pol with
    | ASYN -> "K : Γ ⇑ "^(termsListToString seq.goals)
    | SYNC -> "K : Γ ⇓ "^(termsListToString seq.goals)

  let toTexString seq = match seq.pol with
    | ASYN -> ("\\mathcal{K} : \\Gamma \\Uparrow "^(termsListToTexString seq.goals) )
    | SYNC -> ("\\mathcal{K} : \\Gamma \\Downarrow "^(termsListToTexString seq.goals) )

  end
;;

(*
module Sequent_Schema = 
  struct
  
  type sequent_schema = {
    ctx : context_schema;
    goals : terms list;
    pol : phase
  }

  (* TODO complete when needed *)

  end
;;
*)