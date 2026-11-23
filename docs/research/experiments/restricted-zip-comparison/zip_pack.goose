import std;
import os;
import gpack from "../../../../src/gpack";
import zip_writer;

fn fail(message: const u8[:]) { print(message); exit(1); }

fn main() {
    guard arg_count() == 4 else { print("usage: zip_pack STORE|DEFLATE INPUT_DIR OUTPUT.zip"); exit(2); }
    var mode:   u8[>..] = []; arg(1, mode);
    var input:  u8[>..] = []; arg(2, input);
    var output: u8[>..] = []; arg(3, output);
    let method = if mode == "STORE" { 0 } else if mode == "DEFLATE" { 8 } else { 0xffff };
    guard method != 0xffff else { fail("invalid ZIP method"); }
    guard zip_writer::pack_directory(input, output, method as u16) else { fail("ZIP packing failed"); }
    print("PACKED");
}
