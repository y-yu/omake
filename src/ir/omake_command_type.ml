(*
 * Individual command arguments have three forms:
 *    - value lists
 *    - arg_string lists
 *    - string
 *
 * The arg_string is like a string, but various parts of it are quoted.
 *)
type arg_string =
  | ArgString of string
  | ArgData   of string

type arg = arg_string list

type command_digest = Digest.t option

(*
 * A command line is a string, together with come flags.
 *)
type command_flag =
  | QuietFlag
  | AllowFailureFlag
  | AllowOutputFlag

(*
 * The command line has some flags,
 * and a string to be executed internally
 * or passed to the shell.
 *)
type ('exp, 'argv, 'value) poly_command_inst =
  | CommandEval   of 'exp list
  | CommandPipe   of 'argv
  | CommandValues of 'value list

type ('venv, 'exp, 'argv, 'value) poly_command_line =
   { command_loc    : Lm_location.loc;
     command_dir    : Omake_node.Dir.t;
     command_target : Omake_node.Node.t;
     command_flags  : command_flag list;
     command_venv   : 'venv;
     command_inst   : ('exp, 'argv, 'value) poly_command_inst
   }


let simple_string_of_arg arg =
  match arg with
  | [ArgString s]
  | [ArgData s] ->    s
  | _ ->
    let buf = Buffer.create 32 in
    List.iter
      (fun arg ->
        let s =
          match arg with
          | ArgString s -> s
          | ArgData s -> s in
        Buffer.add_string buf s) arg;
    Buffer.contents buf

let glob_string_of_arg options arg =
  let buf = Buffer.create 32 in
  List.iter (fun arg ->
      match arg with
        ArgString s ->
        Buffer.add_string buf s
      | ArgData s ->
        Lm_glob.glob_add_escaped options buf s) arg;
  Buffer.contents buf

let is_glob_arg options arg =
  List.exists (fun arg ->
      match arg with
      | ArgString s ->
        Lm_glob.is_glob_string options s
      | ArgData _ ->
        false) arg

let is_quoted_arg arg =
   List.exists (fun v ->
         match v with
            ArgString _ -> false
          | ArgData _ -> true) arg

let pp_arg_data_string =
   let special1 = "\" \t<>&;()*~{}[]?!|" in (* Can be protected both by '...c...' and \c *)
   let special2 = "\\\n\r'" in              (* Must be protected by \c *)
   let special_all = special1 ^ special2 in

   let rec pp_w_escapes buf special s =
      if Lm_string_util.contains_any s special then begin
         let i = Lm_string_util.index_set s special in
            Lm_printf.pp_print_string buf (String.sub s 0 i);
            Lm_printf.pp_print_char buf '\\';
            Lm_printf.pp_print_char buf (**)
               (match s.[i] with
                  '\n' -> 'n'
                | '\r' -> 'r'
                | '\t' -> 't'
                | c -> c);
            let i = i + 1 in
               pp_w_escapes buf special (String.sub s i (String.length s - i))

      end else
         Lm_printf.pp_print_string buf s
   in

   let pp_w_quotes buf s =
      if Lm_string_util.contains_any s special1 then
         if String.length s > 2 then begin
            Lm_printf.pp_print_char buf '\'';
            pp_w_escapes buf special2 s;
            Lm_printf.pp_print_char buf '\''
         end else
            pp_w_escapes buf special_all s
      else
         pp_w_escapes buf special2 s

   in
      pp_w_quotes

let pp_print_arg =
   let pp_print_arg_elem buf = function
      ArgString s ->
         Lm_printf.pp_print_string buf s
    | ArgData s ->
         pp_arg_data_string buf s
   in
      (fun buf arg -> List.iter (pp_print_arg_elem buf) arg)

let pp_print_verbose_arg buf arg =
   List.iter (fun arg ->
         match arg with
            ArgString s ->
               Lm_printf.pp_print_string buf s
          | ArgData s ->
               Format.fprintf buf "'%s'" s) arg

let pp_print_command_flag buf flag =
   let c =
      match flag with
         QuietFlag        -> '@'
       | AllowFailureFlag -> '-'
       | AllowOutputFlag  -> '*'
   in
      Lm_printf.pp_print_char buf c

let pp_print_command_flags buf flags =
   List.iter (pp_print_command_flag buf) flags

module type PrintArgvSig =
sig
   type argv

   val pp_print_argv : argv Lm_printf.t 
end;;

module MakePrintCommand (PrintArgv : PrintArgvSig) =
struct
   open PrintArgv

   let pp_print_command_inst buf inst =
      match inst with
         CommandPipe argv ->
            pp_print_argv buf argv
       | CommandEval exp ->
            Omake_ir_print.pp_print_exp_list_simple buf exp
       | CommandValues values ->
            Format.fprintf buf "<compute %i value dependencies>" (List.length values)

   let pp_print_command_line buf line =
      pp_print_command_inst buf line.command_inst

   let pp_print_command_lines buf lines =
      List.iter (fun line -> Format.fprintf buf "@ %a" pp_print_command_line line) lines
end;;
