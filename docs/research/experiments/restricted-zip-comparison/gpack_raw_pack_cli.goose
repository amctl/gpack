import std;
import os;
import gpack from "../../../../src/gpack";
import gpack_raw_pack;

fn main() {
    guard arg_count() == 3 else { print("usage: gpack_raw_pack INPUT_DIR OUTPUT.gpk"); exit(2); }
    var input: u8[>..] = []; arg(1, input);
    var output: u8[>..] = []; arg(2, output);
    guard gpack_raw_pack::pack(input, output) else { print("raw GPack packing failed"); exit(1); }
    print("PACKED");
}
