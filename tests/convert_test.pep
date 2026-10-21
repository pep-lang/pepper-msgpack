# Struct conversion through both formats: the `serialize` attributes,
# every kind of property, round trips, and conversion errors at their path.

import msgpack.cbor;
import digest;
import json;
import msgpack;
import serialize;
import "support";

enum Level {
    Low,
    High,
}

[Tag("kind")]
enum Shape {
    Circle(radius: int),
    Point,
}

struct Inner {
    var name: String;
    var weights: Array<double>;
}

struct Record {
    [Required]
    var id: long;
    var small: i8;
    var count: u16;
    var big: ulong;
    var ratio: float;
    var active: bool;
    [Name("e-mail")]
    var email: String?;
    var limit: int?;
    var level: Level;
    var shape: Shape;
    var payload: u8[];
    var tags: Array<String>;
    var scores: HashMap<String, int>;
    var ordered: OrderedMap<String, Inner>;
    var inner: Inner;
    var missing: Inner;
    var raw: msgpack.Value;
    [Ignore]
    var cached: int;
}

make_record(): Record {
    var record = Record();
    record.id = -9000000000;
    record.small = -5;
    record.count = 65535;
    record.big = 0xffffffffffffffff;
    record.ratio = 0.25;
    record.active = true;
    record.email = Optional<String>.Value("ada@example.com");
    record.limit = Optional<int>.Empty;
    record.level = Level.High;
    record.shape = Shape.Circle(3);
    record.payload = [0 as u8, 1, 255];
    record.tags = ["a", "b"];
    record.scores = HashMap<String, int>();
    record.scores["x"] = 7;
    record.ordered = OrderedMap<String, Inner>();
    var first = Inner();
    first.name = "first";
    first.weights = [1.5, -2.0];
    record.ordered["one"] = first;
    record.inner = Inner();
    record.inner.name = "in";
    record.raw = msgpack.Value.Tag(1, msgpack.Value.Integer(2));
    record.cached = 99;
    return record;
}

expect_record(back: Record, location: __ptr<char> = __caller_location()) {
    expect_equal(back.id, -9000000000, location);
    expect_equal(back.small as int, -5, location);
    expect_equal(back.count as int, 65535, location);
    expect_equal(back.big, 0xffffffffffffffff, location);
    expect_equal(back.ratio, 0.25 as float, location);
    expect_true(back.active, location);
    expect_equal(back.email.value(), "ada@example.com", location);
    expect_true(back.limit.is_empty(), location);
    expect_true(back.level is High, location);
    expect_equal(json.encode(back.shape), "{\"kind\":\"Circle\",\"radius\":3}", location);
    expect_equal(digest.to_hex(back.payload), "0001ff", location);
    expect_equal(", ".join(back.tags), "a, b", location);
    expect_equal(back.scores["x"], 7, location);
    expect_equal(back.ordered["one"].name, "first", location);
    expect_equal(back.ordered["one"].weights[1], -2.0, location);
    expect_equal(back.inner.name, "in", location);
    expect_true(back.inner.weights.is_empty, location);
    expect_true(back.missing === __null, location);
    expect_equal(back.cached, 0, location);
}

[Test]
round_trips_a_struct_through_msgpack() {
    var bytes = msgpack.encode(make_record());
    expect_record(msgpack.decode<Record>(bytes).value());
    # The value keeps the struct's shape, with the attributes applied.
    var value = msgpack.decode<msgpack.Value>(bytes).value();
    expect_equal(value.get("e-mail").value().to_string(), "\"ada@example.com\"");
    expect_true(value.get("cached").is_empty());
    expect_equal(value.get("shape").value().to_string(), "{\"kind\": \"Circle\", \"radius\": 3}");
    expect_equal(value.get("level").value().to_string(), "\"High\"");
    expect_equal(value.get("payload").value().to_string(), "h'0001ff'");
    expect_equal(value.get("missing").value().to_string(), "null");
    expect_equal(value.get("raw").value().to_string(), "2");
}

[Test]
round_trips_a_struct_through_cbor() {
    var bytes = cbor.encode(make_record());
    expect_record(cbor.decode<Record>(bytes).value());
    var value = cbor.decode<cbor.Value>(bytes).value();
    expect_equal(value.get("raw").value().to_string(), "1(2)");
    expect_equal(value.get("big").value().to_string(), "18446744073709551615");
}

struct Point {
    var x: int;
    var y: int;
}

[Test]
encodes_a_struct_compactly() {
    var p = Point();
    p.x = 1;
    p.y = -1;
    expect_equal(digest.to_hex(msgpack.encode(p)), "82a17801a179ff");
    expect_equal(digest.to_hex(cbor.encode(p)), "a2617801617920");
    expect_equal(digest.to_hex(msgpack.encode([p, p])), "9282a17801a179ff82a17801a179ff");
}

# The error decoding MessagePack `text` (hexadecimal) into a `T` gives.
error_of<T>(text: String, unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore): String {
    var result = msgpack.decode<T>(bytes_of(text), unknown_keys);
    if (result.is_ok()) {
        return "no error";
    }
    return result.error().to_string();
}

[Test]
reports_conversion_errors_at_their_path() {
    # {"id": "x"}
    expect_equal(error_of<Record>("81a26964a178"), "$.id: expected an integer, found a string");
    # {}: id is required.
    expect_equal(error_of<Record>("80"), "$: missing required key 'id'");
    # {"id": 1, "small": 200}
    expect_equal(
        error_of<Record>("82a26964 01a5736d616c6ccc c8".replace(" ", "")), "$.small: 200 does not fit in 'i8'"
    );
    # {"id": 1, "tags": ["a", 2]}
    expect_equal(
        error_of<Record>("82a2696401a4746167739 2a16102".replace(" ", "")),
        "$.tags[1]: expected a string, found an integer"
    );
    # {"id": 1, "level": "Middle"}
    expect_equal(
        error_of<Record>("82a2696401a56c6576656ca64d6964646c65"), "$.level: 'Middle' is not a case of 'Level'"
    );
    # {"id": 1, "zzz": 1}, with unknown keys rejected.
    expect_equal(error_of<Record>("82a2696401a37a7a7a01", json.UnknownKeys.Reject), "$.zzz: unknown key 'zzz'");
    expect_equal(error_of<Record>("82a2696401a37a7a7a01"), "no error");
    # {"id": 1, 5: 1}: a struct's keys are strings.
    expect_equal(
        error_of<Record>("82a26964010501", json.UnknownKeys.Reject), "$: unknown key 5: a struct's keys are strings"
    );
    # A map for a scalar, and an array for a struct.
    expect_equal(error_of<int>("80"), "$: expected an integer, found a map");
    expect_equal(error_of<Point>("90"), "$: expected a map, found an array");
    expect_equal(error_of<HashMap<String, int>>("810101"), "$: expected a string key, found 1");
}

[Test]
reads_bytes_from_an_array_of_integers() {
    expect_equal(digest.to_hex(msgpack.decode<u8[]>(bytes_of("930102ccff")).value()), "0102ff");
    expect_equal(error_of<u8[]>("91cd0100"), "$[0]: 256 does not fit in 'u8'");
}
