# Decoding untrusted input: truncated, oversized, deeply nested and random
# bytes all give errors, never a panic or a huge allocation.

import msgpack.cbor;
import digest;
import msgpack;
import "support";

[Test]
rejects_every_truncation() {
    # A value of every MessagePack family, cut at each byte.
    var full = msgpack.encode(
        msgpack.decode<msgpack.Value>(
            bytes_of(
                "8aa161cd0100a162cb3ff199999999999aa163d90161a164c40201 02a165dc000201c3a166d6ff00000000a167d3ffffffffffffffffa168ca3fc00000a169c70301 0203a16adf00000001c0c0".replace(
                    " ",
                    ""
                )
            )
        ).value()
    );
    expect_true(msgpack.decode<msgpack.Value>(full).is_ok());
    for (var cut in 0..full.count) {
        var result = msgpack.decode<msgpack.Value>(full.slice(0, cut).to_array());
        expect_true(result.is_err());
    }
    # And a CBOR one, with tags, floats and indefinite lengths.
    var item = bytes_of(
        "bf6161c11a514b67b06162f93e0061637f6161626263ff61645f420102ff61659f01fb3ff199999999999aff6166f8ffff"
    );
    expect_true(cbor.decode<cbor.Value>(item).is_ok());
    for (var cut in 0..item.count) {
        expect_true(cbor.decode<cbor.Value>(item.slice(0, cut).to_array()).is_err());
    }
    expect_equal(msgpack_text(""), "byte 0: unexpected end of input");
    expect_equal(cbor_text("1a0001"), "byte 0: unexpected end of input: the item needs 4 more bytes, 2 remain");
}

[Test]
rejects_lengths_longer_than_the_input() {
    # 4 GB strings, byte strings and extensions in a few bytes.
    expect_equal(
        msgpack_text("dbffffffff"), "byte 0: unexpected end of input: the item needs 4294967295 more bytes, 0 remain"
    );
    expect_equal(
        msgpack_text("c6ffffffff00"), "byte 0: unexpected end of input: the item needs 4294967295 more bytes, 1 remain"
    );
    expect_equal(
        msgpack_text("c9ffffffff01"), "byte 0: unexpected end of input: the item needs 4294967295 more bytes, 0 remain"
    );
    # 4 G-item arrays and maps, which would reserve 32 GB if trusted.
    expect_equal(
        msgpack_text("ddffffffff"), "byte 0: an array or map of 4294967295 items is longer than the input left"
    );
    expect_equal(
        msgpack_text("dfffffffff0101"), "byte 0: an array or map of 4294967295 items is longer than the input left"
    );
    expect_equal(
        cbor_text("5affffffff"), "byte 0: unexpected end of input: the item needs 4294967295 more bytes, 0 remain"
    );
    expect_equal(
        cbor_text("7bffffffffffffffff"),
        "byte 0: unexpected end of input: the item needs 18446744073709551615 more bytes, 0 remain"
    );
    expect_equal(
        cbor_text("9bffffffffffffffff00"),
        "byte 0: an array or map of 18446744073709551615 items is longer than the input left"
    );
    expect_equal(
        cbor_text("bb7fffffffffffffff0000"),
        "byte 0: an array or map of 9223372036854775807 items is longer than the input left"
    );
    # Within an indefinite-length string, each chunk is checked too.
    expect_equal(
        cbor_text("5f5affffffff"), "byte 1: unexpected end of input: the item needs 4294967295 more bytes, 0 remain"
    );
}

[Test]
caps_nesting() {
    var deep = "91".repeat(300) + "c0";
    expect_equal(msgpack_text(deep), "byte 257: items nest deeper than 256 levels");
    expect_equal(msgpack_text("91".repeat(256) + "c0"), "[".repeat(256) + "null" + "]".repeat(256));
    expect_equal(msgpack_text("8101".repeat(5) + "c0", max_depth = 4), "byte 9: items nest deeper than 4 levels");
    expect_equal(cbor_text("81".repeat(100000) + "f6"), "byte 257: items nest deeper than 256 levels");
    expect_equal(cbor_text("9f".repeat(1000)), "byte 257: items nest deeper than 256 levels");
    expect_equal(cbor_text("c1".repeat(1000) + "00"), "byte 257: items nest deeper than 256 levels");
    expect_equal(cbor_text("a1".repeat(300) + "00"), "byte 257: items nest deeper than 256 levels");
}

[Test]
rejects_malformed_input() {
    expect_equal(msgpack_text("c1"), "byte 0: 0xc1 is never used in MessagePack");
    expect_equal(msgpack_text("a2c328"), "byte 0: a string is not valid UTF-8");
    expect_equal(msgpack_text("c0c0"), "byte 1: unexpected data after the value");
    expect_equal(msgpack_text("92c0"), "byte 0: an array or map of 2 items is longer than the input left");
    expect_equal(msgpack_text("9291c0"), "byte 3: unexpected end of input");
}

# A pseudo-random generator, so the test is the same each run.
struct Lcg {
    var state: ulong;

    next(): ulong {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        return state >> 33;
    }
}

[Test]
survives_random_input() {
    var random = Lcg();
    random.state = 42;
    var decoded = 0;
    for (var round in 0..3000) {
        var size = random.next() % 24;
        var bytes = Array<u8>(size);
        for (var index in 0..size) {
            bytes.append((random.next() & 0xff) as u8);
        }
        if (msgpack.decode<msgpack.Value>(bytes).is_ok()) {
            decoded = decoded + 1;
        }
        if (cbor.decode<cbor.Value>(bytes).is_ok()) {
            decoded = decoded + 1;
        }
    }
    # Some random inputs are well formed; none panics.
    expect_true(decoded > 0);
}
