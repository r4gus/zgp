//! OpenPGP's Radix-64 encoding is used to prevent damage caused by
//! character set translation, data conversions, etc. It is composed
//! of two parts: a base64 encoding of the binary data and a checksum.

/// A 24-bit checksum
pub const Crc24 = u24;

/// Calculate a 24-bit checksum for the given binary data
///
/// # Arguments
/// - `octets` - A slice of octets
pub fn crcFromOctets(octets: []const u8) Crc24 {
    const CRC24_INIT = 0xB704CE;
    const CRC24_POLY = 0x1864CFB;

    var crc: u32 = CRC24_INIT;
    for (octets) |octet| {
        crc ^= (octet << 16);

        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            crc <<= 1;
            if (crc & 0x1000000) crc ^= CRC24_POLY;
        }
    }

    return @intCast(Crc24, crc & 0xFFFFFF);
}

/// Encode the given input data into Radix-64
///
/// # Arguments
/// - `out` - A writer
/// - `in` - A slice of octets
pub fn encode(out: anytype, in: []const u8) !void {
    var i: usize = 0;

    while (i < in.len) : (i += 3) {
        const rem: usize = in.len - i;
        var x: [4]u8 = .{ 0, 0, 0, 0 };

        // +--first octet--+-second octet--+--third octet--+
        // |7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|
        // +-----------+---+-------+-------+---+-----------+
        // |5 4 3 2 1 0|5 4 3 2 1 0|5 4 3 2 1 0|5 4 3 2 1 0|
        // +--1.index--+--2.index--+--3.index--+--4.index--+
        if (rem == 2) {
            x[0] = indexToEnc(@intCast(u6, in[i] >> 2));
            x[1] = indexToEnc(@intCast(u6, ((in[i] & 0b11) << 4) | (in[i + 1] >> 4)));
            x[2] = indexToEnc(@intCast(u6, ((in[i + 1] & 0xF) << 2)));
            x[3] = '=';
        } else if (rem == 1) {
            x[0] = indexToEnc(@intCast(u6, in[i] >> 2));
            x[1] = indexToEnc(@intCast(u6, ((in[i] & 0b11) << 4)));
            x[2] = '=';
            x[3] = '=';
        } else {
            x[0] = indexToEnc(@intCast(u6, in[i] >> 2));
            x[1] = indexToEnc(@intCast(u6, ((in[i] & 0b11) << 4) | (in[i + 1] >> 4)));
            x[2] = indexToEnc(@intCast(u6, ((in[i + 1] & 0xF) << 2) | (in[i + 2] >> 6)));
            x[3] = indexToEnc(@intCast(u6, (in[i + 2] & 0x3F)));
        }

        try out.writeAll(x[0..]);
    }
}

/// Decode the given input data form Radix-64 into octets
///
/// # Arguments
/// - `out` - A writer
/// - `in` - A slice of Radix-64 data
pub fn decode(out: anytype, in: []const u8) !void {
    if (@mod(in.len, 4) != 0) return error.InvalidInputLength;

    const l: usize = if (in[in.len - 2] == '=')
        in.len - 2
    else if (in[in.len - 1] == '=')
        in.len - 1
    else
        in.len;

    var i: usize = 0;
    while (i < l) : (i += 4) {
        var x: [3]u8 = .{ 0, 0, 0 };
        var xl: usize = 3;
        const rem: usize = l - i;

        // +--first octet--+-second octet--+--third octet--+
        // |7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|
        // +-----------+---+-------+-------+---+-----------+
        // |5 4 3 2 1 0|5 4 3 2 1 0|5 4 3 2 1 0|5 4 3 2 1 0|
        // +--1.index--+--2.index--+--3.index--+--4.index--+
        if (rem == 3) {
            x[0] = try encToIndex(in[i]) << 2 | try encToIndex(in[i + 1]) >> 4;
            x[1] = try encToIndex(in[i + 1]) << 4 | try encToIndex(in[i + 2]) >> 2;
            x[2] = try encToIndex(in[i + 2]) << 6;
            xl = 2;
        } else if (rem == 2) {
            x[0] = try encToIndex(in[i]) << 2 | try encToIndex(in[i + 1]) >> 4;
            x[1] = try encToIndex(in[i + 1]) << 4;
            xl = 1;
        } else if (rem == 1) {
            x[0] = try encToIndex(in[i]) << 2;
            xl = 1;
        } else {
            x[0] = try encToIndex(in[i]) << 2 | try encToIndex(in[i + 1]) >> 4;
            x[1] = try encToIndex(in[i + 1]) << 4 | try encToIndex(in[i + 2]) >> 2;
            x[2] = try encToIndex(in[i + 2]) << 6 | try encToIndex(in[i + 3]);
        }

        try out.writeAll(x[0..xl]);
    }
}

fn indexToEnc(idx: u6) u8 {
    return switch (idx) {
        0...25 => |i| 0x41 + @intCast(u8, i),
        26...51 => |i| 0x61 + @intCast(u8, i) - 26,
        52...61 => |i| 0x30 + @intCast(u8, i) - 52,
        62 => '+',
        63 => '/',
    };
}

fn encToIndex(enc: u8) !u8 {
    return switch (enc) {
        'A'...'Z' => |i| i - 0x41,
        'a'...'z' => |i| i + 26 - 0x61,
        '0'...'9' => |i| i + 52 - 0x30,
        '+' => 62,
        '/' => 63,
        else => error.InvalidChar,
    };
}

const std = @import("std");

fn testEncode(expected: []const u8, in: []const u8) !void {
    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try encode(str.writer(), in);

    try std.testing.expectEqualStrings(expected, str.items);
}

fn testDecode(expected: []const u8, in: []const u8) !void {
    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try decode(str.writer(), in);

    try std.testing.expectEqualSlices(u8, expected, str.items);
}

test "encode octet string" {
    try testEncode("FPucA9l+", "\x14\xFB\x9C\x03\xD9\x7E");
    try testEncode("FPucA9k=", "\x14\xFB\x9C\x03\xD9");
    try testEncode("FPucAw==", "\x14\xFB\x9C\x03");
}

test "decode radix-64" {
    try testDecode("\x14\xFB\x9C\x03\xD9\x7E", "FPucA9l+");
    try testDecode("\x14\xFB\x9C\x03\xD9", "FPucA9k=");
    try testDecode("\x14\xFB\x9C\x03", "FPucAw==");
}
