const std = @import("std");

const Boundary = @import("Boundary.zig");

const boundary_indicator = "\r\n--";

fn eqlFmt(source: []const u8, comptime fmt: []const u8, args: anytype) bool {
    var counter = std.io.countingWriter(std.io.null_writer);
    var change_stream = std.io.changeDetectionStream(source, counter.writer());
    change_stream.writer().print(fmt, args) catch unreachable;
    return !change_stream.anything_changed and counter.bytes_written == source.len;
}

test eqlFmt {
    const test_buf = "one two three";

    try std.testing.expect(eqlFmt(test_buf, "one {s} three", .{"two"}));
    try std.testing.expect(!eqlFmt(test_buf, "one {s} three", .{"tw"}));
    try std.testing.expect(!eqlFmt(test_buf, "one {s}", .{"two"}));
    try std.testing.expect(eqlFmt(test_buf, "one two three", .{}));
}

pub fn Scanner(comptime buffer_size: usize, UnderlyingReader: type) type {
    if (buffer_size < boundary_indicator.len + Boundary.max_boundary_length) @compileError("Buffer size must be at least bigger than the maximum form data boundary size");

    return struct {
        const ScannerT = @This();

        pub const Error = UnderlyingReader.Error || error{ EndOfStream, NotFormData, InvalidBoundary };

        pub const Entry = struct {
            pub const Kind = union(enum) {
                pub const File = struct {
                    file_name: []const u8,
                    content_type: ?[]const u8,
                };

                text: void,
                file: File,
            };

            name: []const u8,
            kind: Kind,
        };

        pub const Reader = std.io.Reader(*ScannerT, Error, read);
        const BufferedReader = std.io.Reader(*ScannerT, Error, readFromBuffer);

        underlying_reader: UnderlyingReader,
        boundary: Boundary,

        data_list: std.ArrayList(u8),

        // buffer: [boundary_indicator.len + Boundary.max_boundary_length]u8 = undefined,
        buffer: [buffer_size]u8 = undefined,
        buffer_len: usize = 0,

        pub fn init(allocator: std.mem.Allocator, boundary: Boundary, underlying_reader: UnderlyingReader) !ScannerT {
            const expected_boundary_len = "--".len + boundary.slice().len;

            var buffer: ["--".len + Boundary.max_boundary_length]u8 = undefined;
            const num_read_bytes = try underlying_reader.readAll(buffer[0..expected_boundary_len]);

            if (num_read_bytes != expected_boundary_len) return Error.EndOfStream;
            if (!eqlFmt(buffer[0..num_read_bytes], "--{s}", .{boundary.slice()})) return Error.NotFormData;

            return .{
                .underlying_reader = underlying_reader,
                .boundary = boundary,
                .data_list = .init(allocator),
            };
        }

        pub fn deinit(self: *ScannerT) void {
            self.data_list.deinit();
        }

        fn readFromBuffer(self: *ScannerT, bytes: []u8) !usize {
            if (bytes.len < self.buffer_len) {
                @memcpy(bytes[0..bytes.len], self.buffer[0..bytes.len]);
                std.mem.copyForwards(u8, self.buffer[0 .. self.buffer_len - bytes.len], self.buffer[bytes.len..self.buffer_len]);
                self.buffer_len -= bytes.len;
                return bytes.len;
            }

            defer self.buffer_len = 0;
            @memcpy(bytes[0..self.buffer_len], self.buffer[0..self.buffer_len]);

            const more_bytes_read = try self.underlying_reader.read(bytes[self.buffer_len..]);
            return self.buffer_len + more_bytes_read;
        }

        pub fn read(self: *ScannerT, bytes: []u8) !usize {
            var buffered_reader: BufferedReader = .{ .context = self };

            const expected_boundary = self.boundary.slice();

            var buffer: [buffer_size]u8 = undefined;
            const num_bytes_read = try buffered_reader.read(buffer[0..buffer_size]);

            std.debug.assert(self.buffer_len == 0); // we expect the buffer to be fully cleared

            if (num_bytes_read == 0) return 0;

            if (buffer[0] == boundary_indicator[0]) {
                const boundary_size = boundary_indicator.len + expected_boundary.len;

                if (num_bytes_read < boundary_size) {
                    const actually_read = try buffered_reader.readAll(buffer[num_bytes_read..boundary_size]);
                    if (actually_read != boundary_size - num_bytes_read) return Error.EndOfStream;
                }

                if (eqlFmt(buffer[0..boundary_size], "{s}{s}", .{ boundary_indicator, expected_boundary })) {
                    if (num_bytes_read >= boundary_size) {
                        const bytes_remaining = num_bytes_read - boundary_size;
                        @memcpy(self.buffer[0..bytes_remaining], buffer[boundary_size..][0..bytes_remaining]);
                        self.buffer_len = bytes_remaining;
                    }
                    return 0;
                }
            }

            if (std.mem.indexOfScalarPos(u8, buffer[0..num_bytes_read], 1, boundary_indicator[0])) |idx| {
                const bytes_remaining = num_bytes_read - idx;
                @memcpy(self.buffer[0..bytes_remaining], buffer[idx..num_bytes_read]);
                self.buffer_len = bytes_remaining;
                @memcpy(bytes[0..idx], buffer[0..idx]);
                return idx;
            }

            @memcpy(bytes[0..num_bytes_read], buffer[0..num_bytes_read]);

            return num_bytes_read;

            // const expected_boundary = self.boundary.slice();

            // const num_read_bytes = try self.readImpl(bytes[0..@min(buffer_size, bytes.len)]); // only read max buffer size at a time
            // const bytes_read = bytes[0..num_read_bytes];

            // if (std.mem.indexOfScalar(u8, bytes_read, boundary_indicator[0])) |idx| {
            //     // var buffer: [boundary_indicator.len + Boundary.max_boundary_length]u8 = undefined;
            //     var buffer: [buffer_size]u8 = undefined;

            //     const total_check_len = boundary_indicator.len + expected_boundary.len;

            //     const check_existing = bytes_read[idx..];
            //     @memcpy(buffer[0..check_existing.len], check_existing);

            //     if (check_existing.len < total_check_len) {
            //         const check_new_len = total_check_len - check_existing.len;

            //         var buffered_reader: BufferedReader = .{ .context = self };
            //         const read_check = try buffered_reader.readAll(buffer[check_existing.len..][0..check_new_len]);

            //         if (read_check != check_new_len) return Error.EndOfStream;
            //     }

            //     if (eqlFmt(buffer[0..total_check_len], "{s}{s}", .{ boundary_indicator, expected_boundary })) {
            //         const remaining_bytes = bytes_read.len - idx;
            //         @memcpy(self.buffer[0..remaining_bytes], bytes_read[idx..]);
            //         self.buffer_len = remaining_bytes;
            //         if (idx == 0) { // this means eof
            //             _ = try self.readImpl(buffer[0..total_check_len]); // re-use the buffer to skip the boundary
            //         }
            //         return idx;
            //     }
            //     const read_until = std.mem.indexOfScalarPos(u8, bytes_read, idx + 1, boundary_indicator[0]) orelse bytes_read.len;
            //     const remaining_bytes = bytes_read.len - read_until;

            //     @memcpy(self.buffer[0..remaining_bytes], bytes_read[read_until..]);
            //     self.buffer_len = remaining_bytes;

            //     return read_until;
            // }

            // return bytes_read.len;
        }

        pub fn reader(self: *ScannerT) Reader {
            return .{ .context = self };
        }

        fn streamUntilCrLf(stream_reader: anytype, stream_writer: anytype) !void {
            while (true) {
                try stream_reader.streamUntilDelimiter(stream_writer, '\r', null);
                const next_byte = try stream_reader.readByte();
                if (next_byte == '\n') return;

                try stream_writer.writeAll("\r\n");
            }
        }

        fn parseParameterValue(slice: []const u8) []const u8 {
            return if (slice[0] == '"') slice[1 .. slice.len - 1] else slice;
        }

        pub fn nextEntry(self: *ScannerT) !?Entry {
            var buffered_reader: BufferedReader = .{ .context = self };

            self.data_list.clearRetainingCapacity();

            var next_two_bytes: [2]u8 = undefined;
            try buffered_reader.readNoEof(&next_two_bytes);
            if (std.mem.eql(u8, &next_two_bytes, "--")) {
                return null;
            } else if (std.mem.eql(u8, &next_two_bytes, "\r\n")) {
                var entry: Entry = .{
                    .name = "",
                    .kind = .text,
                };
                while (true) {
                    const start_idx = self.data_list.items.len;
                    try streamUntilCrLf(buffered_reader, self.data_list.writer());

                    if (start_idx == self.data_list.items.len) break; // empty line

                    const header_line = self.data_list.items[start_idx..];
                    const separator_pos = std.mem.indexOfScalar(u8, header_line, ':') orelse return Error.InvalidBoundary;

                    const header_name = std.mem.trim(u8, header_line[0..separator_pos], " ");
                    const header_value = std.mem.trim(u8, header_line[separator_pos + 1 ..], " ");

                    var parameters = std.mem.tokenizeAny(u8, header_value, "; ");

                    if (std.mem.eql(u8, header_name, "Content-Disposition")) {
                        const disposition_type = parameters.next() orelse return Error.InvalidBoundary;
                        if (!std.mem.eql(u8, disposition_type, "form-data")) return Error.InvalidBoundary;

                        while (parameters.next()) |parameter| {
                            const eql_pos = std.mem.indexOfScalar(u8, parameter, '=') orelse return Error.InvalidBoundary;

                            const parameter_name = std.mem.trim(u8, parameter[0..eql_pos], " ");
                            const parameter_value = std.mem.trim(u8, parameter[eql_pos + 1 ..], " ");

                            if (std.mem.eql(u8, parameter_name, "name")) {
                                entry.name = parseParameterValue(parameter_value);
                            } else if (std.mem.eql(u8, parameter_name, "filename")) {
                                if (entry.kind != .text) return Error.InvalidBoundary;
                                entry.kind = .{
                                    .file = .{
                                        .file_name = parseParameterValue(parameter_value),
                                        .content_type = null,
                                    },
                                };
                            }
                        }
                    } else if (std.mem.eql(u8, header_name, "Content-Type")) {
                        const content_type = parameters.next() orelse return Error.InvalidBoundary;
                        if (entry.kind != .file) return Error.InvalidBoundary;

                        entry.kind.file.content_type = content_type;
                    } else continue;
                }
                return entry;
            }
            return Error.InvalidBoundary;
        }
    };
}

pub fn scanner(allocator: std.mem.Allocator, boundary: Boundary, underlying_reader: anytype) !Scanner(boundary_indicator.len + Boundary.max_boundary_length, @TypeOf(underlying_reader)) {
    return .init(allocator, boundary, underlying_reader);
}

test Scanner {
    const buf =
        "------Boundary\r\n" ++
        "Content-Disposition: form-data; name=\"profile_picture\"; filename=\"profile.jpg\"\r\n" ++
        "Content-Type: image/jpeg\r\n" ++
        "\r\n" ++
        "[Jpeg File Data]" ++ "\r\n" ++
        "------Boundary\r\n" ++
        "Content-Disposition: form-data; name=\"payload_json\"\r\n" ++
        "\r\n" ++
        "{}\r\n" ++
        "------Boundary--\r\n";

    var stream = std.io.fixedBufferStream(buf);

    const reader = stream.reader();

    var scanner2 = try scanner(std.testing.allocator, .buffer("----Boundary"), reader);
    defer scanner2.deinit();

    var i: usize = 0;

    while (try scanner2.nextEntry()) |entry| : (i += 1) {
        const data = try scanner2.reader().readAllAlloc(std.testing.allocator, std.math.maxInt(usize));
        defer std.testing.allocator.free(data);

        switch (i) {
            0 => {
                try std.testing.expect(entry.kind == .file);
                try std.testing.expectEqualSlices(u8, "profile_picture", entry.name);
                try std.testing.expectEqualSlices(u8, "profile.jpg", entry.kind.file.file_name);
                try std.testing.expect(entry.kind.file.content_type != null);
                try std.testing.expectEqualSlices(u8, "image/jpeg", entry.kind.file.content_type.?);

                try std.testing.expectEqualSlices(u8, "[Jpeg File Data]", data);
            },
            1 => {
                try std.testing.expect(entry.kind == .text);
                try std.testing.expectEqualSlices(u8, "payload_json", entry.name);

                try std.testing.expectEqualSlices(u8, "{}", data);
            },
            else => return error.TestUnexpectedResult,
        }
    }
}
