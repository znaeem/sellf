open ProofTree
open Context
open Subexponentials

module TestUnify = 
  Unify.Make(struct
    let instantiatable = Term.LOG
    let constant_like = Term.EIG
  end)

let position lexbuf =
  let curr = lexbuf.Lexing.lex_curr_p in
  let file = curr.Lexing.pos_fname in
  let line = curr.Lexing.pos_lnum in
  let char = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in
    if file = "" then
      () (* lexbuf information is rarely accurate at the toplevel *)
    else
      print_string "";Format.sprintf ": line %d, character %d" line char

let samefile = ref true ;;
let fileName = ref "" ;;
let check = ref "" ;;

let usage = "Usage: " ^ Sys.argv.(0) ^ " [-v] [-i string] [-c string]"

let argslst = [
  ("-v", Arg.Unit (fun () -> Term.verbose := true), ": set verbose on.");
  ("-i", Arg.String (fun s -> fileName := s), ": prefix of .pl and .sig file (with path)");
  ("-c", Arg.String (fun s -> check := s), ": 'principalcut', 'cutcoherence',
    'initialcoherence', 'atomicelim' or 'scopebang' (depending on what you want to check)");
]

let initAll () = 
  Specification.initialize ();
  Context.initialize ();
  Subexponentials.initialize ();
  Coherence.initialize ();
;;

let generate_bipoles () = begin

  let genBip r = 
    print_endline("=======================================================");
    print_endline("Bipoles for the formula: " ^ (Prints.termToString (Term.observe r)));
    let bipoles = Bipole.bipole r in
    List.iter ( fun (pt, clst) ->
      print_endline("-------------------------------------------------------");
      print_endline("Open leaves: ");
      ProofTreeSchema.printOpenLeaves pt;
      print_newline ();
      List.iter (fun c -> 
        print_endline("<<<<<< begin constraint set >>>>>>>");
        Constraints.printConstraints c;
        print_endline("<<<<<< end constraint set >>>>>>>\n")
      ) clst;
      print_endline("-------------------------------------------------------\n")
    ) bipoles;
    print_endline("=======================================================\n")
  in
  List.iter ( fun r -> genBip r ) !Specification.introRules
end ;;

let check_principalcut () = begin
  if Staticpermutationcheck.cut_principal () then 
    print_endline "Tatu could infer that reduction to principal cuts is possible." else
    print_endline "\nCould not reduce to principal cuts.
      \nObservation: It is very likely that the cases shown above are valid permutations by vacuosly."
end ;;

let check_atomicelim () = begin
  if Staticpermutationcheck.weak_coherent () then 
  print_endline "Tatu could infer that it is always possible to eliminate atomic cuts." else
  print_endline "\nCould not infer how to eliminate atomic cuts."  
end ;;

let check_cutcoherence () = Coherence.cutCoherence () ;;
let check_initialcoherence () = Coherence.initialCoherence () ;;

let check_scopebang () = begin
  print_endline "Please type the subexponential:";
  let s = read_line() in
  let ers = Subexponentials.erased_bang s in
  let ept = Subexponentials.empty_bang s in
  print_endline ("!"^s^"  : ");
  print_endline "The following will have their formulas erased: ";
  List.iter (fun a -> print_string (a^", ")) ers; print_newline ();
  print_endline "The following should be empty: ";
  List.iter (fun a -> print_string (a^", ")) ept; print_newline ();
end ;;

let parse file_name = begin
  let file_sig = open_in (file_name^".sig") in
  let lexbuf = Lexing.from_channel file_sig in
  begin
    try 
      while true do
        let _ = Parser_systems.types Lexer.token lexbuf in ();
      done; true
    with 
      |  Lexer.Eof -> 
          let file_prog = open_in (file_name^".pl") in 
          let lexbuf = Lexing.from_channel file_prog in
            begin
            try
              while true do
                let _ = Parser_systems.clause Lexer.token lexbuf in ();
              done; true 
            with
              | Lexer.Eof -> true
              | Parsing.Parse_error ->  Format.printf "Syntax error while parsing .pl file%s.\n%!" (position lexbuf); false
              | Failure str -> Format.printf ("ERROR:%s\n%!") (position lexbuf); print_endline str; false
            end
      |  Parsing.Parse_error ->  Format.printf "Syntax error while parsing .sig file%s.\n%!" (position lexbuf); false
      |  Failure _ -> Format.printf "Syntax error%s.\n%!" (position lexbuf); false
    end
end ;;
 
let rec start () =
  initAll ();
  print_string ":> ";
    let command = read_line() in
    try 
      let lexbuf_top = Lexing.from_string command in 
      let action = Parser_systems.top Lexer_top.token lexbuf_top in 
      match action with
      | "help" -> start ()
      | "verbose-on" -> print_endline "Verbose is set to on."; Term.verbose := true; start ()
      | "verbose-off" -> print_endline "Verbose is set to off."; Term.verbose := false; start ()
      | "time-on" -> Term.time := true; print_endline "Time is set to on."; start ()
      | "time-off" -> Term.time := false; print_endline "Time is set to off."; start ()
      | file_name -> 
        print_endline ("Loading file "^file_name);
        if parse file_name then begin
          samefile := true;
          while !samefile do 
            solve_query (); 
          done
        end
        else start ();
    with
    |  Parsing.Parse_error ->  print_endline "Invalid command. For more information type #help."; start  ()
    |  Sys_error str -> print_string ("Error"^str); print_endline ". Please double check the name of the file."; start ()
and
solve_query () = 
  print_string "?> ";
  let query_string = read_line() in
  if query_string = "#done" then samefile := false      
  else begin
  match query_string with 
    | "#rules" -> generate_bipoles ()

(*
    | "#perm" ->
      let tryPermute a b = 
        print_endline "\nLet ";
        print_string "r1 = "; Prints.print_term a; print_string " and \n";
        print_string "r2 = "; Prints.print_term b; print_string "\n";
        flush stdout;
	      let start_time = Sys.time () in
        try match Permutation.permute a b with
          | true -> 
	          let end_time = Sys.time () in
	          let total = end_time -. start_time in
            print_endline "Then r1 permutes over r2.";
	          Printf.printf "Execution time: %f seconds.\n" total
          | false -> 
	          let end_time = Sys.time () in
	          let total = end_time -. start_time in
            print_endline "Then, r1 does NOT permute over r2.";
	          Printf.printf "Execution time: %f seconds.\n" total
          with s -> 
	          let end_time = Sys.time () in
	          let total = end_time -. start_time in
            (* TODO: give more information on this error. *)
            print_endline ("Error: "^(Printexc.to_string s));
	          Printf.printf "Execution time: %f seconds.\n" total
      in

      (* Checking permutation of every pair of rules in the file *)
      let rec every_pair forms = match forms with
        | [] -> print_endline "Done."
        | hd :: tl ->
          (* Checking the formula with itself *)
          (* This makes no sense yet because both formulas use the same
          constants *)
          (* TODO: allow the specification to be done with variables and
          instantiate fresh constants for each variable. *)
          (*tryPermute hd hd;*)
          
          let rec check_perm f lst = match lst with
            | [] -> ()
            | h :: t -> 
              tryPermute f h;
              tryPermute h f;
              check_perm f t    

          in check_perm hd tl; every_pair tl
      in every_pair !Structs.rules;
    *)

    | "#cutcoherence" -> check_cutcoherence ()
    
    | "#initialcoherence" -> check_initialcoherence ()

    | "#scopebang" -> check_scopebang ()

    | "#atomicelim" -> check_atomicelim () 

    | "#principalcut" -> check_principalcut ()

    | _ -> begin
      let query = Lexing.from_string query_string in
      begin
      try 
        (*let _ = Parser.goal Lexer.token query in ();*)
        let _ = Parser_systems.goal Lexer.token query in 
          begin
            createProofSearchContext ();
            Boundedproofsearch.prove !Term.goal !Term.psBound (fun () ->
              print_string "\nYes.\n";
            ) (fun () -> print_string "\nNo.\n")
          end
      with
        | Parsing.Parse_error -> Format.printf "Syntax error%s.\n%!" (position query); solve_query ()
        | Failure str -> Format.printf "ERROR:%s\n%!" (position query); print_endline str; start()
      end      
    end

    (*| _ -> print_endline "Function not implemented. Try again or type #done
     * and #help."*)

  end

let _ = 
Arg.parse argslst (fun x -> raise (Arg.Bad ("Bad argument: "^x))) usage;
match (!check, !fileName) with 
  | ("", "") ->
    print_endline "SELLF -- A linear logic framework for systems with locations.";
    print_endline "Version 0.5.\n";
    print_endline "Type #help for a list of available commands.\n";
    while true do
      start ()
    done
  (* Running in batch mode *)
  | ("principalcut", file) -> 
    initAll ();
    if parse file then check_principalcut ()
  | ("cutcoherence", file) -> 
    initAll ();
    if parse file then check_cutcoherence ()
  | ("initialcoherence", file) -> 
    initAll ();
    if parse file then check_initialcoherence ()
  | ("atomicelim", file) -> 
    initAll ();
    if parse file then check_atomicelim ()
  | ("scopebang", file) ->
    initAll ();
    if parse file then check_scopebang ()
  | (x, y) -> failwith ("Invalid arguments.")
;;

