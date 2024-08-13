const win = @import("std").os.windows;

const Loop = @import("Loop.zig");
const Tcp = @import("Tcp/Tcp.zig");

test "simple test" {
    try main();
}

pub fn main() !void {
    var loop = try Loop.Make();

    var tcp: Tcp = .{};
    try tcp.Create(&loop, .IPv4);

    var conReq = try Tcp.ConnectRequest.Make("127.0.0.1", 80, 1000, &tcp, cb);

    try tcp.Connect(&conReq);

    try loop.Run(100);

    try loop.Close();
}

pub fn cb(tcp: *Tcp, req: *Tcp.ConnectRequest, err: ?win.Win32Error) void {
    if (err) |er| {
        @import("std").log.err("tcp connect cb : Error message : {s}", .{@tagName(er)});
    }

    _ = req;

    tcp.Close() catch unreachable;
}
