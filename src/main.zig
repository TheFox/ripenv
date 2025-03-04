const std = @import("std");
const io = std.io;
const mem = std.mem;

pub fn main() !void {
    var args = std.process.args();
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

    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var input: [4096]u8 = undefined;
    const input_s = try stdin.readAll(&input);
    try stderr.print("input size: {}\n", .{input_s});
    try stdout.print("OK\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const env_map = try allocator.create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(allocator);
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator

    // iterate over env vars
    var env_it = env_map.iterator();
    while (env_it.next()) |env_var| {
        if (arg_verbose) {
            try stdout.print("{s}={s}\n", .{ env_var.key_ptr.*, env_var.value_ptr.* });
        }
    }
}
