import gpack from "../src/gpack";

fn main() {
    let value: u64 = 0x123456789abcdef0;
    assert(gpack::gpack_native_abi_probe(value) == value);
    assert(gpack::gpack_native_zstd_version() == 10507);
}
