# The msgpack package's format: every family of the MessagePack spec's
# formats, written in the shortest form and read back, and the dynamic
# `Value`.

import digest;
import msgpack;
import "support";

# `value` encoded, in hexadecimal.
hex_of(value: msgpack.Value): String {
    return digest.to_hex(msgpack.encode(value));
}

# Checks that `value` encodes to `text` and that `text` decodes back to
# `diagnostic`.
check_msgpack(value: msgpack.Value, text: String, diagnostic: String, location: __ptr<char> = __caller_location()) {
    expect_equal(hex_of(value), text, location);
    expect_equal(msgpack_text(text), diagnostic, location);
}

[Test]
writes_and_reads_integers() {
    check_msgpack(msgpack.Value.Integer(0), "00", "0");
    check_msgpack(msgpack.Value.Integer(127), "7f", "127");
    check_msgpack(msgpack.Value.Integer(128), "cc80", "128");
    check_msgpack(msgpack.Value.Integer(255), "ccff", "255");
    check_msgpack(msgpack.Value.Integer(256), "cd0100", "256");
    check_msgpack(msgpack.Value.Integer(65535), "cdffff", "65535");
    check_msgpack(msgpack.Value.Integer(65536), "ce00010000", "65536");
    check_msgpack(msgpack.Value.Integer(4294967295), "ceffffffff", "4294967295");
    check_msgpack(msgpack.Value.Integer(4294967296), "cf0000000100000000", "4294967296");
    check_msgpack(msgpack.Value.Unsigned(0xffffffffffffffff), "cfffffffffffffffff", "18446744073709551615");
    check_msgpack(msgpack.Value.Integer(-1), "ff", "-1");
    check_msgpack(msgpack.Value.Integer(-32), "e0", "-32");
    check_msgpack(msgpack.Value.Integer(-33), "d0df", "-33");
    check_msgpack(msgpack.Value.Integer(-128), "d080", "-128");
    check_msgpack(msgpack.Value.Integer(-129), "d1ff7f", "-129");
    check_msgpack(msgpack.Value.Integer(-32768), "d18000", "-32768");
    check_msgpack(msgpack.Value.Integer(-32769), "d2ffff7fff", "-32769");
    check_msgpack(msgpack.Value.Integer(-2147483648), "d280000000", "-2147483648");
    check_msgpack(msgpack.Value.Integer(-2147483649), "d3ffffffff7fffffff", "-2147483649");
    check_msgpack(msgpack.Value.Integer(-9223372036854775807 - 1), "d38000000000000000", "-9223372036854775808");
    # Wider forms than needed read too.
    expect_equal(msgpack_text("cd0001"), "1");
    expect_equal(msgpack_text("d3ffffffffffffffff"), "-1");
    expect_equal(msgpack_text("cf7fffffffffffffff"), "9223372036854775807");
}

[Test]
writes_and_reads_nil_booleans_and_floats() {
    check_msgpack(msgpack.Value.Null, "c0", "null");
    check_msgpack(msgpack.Value.Bool(false), "c2", "false");
    check_msgpack(msgpack.Value.Bool(true), "c3", "true");
    check_msgpack(msgpack.Value.Float(1.5), "ca3fc00000", "1.5");
    check_msgpack(msgpack.Value.Float(0.1), "cb3fb999999999999a", "0.1");
    check_msgpack(msgpack.Value.Float(-0.0), "ca80000000", "-0.0");
    check_msgpack(msgpack.Value.Float(1.0 / 0.0), "ca7f800000", "Infinity");
    expect_equal(msgpack_text("cb7ff8000000000000"), "NaN");
}

[Test]
writes_and_reads_strings_and_binary() {
    check_msgpack(msgpack.Value.String(""), "a0", "\"\"");
    check_msgpack(msgpack.Value.String("a"), "a161", "\"a\"");
    check_msgpack(msgpack.Value.String("ü"), "a2c3bc", "\"ü\"");
    var thirty_one = "x".repeat(31);
    expect_equal(hex_of(msgpack.Value.String(thirty_one)), "bf" + "78".repeat(31));
    var thirty_two = "x".repeat(32);
    expect_equal(hex_of(msgpack.Value.String(thirty_two)), "d920" + "78".repeat(32));
    expect_equal(hex_of(msgpack.Value.String("x".repeat(256))).substr_bytes(0, 6), "da0100");
    expect_equal(hex_of(msgpack.Value.String("x".repeat(65536))).substr_bytes(0, 10), "db00010000");
    expect_equal(msgpack_text("d90178"), "\"x\"");
    expect_equal(msgpack_text("da000178"), "\"x\"");
    expect_equal(msgpack_text("db0000000178"), "\"x\"");

    check_msgpack(msgpack.Value.Binary(Array<u8>()), "c400", "h''");
    check_msgpack(msgpack.Value.Binary([1 as u8, 2]), "c4020102", "h'0102'");
    expect_equal(hex_of(msgpack.Value.Binary(bytes_of("00".repeat(256)))).substr_bytes(0, 6), "c50100");
    expect_equal(msgpack_text("c500020102"), "h'0102'");
    expect_equal(msgpack_text("c6000000020102"), "h'0102'");
}

[Test]
writes_and_reads_arrays_and_maps() {
    var items = Array<msgpack.Value>();
    check_msgpack(msgpack.Value.Array(items), "90", "[]");
    items.append(msgpack.Value.Integer(1));
    items.append(msgpack.Value.String("a"));
    check_msgpack(msgpack.Value.Array(items), "9201a161", "[1, \"a\"]");
    var many = Array<msgpack.Value>();
    for (var index in 0..16) {
        many.append(msgpack.Value.Null);
    }
    check_msgpack(msgpack.Value.Array(many), "dc0010" + "c0".repeat(16), "[" + "null, ".repeat(15) + "null]");
    expect_equal(msgpack_text("dd0000000101"), "[1]");

    var entries = Array<(msgpack.Value, msgpack.Value)>();
    check_msgpack(msgpack.Value.Map(entries), "80", "{}");
    entries.append((msgpack.Value.Integer(1), msgpack.Value.Bool(true)));
    entries.append((msgpack.Value.String("k"), msgpack.Value.Array(items)));
    check_msgpack(msgpack.Value.Map(entries), "8201c3a16b9201a161", "{1: true, \"k\": [1, \"a\"]}");
    expect_equal(msgpack_text("de00010102"), "{1: 2}");
    expect_equal(msgpack_text("df000000010102"), "{1: 2}");
}

[Test]
writes_and_reads_extensions() {
    check_msgpack(msgpack.Value.Extension(1, [0xaa as u8]), "d401aa", "ext(1, h'aa')");
    check_msgpack(msgpack.Value.Extension(-1, bytes_of("00000000")), "d6ff00000000", "ext(-1, h'00000000')");
    check_msgpack(msgpack.Value.Extension(2, bytes_of("0102")), "d5020102", "ext(2, h'0102')");
    check_msgpack(
        msgpack.Value.Extension(3, bytes_of("00".repeat(8))), "d703" + "00".repeat(8), "ext(3, h'0000000000000000')"
    );
    check_msgpack(
        msgpack.Value.Extension(4, bytes_of("00".repeat(16))), "d804" + "00".repeat(16), $"ext(4, h'{"00".repeat(16)}')"
    );
    check_msgpack(msgpack.Value.Extension(5, bytes_of("010203")), "c70305010203", "ext(5, h'010203')");
    check_msgpack(msgpack.Value.Extension(6, Array<u8>()), "c70006", "ext(6, h'')");
    expect_equal(msgpack_text("c800010701"), "ext(7, h'01')");
    expect_equal(msgpack_text("c90000000108ff"), "ext(8, h'ff')");
}

[Test]
writes_cbor_only_cases_as_their_nearest() {
    expect_equal(hex_of(msgpack.Value.Undefined), "c0");
    expect_equal(hex_of(msgpack.Value.Simple(16)), "c0");
    expect_equal(hex_of(msgpack.Value.Tag(1, msgpack.Value.Integer(5))), "05");
    expect_equal(msgpack_text(hex_of(msgpack.Value.Negative(0xffffffffffffffff))), "-1.8446744073709552e+19");
}

[Test]
looks_up_map_members() {
    var value = msgpack.decode<msgpack.Value>(bytes_of("82a16101a16292c3c0")).value();
    expect_equal(value.get("a").value().to_string(), "1");
    expect_equal(value.get("b").value().to_string(), "[true, null]");
    expect_true(value.get("c").is_empty());
    expect_true(msgpack.Value.Integer(1).get("a").is_empty());
}
