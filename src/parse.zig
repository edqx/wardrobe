const std = @import("std");

const Boundary = @import("Boundary.zig");
const scanner = @import("scanner.zig").scanner;

pub const Entry = struct {
    name: []const u8,

    file_name: ?[]const u8,
    content_type: ?[]const u8,

    data: []const u8,

    pub fn deinit(self: Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.free(self.name);
        if (self.file_name) |file_name| allocator.free(file_name);
        if (self.content_type) |content_type| allocator.free(content_type);
    }
};

pub fn deinitEntries(allocator: std.mem.Allocator, entries: []Entry) void {
    for (entries) |entry| entry.deinit(allocator);
    allocator.free(entries);
}

pub fn fromScanner(allocator: std.mem.Allocator, scanner2: anytype) ![]Entry {
    var entries: std.ArrayListUnmanaged(Entry) = .empty;
    defer entries.deinit(allocator);
    defer for (entries.items) |entry| entry.deinit(allocator);

    while (try scanner2.nextEntry()) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);
        const file_name = if (entry.file_name) |str| try allocator.dupe(u8, str) else null;
        errdefer if (file_name) |str| allocator.free(str);
        const content_type = if (entry.content_type) |str| try allocator.dupe(u8, str) else null;
        errdefer if (content_type) |str| allocator.free(str);

        const data = try scanner2.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        errdefer allocator.free(data);

        try entries.append(allocator, .{
            .name = name,
            .file_name = file_name,
            .content_type = content_type,
            .data = data,
        });
    }

    return try entries.toOwnedSlice(allocator);
}

pub fn fromReader(allocator: std.mem.Allocator, boundary: Boundary, reader: anytype) ![]Entry {
    var scanner2 = try scanner(allocator, boundary, reader);
    defer scanner2.deinit();

    return fromScanner(allocator, &scanner2);
}

pub fn fromSlice(allocator: std.mem.Allocator, boundary: Boundary, slice: []const u8) ![]Entry {
    var fbs = std.io.fixedBufferStream(slice);
    return try fromReader(allocator, boundary, fbs.reader());
}

test fromSlice {
    // https://medium.com/@muhebollah.diu/understanding-multipart-form-data-the-ultimate-guide-for-beginners-fd039c04553d
    const data = "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ++
        "Content-Disposition: form-data; name=\"username\"\r\n" ++
        "\r\n" ++
        "john_doe\r\n" ++
        "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ++
        "Content-Disposition: form-data; name=\"profile_picture\"; filename=\"profile.jpg\"\r\n" ++
        "Content-Type: image/jpeg\r\n" ++
        "\r\n" ++
        "[Binary data of the JPEG file]\r\n" ++
        "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "Content-Type: application/json\r\n" ++
        "\r\n" ++
        "{\"age\": 30, \"location\": \"New York\"}\r\n" ++
        "------WebKitFormBoundary7MA4YWxkTrZu0gW--";

    const parsed = try fromSlice(std.testing.allocator, .buffer("----WebKitFormBoundary7MA4YWxkTrZu0gW"), data);
    defer deinitEntries(std.testing.allocator, parsed);

    try std.testing.expect(parsed.len == 3);

    try std.testing.expectEqualSlices(u8, parsed[0].name, "username");
    try std.testing.expectEqualSlices(u8, parsed[0].data, "john_doe");

    try std.testing.expectEqualSlices(u8, parsed[1].name, "profile_picture");
    try std.testing.expect(parsed[1].file_name != null);
    try std.testing.expectEqualSlices(u8, parsed[1].file_name.?, "profile.jpg");
    try std.testing.expect(parsed[1].content_type != null);
    try std.testing.expectEqualSlices(u8, parsed[1].content_type.?, "image/jpeg");
    try std.testing.expectEqualSlices(u8, parsed[1].data, "[Binary data of the JPEG file]");

    try std.testing.expectEqualSlices(u8, parsed[2].name, "metadata");
    try std.testing.expect(parsed[2].content_type != null);
    try std.testing.expectEqualSlices(u8, parsed[2].content_type.?, "application/json");
    try std.testing.expectEqualSlices(u8, parsed[2].data, "{\"age\": 30, \"location\": \"New York\"}");
}
