const std = @import("std");

const Boundary = @import("Boundary.zig");

pub fn WriteStream(UnderlyingWriter: type) type {
    return struct {
        underlying_writer: UnderlyingWriter,
        boundary: Boundary,

        in_entry: bool = false,
        ended: bool = false,

        pub fn rawWriter(self: @This()) UnderlyingWriter {
            return self.underlying_writer;
        }

        pub fn writer(self: @This()) UnderlyingWriter {
            return self.rawWriter();
        }

        pub fn writeBoundary(self: @This()) !void {
            try self.rawWriter().print("--{s}\r\n", .{self.boundary.slice()});
        }

        pub fn writeLastBoundary(self: @This()) !void {
            try self.rawWriter().print("--{s}--\r\n", .{self.boundary.slice()});
        }

        pub fn writeHeader(self: @This(), header_name: []const u8, comptime val_fmt: []const u8, args: anytype) !void {
            try self.rawWriter().print("{s}: " ++ val_fmt ++ "\r\n", .{header_name} ++ args);
        }

        pub fn writeHeaderEnd(self: @This()) !void {
            try self.rawWriter().print("\r\n", .{});
        }

        pub fn writeDispositionHeader(self: @This(), name: []const u8, file_name: ?[]const u8) !void {
            if (file_name) |str| {
                try self.writeHeader("Content-Disposition", "form-data; name=\"{s}\"; filename=\"{s}\"", .{ name, str });
            } else {
                try self.writeHeader("Content-Disposition", "form-data; name=\"{s}\"", .{name});
            }
        }

        pub fn beginTextEntry(self: *@This(), name: []const u8) !void {
            std.debug.assert(!self.in_entry);
            std.debug.assert(!self.ended);
            try self.writeBoundary();
            try self.writeDispositionHeader(name, null);
            try self.writeHeaderEnd();
            self.in_entry = true;
        }

        pub fn beginFileEntry(self: *@This(), name: []const u8, content_type: []const u8, file_name: []const u8) !void {
            std.debug.assert(!self.in_entry);
            std.debug.assert(!self.ended);
            try self.writeBoundary();
            try self.writeDispositionHeader(name, file_name);
            try self.writeHeader("Content-Type", "{s}", .{content_type});
            try self.writeHeaderEnd();
            self.in_entry = true;
        }

        pub fn endEntry(self: *@This()) !void {
            std.debug.assert(self.in_entry);
            std.debug.assert(!self.ended);
            try self.rawWriter().print("\r\n", .{});
            self.in_entry = false;
        }

        pub fn endEntries(self: *@This()) !void {
            std.debug.assert(!self.in_entry);
            std.debug.assert(!self.ended);
            try self.writeLastBoundary();
            self.ended = true;
        }
    };
}

pub fn writeStream(boundary: Boundary, underlying_writer: anytype) WriteStream(@TypeOf(underlying_writer)) {
    return .{
        .underlying_writer = underlying_writer,
        .boundary = boundary,
    };
}

test WriteStream {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    const writer = output.writer(std.testing.allocator);

    var write_stream = writeStream(.buffer("----ZeppelinMessageBoundarydGMntdcUv30758LEJIwq"), writer);

    try write_stream.beginTextEntry("payload_json");
    try write_stream.writer().print("hello", .{});
    try write_stream.endEntry();

    try write_stream.beginFileEntry("file", "image/png", "barney.jpeg");
    try write_stream.writer().print("[barney bytes]", .{});
    try write_stream.endEntry();

    try write_stream.endEntries();

    try std.testing.expectEqualSlices(
        u8,
        "------ZeppelinMessageBoundarydGMntdcUv30758LEJIwq\r\n" ++
            "Content-Disposition: form-data; name=\"payload_json\"\r\n" ++
            "\r\n" ++
            "hello\r\n" ++
            "------ZeppelinMessageBoundarydGMntdcUv30758LEJIwq\r\n" ++
            "Content-Disposition: form-data; name=\"file\"; filename=\"barney.jpeg\"\r\n" ++
            "Content-Type: image/png\r\n" ++
            "\r\n" ++
            "[barney bytes]\r\n" ++
            "------ZeppelinMessageBoundarydGMntdcUv30758LEJIwq--\r\n",
        output.items,
    );
}
