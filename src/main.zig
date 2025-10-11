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

pub fn main() !void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = File.stderr().writer(&stderr_buffer);
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
                }
            }
        }
    }

    try stdout.writeAll(input.items);
}

fn replaceInArraylist(allocator: Allocator, input: *ArrayList(u8), search: *ArrayList(u8), replace: []const u8) !bool {
    const pos = indexOf(u8, input.items, search.items) orelse return false;

    if (search.items.len == replace.len) {
        // '$HELLO' replaced by 'WORLDX'
        input.replaceRangeAssumeCapacity(pos, search.items.len, replace);
    } else if (search.items.len > replace.len) {
        // '$HELLO' replaced by 'WORD'
        const diff: usize = search.items.len - replace.len;
        try input.replaceRange(allocator, pos, replace.len, replace);
        input.replaceRangeAssumeCapacity(pos + replace.len, diff, &.{});
    } else {
        // '$HELLO' replaced by 'HELLO WORLD'
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

test "strings" {
    const john = "John";
    print("john={s} len={} type={}\n", .{ john, john.len, @TypeOf(john) });
}

test "strInStr" {
    const haystack = "hello world";
    const needle = "world";
    const result = indexOf(u8, haystack, needle);
    if (result != null)
        try expect(result == 6);
}

test "replaceInArraylist1a" {
    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice("START'$HELLO'END");

    var search = ArrayList(u8).init(std.heap.page_allocator);
    defer search.deinit();
    try search.appendSlice("$HELLO");

    const replace: []const u8 = "WORLDX";

    const did_something = try replaceInArraylist(&input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORLDX'END"));
}

test "replaceInArraylist1b" {
    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice("START'$HELLO''$HELLO'END");

    var search = ArrayList(u8).init(std.heap.page_allocator);
    defer search.deinit();
    try search.appendSlice("$HELLO");

    const replace: []const u8 = "WORLDX";

    const did_something = try replaceInArraylist(&input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
}

test "replaceInArraylist1c" {
    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice("START'${HELLO}''${HELLO}'END");

    var search = ArrayList(u8).init(std.heap.page_allocator);
    defer search.deinit();
    try search.appendSlice("${HELLO}");

    const replace: []const u8 = "WORLDX";

    const did_something = try replaceInArraylist(&input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
}

test "replaceInArraylist2" {
    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice("START'$HELLO'END");

    var search = ArrayList(u8).init(std.heap.page_allocator);
    defer search.deinit();
    try search.appendSlice("$HELLO");

    const replace: []const u8 = "WORd";

    const did_something = try replaceInArraylist(&input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORd'END"));
}

test "replaceInArraylist3" {
    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice("START'$HELLO'END");

    var search = ArrayList(u8).init(std.heap.page_allocator);
    defer search.deinit();
    try search.appendSlice("$HELLO");

    const replace: []const u8 = "A New World Order";

    const did_something = try replaceInArraylist(&input, &search, replace);
    try expect(did_something);
    try expect(eql(u8, input.items, "START'A New World Order'END"));
}
