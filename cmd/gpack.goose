import gpack from "../src/gpack";
import gpack.pack;
import gpack.reader;
import os;

fn main() {
    let arguments = args();
    if arguments.len == 4 && arguments[1] == "pack" {
        if !pack::pack_directory(arguments[2], arguments[3]) {
            write_stderr("gpack: pack failed (invalid input, I/O error, or source changed)\n");
            exit(1);
        }
    } else if arguments.len == 3 && arguments[1] == "list" {
        if !reader::list(arguments[2]) {
            write_stderr("gpack: cannot read or validate archive\n");
            exit(1);
        }
    } else if arguments.len == 3 && arguments[1] == "verify" {
        if !reader::verify(arguments[2]) {
            write_stderr("gpack: verification failed\n");
            exit(1);
        }
    } else {
        write_stderr("usage: gpack pack INPUT_DIR OUTPUT.gpk | list ARCHIVE.gpk | verify ARCHIVE.gpk\n");
        exit(2);
    }
}
