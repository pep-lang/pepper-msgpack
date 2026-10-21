# The cbor module against RFC 8949's Appendix A: each example decodes to its
# diagnostic notation, and those in preferred serialization encode back to
# the same bytes.

import msgpack.cbor;
import digest;
import text;
import "support";

# Checks that `text` decodes to `diagnostic` and encodes back to `text`.
check_cbor(text: String, diagnostic: String, location: __ptr<char> = __caller_location()) {
    var value = cbor.decode<cbor.Value>(bytes_of(text));
    if (value.is_err()) {
        panic($"{text}: {value.error().to_string()}", location);
    }
    expect_equal(value.value().to_string(), diagnostic, location);
    expect_equal(digest.to_hex(cbor.encode(value.value())), text, location);
}

# Checks that `n` encodes to `text` and that `text` decodes to `n`, bit for
# bit.
check_float(n: double, text: String, location: __ptr<char> = __caller_location()) {
    expect_equal(digest.to_hex(cbor.encode(n)), text, location);
    expect_float(text, n, location);
}

# Checks that `text` decodes to the float `n`, bit for bit.
expect_float(text: String, n: double, location: __ptr<char> = __caller_location()) {
    var value = cbor.decode<double>(bytes_of(text)).value();
    expect_equal(unsafe_cast<ulong>(value), unsafe_cast<ulong>(n), location);
}

[Test]
reads_and_writes_integers() {
    check_cbor("00", "0");
    check_cbor("01", "1");
    check_cbor("0a", "10");
    check_cbor("17", "23");
    check_cbor("1818", "24");
    check_cbor("1819", "25");
    check_cbor("1864", "100");
    check_cbor("1903e8", "1000");
    check_cbor("1a000f4240", "1000000");
    check_cbor("1b000000e8d4a51000", "1000000000000");
    check_cbor("1bffffffffffffffff", "18446744073709551615");
    check_cbor("c249010000000000000000", "2(h'010000000000000000')");
    check_cbor("3bffffffffffffffff", "-18446744073709551616");
    check_cbor("c349010000000000000000", "3(h'010000000000000000')");
    check_cbor("20", "-1");
    check_cbor("29", "-10");
    check_cbor("3863", "-100");
    check_cbor("3903e7", "-1000");
    check_cbor("3b7fffffffffffffff", "-9223372036854775808");
    check_cbor("3b8000000000000000", "-9223372036854775809");
}

[Test]
reads_and_writes_floats() {
    check_float(0.0, "f90000");
    check_float(-0.0, "f98000");
    check_float(1.0, "f93c00");
    check_float(1.1, "fb3ff199999999999a");
    check_float(1.5, "f93e00");
    check_float(65504.0, "f97bff");
    check_float(100000.0, "fa47c35000");
    check_float(3.4028234663852886e+38, "fa7f7fffff");
    check_float(1.0e+300, "fb7e37e43c8800759c");
    check_float(5.960464477539063e-8, "f90001");
    check_float(0.00006103515625, "f90400");
    check_float(-4.0, "f9c400");
    check_float(-4.1, "fbc010666666666666");
    var infinity = 1.0 / 0.0;
    check_float(infinity, "f97c00");
    check_float(-infinity, "f9fc00");
    expect_equal(digest.to_hex(cbor.encode(0.0 / 0.0)), "f97e00");
    expect_equal(cbor_text("f97e00"), "NaN");
    # The wider forms of the same values read too.
    expect_float("fa7f800000", infinity);
    expect_float("faff800000", -infinity);
    expect_float("fb7ff0000000000000", infinity);
    expect_float("fbfff0000000000000", -infinity);
    expect_equal(cbor_text("fa7fc00000"), "NaN");
    expect_equal(cbor_text("fb7ff8000000000000"), "NaN");
    # Half subnormals other than the smallest, and a single that a half
    # cannot hold.
    check_float(5.960464477539063e-8 * 3.0, "f90003");
    check_float(0.00006097555160522461, "f903ff");
    check_float(1.0 / 3.0, "fb3fd5555555555555");
    check_float(((1.0 / 3.0) as float) as double, "fa3eaaaaab");
}

[Test]
reads_and_writes_simple_values() {
    check_cbor("f4", "false");
    check_cbor("f5", "true");
    check_cbor("f6", "null");
    check_cbor("f7", "undefined");
    check_cbor("f0", "simple(16)");
    check_cbor("f8ff", "simple(255)");
    # 20 to 31 are not simple values of their own.
    expect_equal(digest.to_hex(cbor.encode(cbor.Value.Simple(19))), "f3");
    expect_equal(digest.to_hex(cbor.encode(cbor.Value.Simple(20))), "f7");
    expect_equal(digest.to_hex(cbor.encode(cbor.Value.Simple(31))), "f7");
    expect_equal(digest.to_hex(cbor.encode(cbor.Value.Simple(32))), "f820");
}

[Test]
reads_and_writes_tags() {
    check_cbor("c074323031332d30332d32315432303a30343a30305a", "0(\"2013-03-21T20:04:00Z\")");
    check_cbor("c11a514b67b0", "1(1363896240)");
    check_cbor("c1fb41d452d9ec200000", "1(1363896240.5)");
    check_cbor("d74401020304", "23(h'01020304')");
    check_cbor("d818456449455446", "24(h'6449455446')");
    check_cbor("d82076687474703a2f2f7777772e6578616d706c652e636f6d", "32(\"http://www.example.com\")");
}

[Test]
reads_and_writes_strings() {
    check_cbor("40", "h''");
    check_cbor("4401020304", "h'01020304'");
    check_cbor("60", "\"\"");
    check_cbor("6161", "\"a\"");
    check_cbor("6449455446", "\"IETF\"");
    check_cbor("62225c", "\"\\\"\\\\\"");
    check_cbor("62c3bc", "\"ü\"");
    check_cbor("63e6b0b4", "\"水\"");
    check_cbor("64f0908591", "\"" + text.Utf8.decode_lossy(bytes_of("f0908591")) + "\"");
}

[Test]
reads_and_writes_arrays_and_maps() {
    check_cbor("80", "[]");
    check_cbor("83010203", "[1, 2, 3]");
    check_cbor("8301820203820405", "[1, [2, 3], [4, 5]]");
    var one_to_25 = "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]";
    check_cbor("98190102030405060708090a0b0c0d0e0f101112131415161718181819", one_to_25);
    check_cbor("a0", "{}");
    check_cbor("a201020304", "{1: 2, 3: 4}");
    check_cbor("a26161016162820203", "{\"a\": 1, \"b\": [2, 3]}");
    check_cbor("826161a161626163", "[\"a\", {\"b\": \"c\"}]");
    check_cbor(
        "a56161614161626142616361436164614461656145",
        "{\"a\": \"A\", \"b\": \"B\", \"c\": \"C\", \"d\": \"D\", \"e\": \"E\"}"
    );
}

[Test]
reads_indefinite_lengths() {
    expect_equal(cbor_text("5f42010243030405ff"), "h'0102030405'");
    expect_equal(cbor_text("7f657374726561646d696e67ff"), "\"streaming\"");
    expect_equal(cbor_text("9fff"), "[]");
    expect_equal(cbor_text("9f018202039f0405ffff"), "[1, [2, 3], [4, 5]]");
    expect_equal(cbor_text("9f01820203820405ff"), "[1, [2, 3], [4, 5]]");
    expect_equal(cbor_text("83018202039f0405ff"), "[1, [2, 3], [4, 5]]");
    expect_equal(cbor_text("83019f0203ff820405"), "[1, [2, 3], [4, 5]]");
    var one_to_25 = "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]";
    expect_equal(cbor_text("9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff"), one_to_25);
    expect_equal(cbor_text("bf61610161629f0203ffff"), "{\"a\": 1, \"b\": [2, 3]}");
    expect_equal(cbor_text("826161bf61626163ff"), "[\"a\", {\"b\": \"c\"}]");
    expect_equal(cbor_text("bf6346756ef563416d7421ff"), "{\"Fun\": true, \"Amt\": -2}");
    expect_equal(cbor_text("5fff"), "h''");
}

[Test]
rejects_malformed_items() {
    expect_equal(cbor_text("1c"), "byte 0: additional information 28 is reserved");
    expect_equal(cbor_text("1f"), "byte 0: major type 0 has no indefinite length");
    expect_equal(cbor_text("df"), "byte 0: major type 6 has no indefinite length");
    expect_equal(cbor_text("fc"), "byte 0: additional information 28 is reserved");
    expect_equal(cbor_text("ff"), "byte 0: 'break' outside an indefinite-length item");
    expect_equal(cbor_text("f818"), "byte 0: simple value 24 must be written in the initial byte");
    expect_equal(
        cbor_text("5f01ff"), "byte 1: a chunk of an indefinite-length string must be a definite string of its type"
    );
    expect_equal(
        cbor_text("7f4161ff"), "byte 1: a chunk of an indefinite-length string must be a definite string of its type"
    );
    expect_equal(
        cbor_text("5f5f4101ffff"),
        "byte 1: a chunk of an indefinite-length string must be a definite string of its type"
    );
    expect_equal(cbor_text("bf6161ff"), "byte 0: an indefinite-length map ends after a key, with no value");
    expect_equal(cbor_text("62c328"), "byte 0: a string is not valid UTF-8");
    expect_equal(cbor_text("0001"), "byte 1: unexpected data after the value");
}
