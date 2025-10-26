const std = @import("std");
const File = std.fs.File;
const Writer = std.Io.Writer;
const memcpy = std.mem.copyForwards;
const eql = std.mem.eql;
const indexOf = std.mem.indexOf;
const print = std.debug.print;
const expect = std.testing.expect;
const process = std.process;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const BUFFER_SIZE = 1024;

pub fn main() !void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdin_buffer = try allocator.alloc(u8, BUFFER_SIZE);
    defer allocator.free(stdin_buffer);
    var stdin_reader = File.stdin().reader(stdin_buffer);
    const stdin = &stdin_reader.interface;

    const stdout_buffer = try allocator.alloc(u8, BUFFER_SIZE);
    defer allocator.free(stdout_buffer);
    var stdout_writer = File.stdout().writer(stdout_buffer);
    const stdout = &stdout_writer.interface;

    const stderr_buffer = try allocator.alloc(u8, BUFFER_SIZE);
    defer allocator.free(stderr_buffer);
    var stderr_writer = File.stderr().writer(stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args = process.args();
    _ = args.next(); // Skip program name

    var arg_verbose: u8 = 0;
    var arg_prefix: u8 = '$';
    while (args.next()) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return;
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--verbose")) {
            arg_verbose = 1;
        } else if (eql(u8, arg, "-c")) {
            if (args.next()) |char| {
                if (char.len == 1)
                    arg_prefix = char[0];
            }
        }
    }

    const input_b = try allocator.alloc(u8, 1024);
    defer allocator.free(input_b);

    const input_l = try stdin.readSliceShort(input_b);

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, input_b[0..input_l]);

    const env_map = try allocator.create(process.EnvMap);
    defer env_map.deinit();
    env_map.* = try process.getEnvMap(allocator);

    // Iterate over env vars.
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        if (arg_prefix == '$') {
            {
                var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
                defer search_s.deinit(allocator);
                try search_s.append(allocator, arg_prefix);
                try search_s.appendSlice(allocator, env_var.key_ptr.*);

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(allocator, &input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose >= 1 and did_something) {
                        try stderr.print("found A: '{s}'\n", .{search_s.items});
                        try stderr.flush();
                    }
                }
            }

            {
                var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
                defer search_s.deinit(allocator);
                try search_s.append(allocator, arg_prefix);
                try search_s.append(allocator, '{');
                try search_s.appendSlice(allocator, env_var.key_ptr.*);
                try search_s.append(allocator, '}');

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(allocator, &input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose >= 1 and did_something) {
                        try stderr.print("found B: '{s}'\n", .{search_s.items});
                        try stderr.flush();
                    }
                }
            }
        } else {
            var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
            defer search_s.deinit(allocator);
            try search_s.append(allocator, arg_prefix);
            try search_s.appendSlice(allocator, env_var.key_ptr.*);
            try search_s.append(allocator, arg_prefix);

            var did_something = true;
            while (did_something) {
                did_something = try replaceInArraylist(allocator, &input, &search_s, env_var.value_ptr.*);
                if (arg_verbose >= 1 and did_something) {
                    try stderr.print("found C: '{s}'\n", .{search_s.items});
                    try stderr.flush();
                }
            }
        }
    }

    try stdout.writeAll(input.items);
    try stdout.flush();
}

fn replaceInArraylist(allocator: Allocator, input: *ArrayList(u8), search: *ArrayList(u8), replace: []const u8) !bool {
    const pos = indexOf(u8, input.items, search.items) orelse return false;

    if (search.items.len == replace.len) {
        // '$HELLO' (6) replaced by 'WORLDX' (6)
        input.replaceRangeAssumeCapacity(pos, search.items.len, replace);
    } else if (search.items.len > replace.len) {
        // '$HELLO' (6) replaced by 'WORD' (4)
        const diff: usize = search.items.len - replace.len;
        try input.replaceRange(allocator, pos, replace.len, replace);
        input.replaceRangeAssumeCapacity(pos + replace.len, diff, &.{});
    } else {
        // '$HELLO' (6) replaced by 'HELLO WORLD' (11)
        const diff: usize = replace.len - search.items.len;
        _ = try input.addManyAt(allocator, pos + search.items.len, diff);
        try input.replaceRange(allocator, pos, replace.len, replace);
    }
    return true;
}

fn printHelp(stdout: *Writer) !void {
    const help =
        \\Usage: ripenv [-h|--help] [-v] < input_template > output_file
        \\
        \\Options:
        \\-h, --help           Print this help.
        \\-v, --verbose        Verbose output.
    ;
    try stdout.print(help ++ "\n", .{});
    try stdout.flush();
}

test "strInStr" {
    const haystack = "hello world";
    const needle = "world";
    const result = indexOf(u8, haystack, needle);
    if (result != null)
        try expect(result == 6);
}

test "replace1a" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO'END");

    var search = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search.deinit(allocator);
    try search.appendSlice(allocator, "$HELLO");

    const replace: []const u8 = "WORLDX";

    const did_something = try replaceInArraylist(allocator, &input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORLDX'END"));
}

test "replace1b" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO''$HELLO'END");

    var search = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search.deinit(allocator);
    try search.appendSlice(allocator, "$HELLO");

    {
        const did_something = try replaceInArraylist(allocator, &input, &search, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''$HELLO'END"));
    }
    {
        const did_something = try replaceInArraylist(allocator, &input, &search, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
    }
}

test "replace1c" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'${HELLO}''${HELLO}'END");

    var search = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search.deinit(allocator);
    try search.appendSlice(allocator, "${HELLO}");

    {
        const did_something = try replaceInArraylist(allocator, &input, &search, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''${HELLO}'END"));
    }
    {
        const did_something = try replaceInArraylist(allocator, &input, &search, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
    }
}

test "replace2" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO'END");

    var search = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search.deinit(allocator);
    try search.appendSlice(allocator, "$HELLO");

    const replace: []const u8 = "WORd";

    const did_something = try replaceInArraylist(allocator, &input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORd'END"));
}

test "replace3" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO'END");

    var search = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search.deinit(allocator);
    try search.appendSlice(allocator, "$HELLO");

    const replace: []const u8 = "A New World Order";

    const did_something = try replaceInArraylist(allocator, &input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'A New World Order'END"));
}
