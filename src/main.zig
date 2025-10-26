const config = @import("config");
const std = @import("std");
const File = std.fs.File;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const process = std.process;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const eql = std.mem.eql;
const indexOf = std.mem.indexOf;
const print = std.debug.print;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const copy = std.mem.copyForwards;
const replacementSize = std.mem.replacementSize;
const replace = std.mem.replace;
const zeroes = std.mem.zeroes;

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
    var arg_buffer_size: usize = BUFFER_SIZE;
    while (args.next()) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return;
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--verbose")) {
            arg_verbose = 1;
        } else if (eql(u8, arg, "-c") or eql(u8, arg, "--prefix")) {
            if (args.next()) |char| {
                if (char.len == 1)
                    arg_prefix = char[0];
            }
        } else if (eql(u8, arg, "-b") or eql(u8, arg, "--buffer")) {
            if (args.next()) |char| {
                arg_buffer_size = try parseInt(usize, char, 10);
            }
        }
    }

    const mainFn = if (config.use_replace)
        mainReplace
    else
        mainArrayList;

    try mainFn(.{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
        .stderr = stderr,
        .verbose = arg_verbose,
        .prefix = arg_prefix,
        .buffer_size = arg_buffer_size,
    });
}

fn mainReplace(options: MainOptions) !void {
    const allocator = options.allocator;
    const stdin = options.stdin;
    const stdout = options.stdout;
    const stderr = options.stderr;
    const verbose = options.verbose;
    const prefix = options.prefix;
    const buffer_size = options.buffer_size;

    const input = try allocator.alloc(u8, buffer_size);
    defer allocator.free(input);

    const input_l = try stdin.readSliceShort(input);
    try stderr.print("input_l: {d}\n", .{input_l});
    try stderr.flush();

    var outputs = try ArrayList([]u8).initCapacity(allocator, 1024);

    const env_map = try allocator.create(process.EnvMap);
    defer env_map.deinit();
    env_map.* = try process.getEnvMap(allocator);

    // Iterate over env vars.
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        const env_key = env_var.key_ptr.*;
        const env_val = env_var.value_ptr.*;

        print("env: '{s}'='{s}'\n", .{ env_key, env_val });

        if (prefix == '$') {
            var search_s = try ArrayList(u8).initCapacity(allocator, buffer_size);
            defer search_s.deinit(allocator);
            try search_s.append(allocator, prefix);
            try search_s.appendSlice(allocator, env_key);

            const needed = replacementSize(u8, input, search_s.items, env_val);
            if (verbose >= 1) {
                try stderr.print("-> needed: {d}\n", .{needed});
                try stderr.flush();
            }
            // if (needed > buffer_size) {
            //     @panic("Needed replacement size is bigger then buffer size.");
            // }

            const output = try allocator.alloc(u8, needed);
            // defer allocator.free(output);
            try outputs.append(allocator, output);

            const replaced = replace(u8, input, search_s.items, env_val, output);
            if (verbose >= 1) {
                try stderr.print("-> replaced: {d}\n", .{replaced});
                try stderr.flush();
            }

            copy(u8, input, output);
        } else {}
    }

    for (outputs.items) |output| {
        allocator.free(output);
    }

    try stdout.writeAll(input);
    try stdout.flush();
}

fn mainArrayList(options: MainOptions) !void {
    const allocator = options.allocator;
    const stdin = options.stdin;
    const stdout = options.stdout;
    const stderr = options.stderr;
    const verbose = options.verbose;
    const prefix = options.prefix;
    const buffer_size = options.buffer_size;

    const input_b = try allocator.alloc(u8, buffer_size);
    defer allocator.free(input_b);

    const input_l = try stdin.readSliceShort(input_b);

    var input = try ArrayList(u8).initCapacity(allocator, buffer_size);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, input_b[0..input_l]);

    const env_map = try allocator.create(process.EnvMap);
    defer env_map.deinit();
    env_map.* = try process.getEnvMap(allocator);

    // Iterate over env vars.
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        const env_key = env_var.key_ptr.*;
        const env_val = env_var.value_ptr.*;

        if (prefix == '$') {
            {
                var search_s = try ArrayList(u8).initCapacity(allocator, buffer_size);
                defer search_s.deinit(allocator);
                try search_s.append(allocator, prefix);
                try search_s.appendSlice(allocator, env_key);

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(allocator, &input, &search_s, env_val);
                    if (verbose >= 1 and did_something) {
                        try stderr.print("found A: '{s}'\n", .{search_s.items});
                        try stderr.flush();
                    }
                }
            }

            {
                var search_s = try ArrayList(u8).initCapacity(allocator, buffer_size);
                defer search_s.deinit(allocator);
                try search_s.append(allocator, prefix);
                try search_s.append(allocator, '{');
                try search_s.appendSlice(allocator, env_key);
                try search_s.append(allocator, '}');

                var did_something = true;
                while (did_something) {
                    did_something = try replaceInArraylist(allocator, &input, &search_s, env_val);
                    if (verbose >= 1 and did_something) {
                        try stderr.print("found B: '{s}'\n", .{search_s.items});
                        try stderr.flush();
                    }
                }
            }
        } else {
            var search_s = try ArrayList(u8).initCapacity(allocator, buffer_size);
            defer search_s.deinit(allocator);
            try search_s.append(allocator, prefix);
            try search_s.appendSlice(allocator, env_key);
            try search_s.append(allocator, prefix);

            var did_something = true;
            while (did_something) {
                did_something = try replaceInArraylist(allocator, &input, &search_s, env_val);
                if (verbose >= 1 and did_something) {
                    try stderr.print("found C: '{s}'\n", .{search_s.items});
                    try stderr.flush();
                }
            }
        }
    }

    try stdout.writeAll(input.items);
    try stdout.flush();
}

fn replaceInArraylist(allocator: Allocator, input: *ArrayList(u8), search: *ArrayList(u8), replace_s: []const u8) !bool {
    const pos = indexOf(u8, input.items, search.items) orelse return false;
    if (search.items.len == replace_s.len) {
        // '$HELLO' (6) replaced by 'WORLDX' (6)
        input.replaceRangeAssumeCapacity(pos, search.items.len, replace_s);
    } else if (search.items.len > replace_s.len) {
        // '$HELLO' (6) replaced by 'WORD' (4)
        const diff: usize = search.items.len - replace_s.len;
        try input.replaceRange(allocator, pos, replace_s.len, replace_s);
        input.replaceRangeAssumeCapacity(pos + replace_s.len, diff, &.{});
    } else {
        // '$HELLO' (6) replaced by 'HELLO WORLD' (11)
        const diff: usize = replace_s.len - search.items.len;
        _ = try input.addManyAt(allocator, pos + search.items.len, diff);
        try input.replaceRange(allocator, pos, replace_s.len, replace_s);
    }
    return true;
}

fn printHelp(stdout: *Writer) !void {
    const help =
        \\Usage: ripenv <options> < input_template > output_file
        \\
        \\Options:
        \\-h, --help              Print this help.
        \\-v, --verbose           Verbose output.
        \\-c, --prefix <char>     Prefix (default: '$')
        \\-b, --buffer <size>     Buffer Size (default: 1024 bytes)
    ;
    try stdout.print(help ++ "\n", .{});
    try stdout.flush();
}

const MainOptions = struct {
    allocator: Allocator,
    stdin: *Reader,
    stdout: *Writer,
    stderr: *Writer,
    verbose: u8 = 0,
    prefix: u8 = '$',
    buffer_size: usize = BUFFER_SIZE,
};

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

    var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search_s.deinit(allocator);
    try search_s.appendSlice(allocator, "$HELLO");

    const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORLDX");
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORLDX'END"));
}

test "replace1b" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO''$HELLO'END");

    var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search_s.deinit(allocator);
    try search_s.appendSlice(allocator, "$HELLO");

    {
        const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''$HELLO'END"));
    }
    {
        const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
    }
}

test "replace1c" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'${HELLO}''${HELLO}'END");

    var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search_s.deinit(allocator);
    try search_s.appendSlice(allocator, "${HELLO}");

    {
        const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''${HELLO}'END"));
    }
    {
        const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORLDX");
        try expect(did_something);
        try expect(eql(u8, input.items, "START'WORLDX''WORLDX'END"));
    }
}

test "replace2" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO'END");

    var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search_s.deinit(allocator);
    try search_s.appendSlice(allocator, "$HELLO");

    const did_something = try replaceInArraylist(allocator, &input, &search_s, "WORd");
    try expect(did_something);
    try expect(eql(u8, input.items, "START'WORd'END"));
}

test "replace3" {
    const allocator = std.heap.page_allocator;

    var input = try ArrayList(u8).initCapacity(allocator, 1024);
    defer input.deinit(allocator);
    try input.appendSlice(allocator, "START'$HELLO'END");

    var search_s = try ArrayList(u8).initCapacity(allocator, 1024);
    defer search_s.deinit(allocator);
    try search_s.appendSlice(allocator, "$HELLO");

    const did_something = try replaceInArraylist(allocator, &input, &search_s, "A New World Order");
    try expect(did_something);
    try expect(eql(u8, input.items, "START'A New World Order'END"));
}
