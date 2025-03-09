const std = @import("std");
const io = std.io;
const mem = std.mem;
const memcpy = mem.copyForwards;
const heap = std.heap;
const print = std.debug.print;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;
const process = std.process;
const ArenaAllocator = heap.ArenaAllocator;

pub fn main() !void {
    var args = process.args();
    _ = args.next(); // Skip program name

    var arg_verbose: bool = false;
    var arg_prefix: u8 = '$';
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-v")) {
            arg_verbose = true;
        }
        if (mem.eql(u8, arg, "-c")) {
            if (args.next()) |char| {
                if (char.len == 1)
                    arg_prefix = char[0];
            }
        }
    }

    var stdin = io.getStdIn().reader();
    var stdout = io.getStdOut().writer();

    var input = ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try stdin.readAllArrayList(&input, 4096);

    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aallocator = arena.allocator();

    const env_map = try aallocator.create(process.EnvMap);
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator
    env_map.* = try process.getEnvMap(aallocator);

    // Iterate over env vars.
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        if (arg_prefix == '$') {
            {
                var search_s = ArrayList(u8).init(aallocator);
                defer search_s.deinit();
                try search_s.append(arg_prefix);
                try search_s.appendSlice(env_var.key_ptr.*);

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose and did_something) {
                        print("found A: '{s}'\n", .{search_s.items});
                    }
                }
            }

            {
                var search_s = ArrayList(u8).init(aallocator);
                defer search_s.deinit();
                try search_s.append(arg_prefix);
                try search_s.append('{');
                try search_s.appendSlice(env_var.key_ptr.*);
                try search_s.append('}');

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                    if (arg_verbose and did_something) {
                        print("found B: '{s}'\n", .{search_s.items});
                    }
                }
            }
        } else {
            var search_s = ArrayList(u8).init(aallocator);
            defer search_s.deinit();
            try search_s.append(arg_prefix);
            try search_s.appendSlice(env_var.key_ptr.*);
            try search_s.append(arg_prefix);

            var did_something = true;
            while (did_something) {
                did_something = try replaceInArraylist(&input, &search_s, env_var.value_ptr.*);
                if (arg_verbose and did_something) {
                    print("found C: '{s}'\n", .{search_s.items});
                }
            }
        }
    }

    try stdout.writeAll(input.items);
}

fn replaceInArraylist(input: *ArrayList(u8), search: *ArrayList(u8), replace: []const u8) !bool {
    const pos = mem.indexOf(u8, input.items, search.items) orelse return false;

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

test "strings" {
    const john = "John";
    print("john={s} len={} type={}\n", .{ john, john.len, @TypeOf(john) });
}

test "strInStr" {
    const haystack = "hello world";
    const needle = "world";
    const result = mem.indexOf(u8, haystack, needle);
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
    try expect(mem.eql(u8, input.items, "START'WORLDX'END"));
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
    try expect(mem.eql(u8, input.items, "START'WORLDX''WORLDX'END"));
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
    try expect(mem.eql(u8, input.items, "START'WORLDX''WORLDX'END"));
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
    try expect(mem.eql(u8, input.items, "START'WORd'END"));
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
    try expect(mem.eql(u8, input.items, "START'A New World Order'END"));
}
