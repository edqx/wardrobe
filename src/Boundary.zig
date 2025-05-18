const std = @import("std");

const Boundary = @This();

const allowed_boundary_bytes = blk: {
    var out: []const u8 = "";
    for (0..255) |ascii| {
        switch (ascii) {
            0x27, 0x2d, 0x30...0x39, 0x41...0x5a, 0x5f, 0x61...0x7a => {
                out = out ++ .{ascii};
            },
            else => {},
        }
    }
    break :blk out;
};

const content_type = "multipart/form-data; boundary=";
const prefix = "----";

const max_boundary_length = 70;
const entropy_length = 20;

const base_buffer: [content_type.len + max_boundary_length]u8 = blk: {
    var buf: [content_type.len + max_boundary_length]u8 = undefined;
    buf[0..content_type.len].* = content_type.*;
    buf[content_type.len..][0..prefix.len].* = prefix.*;
    break :blk buf;
};

header_buffer: [content_type.len + max_boundary_length]u8,
boundary_len: usize,

fn specRandom(buf: []u8, rand: std.Random) void {
    for (buf) |*byte| {
        const random_byte = rand.uintLessThan(usize, allowed_boundary_bytes.len);
        byte.* = allowed_boundary_bytes[random_byte];
    }
}

pub fn entropy(boundary_label: []const u8, rand: std.Random) Boundary {
    const boundary_len = prefix.len + boundary_label.len + entropy_length;
    std.debug.assert(boundary_len <= max_boundary_length);

    var header_buffer = base_buffer;
    const boundary_buf = header_buffer[content_type.len + prefix.len ..];

    @memcpy(boundary_buf[0..boundary_label.len], boundary_label);
    specRandom(boundary_buf[boundary_label.len..], rand);

    return .{
        .header_buffer = header_buffer,
        .boundary_len = boundary_len,
    };
}

pub fn buffer(boundary: []const u8) Boundary {
    std.debug.assert(boundary.len <= max_boundary_length);

    var header_buffer = base_buffer;
    const boundary_buf = header_buffer[content_type.len..];

    @memcpy(boundary_buf[0..boundary.len], boundary);

    return .{
        .header_buffer = header_buffer,
        .boundary_len = boundary.len,
    };
}

pub inline fn slice(self: Boundary) []const u8 {
    return self.header_buffer[content_type.len..][0..self.boundary_len];
}

pub inline fn contentType(self: Boundary) []const u8 {
    return self.header_buffer[0 .. content_type.len + self.boundary_len];
}

test entropy {
    var default_prng: std.Random.DefaultPrng = .init(0);
    const random = default_prng.random();

    const boundary: Boundary = .entropy("ZeppelinMessageBoundary", random);

    try std.testing.expectEqualSlices(u8, "----ZeppelinMessageBoundaryJML'U-qpH2I2442Ob5JO", boundary.slice());
}

test contentType {
    const boundary: Boundary = .buffer("----ZeppelinMessageBoundaryONETWOTHREEFOUR");

    try std.testing.expectEqualSlices(u8, "multipart/form-data; boundary=----ZeppelinMessageBoundaryONETWOTHREEFOUR", boundary.contentType());
}
