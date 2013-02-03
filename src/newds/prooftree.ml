open Term 
open Prints
open Sequent

(* What is this for??? *)
let counter = ref 0 ;;

(* Declare mutable so I can modify directly on the object *)
type prooftree = {
  mutable conclusion : Sequent.sequent;
  mutable premisses : prooftree list;
  mutable rule : Llrule.rule;
}
    
let create sq = {
  conclusion = sq;
  premisses = []
}

let setConclusion pt c = pt.conclusion <- c

let getConclusion pt = pt.conclusion

let setPremisses pt p = pt.premisses <- p
let getPremisses pt = pt.premisses

let addPremisse pt p = let newc = create p in
  pt.premisses <- newc :: pt.premisses

    let getLatestPremisse pt = try List.hd pt.premisses 
      with Failure "hd" -> failwith "[ERROR] This sequent has no premisses."

    let rec copy pt = let cp = create pt.conclusion in
      let rec cpPremisses lst = match lst with
        | [] -> []
        | p::t -> (copy p) :: cpPremisses t
      in
      setPremisses cp (cpPremisses pt.premisses); cp

    (* Updates the tree with a new premisse and returns a reference to this new
    child *)
    let update pt sq = let newc = create sq in
      pt.premisses <- newc :: pt.premisses; newc

    let rec getLeaves pt = List.fold_right (fun el acc -> 
      match el.premisses with
        | [] -> el :: acc
        | _ -> getLeaves el @ acc
      ) pt.premisses []

(*
    let rec getOpenLeaves pt = List.fold_right (fun el acc -> 
      match el.premisses with
        | [] -> if is_open el.conclusion then el :: acc else acc
        | _ -> getOpenLeaves el @ acc
      ) pt.premisses []
*)

(*
    let rec getOpenLeaves pt = List.fold_right (fun el acc ->
      if not el.closed then el :: acc
      else getOpenLeaves el @ acc
      ) pt.premisses []
*)

(* FIXME this was a very bad hack done for the permutation algorithm... try to fix it.
    let rec mask m pt = 
      let concm = m.conclusion in
      let concpt = pt.conclusion in
      if isEqual concm concpt then begin
        let rec filteredPrem lst = match lst with
          | [] -> []
          | hd::tl -> try
            let pm = List.find (fun p -> isEqual p.conclusion hd.conclusion) m.premisses in
              mask pm hd;
              hd :: filteredPrem tl
            with Not_found -> filteredPrem tl
        in
        setPremisses pt (filteredPrem pt.premisses)
      end
      else failwith "[ERROR] Masking trees with different root."
*)

    let rec toTexString pt = match pt.closed with
      | true ->
        let topproof = match pt.premisses with
          | [] -> ""
          | hd::tl -> (toTexString hd)^(List.fold_right (fun el acc -> "\n&\n"^(toTexString el)) tl "") 
        in
        "\\infer{"^(Sequent.toTexString (getConclusion pt))^"}\n{"^topproof^"}"
      (* An open proof has no premisses. *)
      | false -> (Sequent.toTexString (getConclusion pt))
      
(*
    let printTexProof pt out = 
      Printf.fprintf out "\\documentclass[a4paper, 11pt]{article}\n"; 
      Printf.fprintf out "\\usepackage[utf8]{inputenc}\n"; 
      Printf.fprintf out "\\usepackage{amsmath}\n"; 
      Printf.fprintf out "\\usepackage{amssymb}\n"; 
      Printf.fprintf out "\\usepackage{stmaryrd}\n"; 
      Printf.fprintf out "\\usepackage{proof}\n\n"; 
      Printf.fprintf out "\\usepackage[landscape]{geometry}\n\n"; 
      Printf.fprintf out "\\begin{document}\n{\\tiny\n$$\n";
      printLatex pt out;
      Printf.fprintf out "$$\n}\n\\end{document}"
    
    let printTexMacros lst out = 
      Printf.fprintf out "\\documentclass[a4paper, 11pt]{article}\n"; 
      Printf.fprintf out "\\usepackage[utf8]{inputenc}\n"; 
      Printf.fprintf out "\\usepackage{amsmath}\n"; 
      Printf.fprintf out "\\usepackage{amssymb}\n"; 
      Printf.fprintf out "\\usepackage{stmaryrd}\n"; 
      Printf.fprintf out "\\usepackage{proof}\n\n"; 
      Printf.fprintf out "\\usepackage[landscape]{geometry}\n\n";
      Printf.fprintf out "\\begin{document}\n\n";
      let rec printEach lst out = match lst with
        | [] -> ()
        | (p, c)::t -> 
          Printf.fprintf out "{\\tiny\n$$\n";
          printLatex p out; 
          Printf.fprintf out "$$\n}\n";
          (*Printf.fprintf out "\\begin{itemize}\n";
          Constraints.printTexConstraints c out;
          Printf.fprintf out "\\end{itemize}\n";*)
          printEach t out
      in printEach lst out;
      Printf.fprintf out "\n\\end{document}"


(* Printing the tree for JIT (not implemented for macro rules) *)
    let rec printJitChildren children out = match children with
      | [] -> ()
      | h::t -> printJitTree h out; printJitChildren t out

    and printJitTree pt out = match pt.conclusion with
      | SEQ(_, terms, ASYN) -> 
        Printf.fprintf out "{ id: \"%d\", name: \"" !counter;
        counter := !counter + 1; 
        printf_list_terms out terms; Printf.fprintf out "\", \ndata: {},\nchildren: [";
        printJitChildren pt.premisses out;
        Printf.fprintf out "]}\n"
  
      | SEQ(_, terms, SYNC) ->
        Printf.fprintf out "{ id: \"%d\", name: \"" !counter; 
        counter := !counter + 1;
        printf_list_terms out terms; Printf.fprintf out "\", \ndata: {},\nchildren: [";
        printJitChildren pt.premisses out;
        Printf.fprintf out "]}\n"
(*  
      | SEQ(_, terms, LHS, ASYN) ->
        Printf.fprintf out "{ id: \"%d\", name: \"" !counter;
        counter := !counter + 1; 
        printf_list_terms out terms; Printf.fprintf out "\", \ndata: {},\nchildren: [";
        printJitChildren pt.premisses out;
        Printf.fprintf out "]}\n"
   
      | SEQ(_, terms, LHS, SYNC) ->
        Printf.fprintf out "{ id: \"%d\", name: \"" !counter;
        counter := !counter + 1; 
        printf_list_terms out terms; Printf.fprintf out "\", \ndata: {},\nchildren: [";
        printJitChildren pt.premisses out;
        Printf.fprintf out "]}\n"
*)
      | SEQM(_, _, _) -> failwith "Printing Jit tree is not implemented for
        macro rules."

      | EMPSEQ -> ()
    ;;  
*)
 end
;;

(* TODO: check if it's worth to join these two modules parametrizing on the type
of the sequent or making it an option *)
module ProofTreeSchema = 
  struct

    type prooftree = {
      conclusion : SequentSchema.sequent;
      mutable premises : prooftree list;
      closed : bool;
    }
    
    let create sq = {
      conclusion = sq;
      premises = [];
      closed = false;
    }
   
    let getConclusion pt = pt.conclusion
    
    (* Updates the tree with a new premisse and returns a reference to this new
    child *)
    let update pt sq = let newc = create sq in
      pt.premises <- newc :: pt.premises; newc

    let clearPremises pt = pt.premises <- []

  end
;;



