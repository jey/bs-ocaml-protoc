(*
  The MIT License (MIT)
  
  Copyright (c) 2016 Maxime Ransan <maxime.ransan@gmail.com>
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

*)

module E = Pb_exception
module Ot = Pb_codegen_ocaml_type 
module F = Pb_codegen_formatting
module Codegen_util = Pb_codegen_util 
module Cmdline = Ocaml_protoc_cmdline.Cmdline

type codegen_f = ?and_:unit -> Ot.type_ -> F.scope -> bool 

let generate_for_all_types ocaml_types sc (f:codegen_f) ocamldoc_title = 
  begin
    match ocamldoc_title with
    | None -> () 
    | Some ocamldoc_title -> ( 
      F.empty_line sc;
      F.linep sc "(** {2 %s} *)" ocamldoc_title;  
      F.empty_line sc;
    )
  end;

  List.iter (fun types -> 
    let _:bool = List.fold_left (fun first type_ -> 
      let has_encoded = if first 
        then f type_ sc 
        else f ~and_:() type_ sc
      in 
      F.empty_line sc;
      first && (not has_encoded) 
    ) true types in 
    ()
  ) ocaml_types 

let open_files cmdline file_suffix = 
  let {
    Cmdline.ml_out; 
    Cmdline.proto_file_name; _} = cmdline in 

  let out_file_name = 
    let proto_file_name = Filename.basename proto_file_name in
    let out_basename = 
      Codegen_util.caml_file_name_of_proto_file_name 
        ~proto_file_name ~file_suffix
    in 
    Filename.concat ml_out out_basename
  in 
  
  Printf.printf "Generating %s.mli\n%!" out_file_name; 
  Printf.printf "Generating %s.ml\n%!"  out_file_name; 

  (open_out @@ out_file_name ^ ".mli" , open_out @@ out_file_name ^ ".ml")

let generate_type_and_default 
       ocaml_types proto_file_options cmdline = 

  let file_suffix = "types" in 

  let print_ppx sc = 
    match Pb_option.get proto_file_options "ocaml_file_ppx" with
    | None -> () 
    | Some Pb_option.Constant_string s -> 
      F.linep sc "[@@@%s]" s
    | _ -> E.invalid_ppx_extension_option cmdline.Cmdline.proto_file_name  
  in 

  (* .ml file *) 
  let ml_sc = F.empty_scope () in 
  F.line ml_sc "[@@@ocaml.warning \"-27-30-39\"]";
  F.empty_line ml_sc; 
  print_ppx ml_sc; 
  F.empty_line ml_sc;
  generate_for_all_types ocaml_types ml_sc Pb_codegen_types.gen_struct None;
  generate_for_all_types ocaml_types ml_sc Pb_codegen_default.gen_struct None;

  (* .mli file *)
  let mli_sc = F.empty_scope () in 
  F.linep mli_sc "(** %s Types *)" 
    (Filename.basename cmdline.Cmdline.proto_file_name); 
  F.empty_line mli_sc; 
  print_ppx mli_sc; 
  F.empty_line mli_sc;
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_types.gen_sig 
    (Some Pb_codegen_types.ocamldoc_title);
  generate_for_all_types ocaml_types mli_sc
    Pb_codegen_default.gen_sig 
    (Some Pb_codegen_default.ocamldoc_title);

  let sig_oc, struct_oc = open_files cmdline file_suffix in 
  output_string struct_oc (F.print ml_sc);
  output_string sig_oc (F.print mli_sc)

let generate_mutable_records gen_file_suffix ocaml_types sc = 
  let ocaml_types = List.flatten ocaml_types in 
  List.iter (fun {Ot.spec; module_prefix; _ } -> 
    match spec with
    | Ot.Record r -> 
      Pb_codegen_types.gen_record_mutable module_prefix r sc;
      F.empty_line sc;
      Pb_codegen_default.gen_record_mutable 
        ~gen_file_suffix ~module_prefix r sc; 
      F.empty_line sc;
    | _ -> () 
  ) ocaml_types

let generate_yojson ocaml_types cmdline = 
  let file_suffix = "yojson" in 

  (* .ml file *) 
  let ml_sc = F.empty_scope () in 
  F.line ml_sc "[@@@ocaml.warning \"-27-30-39\"]";
  F.empty_line ml_sc;
  generate_mutable_records file_suffix ocaml_types ml_sc;
  F.empty_line ml_sc;

  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_decode_yojson.gen_struct None; 
  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_encode_yojson.gen_struct None; 
  
  (* .mli file *)
  let mli_sc = F.empty_scope () in 
  F.linep mli_sc 
        "(** %s YoJSON Encoding *)" 
        (Filename.basename cmdline.Cmdline.proto_file_name); 
  F.empty_line mli_sc; 
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_encode_yojson.gen_sig 
    (Some Pb_codegen_encode_yojson.ocamldoc_title);
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_decode_yojson.gen_sig 
    (Some Pb_codegen_decode_yojson.ocamldoc_title);

  let sig_oc, struct_oc = open_files cmdline file_suffix in 
  output_string struct_oc (F.print ml_sc);
  output_string sig_oc (F.print mli_sc)

let generate_bs ocaml_types cmdline = 
  let file_suffix = "bs" in 

  (* .ml file *) 
  let ml_sc = F.empty_scope () in 
  F.line ml_sc "[@@@ocaml.warning \"-27-30-39\"]";
  F.empty_line ml_sc;
  generate_mutable_records file_suffix ocaml_types ml_sc;
  F.empty_line ml_sc;

  F.line ml_sc "module Decode = struct";
  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_decode_bs.gen_struct None; 
  F.line ml_sc "end";
  F.empty_line ml_sc;
  F.line ml_sc "module Encode = struct";
  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_encode_bs.gen_struct None; 
  F.line ml_sc "end";
  
  (* .mli file *)
  let mli_sc = F.empty_scope () in 
  F.linep mli_sc 
        "(** %s BuckleScript Encoding *)" 
        (Filename.basename cmdline.Cmdline.proto_file_name); 
  F.empty_line mli_sc; 
  F.line mli_sc "module Encode : sig";
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_encode_bs.gen_sig 
    (Some Pb_codegen_encode_bs.ocamldoc_title);
  F.line mli_sc "end";
  F.empty_line mli_sc;
  F.line mli_sc "module Decode : sig";
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_decode_bs.gen_sig 
    (Some Pb_codegen_decode_bs.ocamldoc_title);
  F.line mli_sc "end";
  
  let sig_oc, struct_oc = open_files cmdline file_suffix in 
  output_string struct_oc (F.print ml_sc);
  output_string sig_oc (F.print mli_sc)

let generate_binary ocaml_types cmdline =
  let file_suffix = "pb" in 

  (* .ml file *) 
  let ml_sc = F.empty_scope () in 
  F.line ml_sc "[@@@ocaml.warning \"-27-30-39\"]";
  F.empty_line ml_sc;
  generate_mutable_records file_suffix ocaml_types ml_sc;
  F.empty_line ml_sc;

  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_decode_binary.gen_struct None; 
  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_encode_binary.gen_struct None; 
  
  (* .mli file *)
  let mli_sc = F.empty_scope () in 
  F.linep mli_sc 
        "(** %s Binary Encoding *)" 
        (Filename.basename cmdline.Cmdline.proto_file_name); 
  F.empty_line mli_sc; 
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_encode_binary.gen_sig 
    (Some Pb_codegen_encode_binary.ocamldoc_title);
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_decode_binary.gen_sig 
    (Some Pb_codegen_decode_binary.ocamldoc_title);

  let sig_oc, struct_oc = open_files cmdline file_suffix in 
  output_string struct_oc (F.print ml_sc);
  output_string sig_oc (F.print mli_sc)

let generate_pp ocaml_types cmdline =
  let file_suffix = "pp" in 

  (* .ml file *) 
  let ml_sc = F.empty_scope () in 
  F.line ml_sc "[@@@ocaml.warning \"-27-30-39\"]";
  F.empty_line ml_sc;

  generate_for_all_types ocaml_types ml_sc 
    Pb_codegen_pp.gen_struct None; 
  
  (* .mli file *)
  let mli_sc = F.empty_scope () in 
  F.linep mli_sc 
    "(** %s Pretty Printing *)" 
    (Filename.basename cmdline.Cmdline.proto_file_name); 
  F.empty_line mli_sc; 
  generate_for_all_types ocaml_types mli_sc 
    Pb_codegen_pp.gen_sig 
    (Some Pb_codegen_pp.ocamldoc_title);

  let sig_oc, struct_oc = open_files cmdline file_suffix in 
  output_string struct_oc (F.print ml_sc);
  output_string sig_oc (F.print mli_sc)

let generate_code ocaml_types proto_file_options cmdline = 

  generate_type_and_default 
    ocaml_types proto_file_options cmdline;

  begin if !(cmdline.Cmdline.yojson)  
  then generate_yojson ocaml_types cmdline 
  end; 
  
  begin if !(cmdline.Cmdline.binary)
  then generate_binary ocaml_types cmdline
  end; 
  
  begin if !(cmdline.Cmdline.pp)
  then generate_pp ocaml_types cmdline
  end; 
  
  begin if !(cmdline.Cmdline.bs)
  then generate_bs ocaml_types cmdline
  end; 
  ()
