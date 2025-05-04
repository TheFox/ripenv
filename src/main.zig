const std = @import("std");
const io = std.io;
const memcpy = std.mem.copyForwards;
const eql = std.mem.eql;
const indexOf = std.mem.indexOf;
const print = std.debug.print;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;
const process = std.process;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn main() !void {
    var args = process.args();
    _ = args.next(); // Skip program name

    var arg_verbose: u8 = 0;
    var arg_prefix: u8 = '$';
    while (args.next()) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            try printHelp();
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

    var stdin = io.getStdIn().reader();
    var stdout = io.getStdOut().writer();
    var stderr = io.getStdErr().writer();

    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try stdin.readAllArrayList(&input, 4096);

    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const env_map = try allocator.create(process.EnvMap);
    defer env_map.deinit();
    env_map.* = try process.getEnvMap(allocator);

    // Iterate over env vars.
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        if (arg_prefix == '$') {
            {
                var search_s = ArrayList(u8).init(allocator);
                defer search_s.deinit();
                try search_s.append(arg_prefix);
                try search_s.appendSlice(env_var.key_ptr.*);

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose >= 1 and did_something) {
                        try stderr.print("found A: '{s}'\n", .{search_s.items});
                    }
                }
            }

            {
                var search_s = ArrayList(u8).init(allocator);
                defer search_s.deinit();
                try search_s.append(arg_prefix);
                try search_s.append('{');
                try search_s.appendSlice(env_var.key_ptr.*);
                try search_s.append('}');

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose >= 1 and did_something) {
                        try stderr.print("found B: '{s}'\n", .{search_s.items});
                    }
                }
            }
        } else {
            var search_s = ArrayList(u8).init(allocator);
            defer search_s.deinit();
            try search_s.append(arg_prefix);
            try search_s.appendSlice(env_var.key_ptr.*);
            try search_s.append(arg_prefix);

            var did_something = true;
            while (did_something) {
                did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                if (arg_verbose >= 1 and did_something) {
                    try stderr.print("found C: '{s}'\n", .{search_s.items});
                }
            }
        }
    }

    try stdout.writeAll(input.items);
}

fn replaceInArraylist(input: *ArrayList(u8), search: *ArrayList(u8), replace: []const u8) !bool {
    const pos = indexOf(u8, input.items, search.items) orelse return false;

    if (search.items.len == replace.len) {
        // '$HELLO' replaced by 'WORLDX'
        input.replaceRangeAssumeCapacity(pos, search.items.len, replace);
    } else if (search.items.len > replace.len) {
        // '$HELLO' replaced by 'WORD'
        const diff: usize = search.items.len - replace.len;
        try input.replaceRange(pos, replace.len, replace);
        input.replaceRangeAssumeCapacity(pos + replace.len, diff, &.{});
    } else {
        // '$HELLO' replaced by 'HELLO WORLD'
        const diff: usize = replace.len - search.items.len;
        _ = try input.addManyAt(pos + search.items.len, diff);
        try input.replaceRange(pos, replace.len, replace);
    }
    return true;
}

fn printHelp() !void {
    const help =
        \\Usage: ripenv [-h|--help] [-v] < input_template > output_file
        \\
        \\Options:
        \\-h, --help           Print this help.
        \\-v, --verbose        Verbose output.
    ;

    var stdout = std.io.getStdErr().writer();
    try stdout.print(help ++ "\n", .{});
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
