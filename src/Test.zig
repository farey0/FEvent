const win = @import("std").os.windows;

const Loop = @import("Loop.zig");
const Tcp = @import("Tcp/Tcp.zig");

test "simple test" {
    try main();
}

var req: [5]Tcp.AnyRequest = undefined;
var acceptBuffer: [Tcp.AnyRequest.Accept.TotalAddressSize]u8 = undefined;

pub fn main() !void {
    var loop = try Loop.Make();

    var client: Tcp = .{};
    try client.Create(&loop);

    var listener: Tcp = .{};
    try listener.Create(&loop);

    var accepter: Tcp = .{};
    try accepter.Create(&loop);

    try listener.BindAndListen("127.0.0.1", 80, null);

    req[0] = Tcp.AnyRequest.MakeAccept(&listener, acceptSocket);

    try listener.Accept(&accepter, &acceptBuffer, &req[0]);

    req[1] = try Tcp.AnyRequest.MakeConnect("127.0.0.1", 80, 2000, &client, connectSocket);

    try client.Connect(&req[1]);

    try loop.Run(null);

    try loop.Close();
}

pub fn acceptSocket(tcp: *Tcp, reqin: *Tcp.AnyRequest, err: ?Tcp.Error) void {
    if (err) |er| {
        @import("std").log.err("tcp accept cb : Error message : {s}", .{@tagName(er)});
    }

    tcp.Close() catch unreachable;

    var accepted: *Tcp = reqin.req.accept.accepting;
    @import("std").log.warn("accepted", .{});

    req[2] = Tcp.AnyRequest.MakeDisconnect(accepted, disconnectSocket);
    accepted.Disconnect(&req[2]) catch unreachable;
}

pub fn connectSocket(tcp: *Tcp, reqin: *Tcp.AnyRequest, err: ?Tcp.Error) void {
    if (err) |er| {
        @import("std").log.err("tcp connect cb : Error message : {s}", .{@tagName(er)});
    }

    _ = reqin;
    @import("std").log.warn("connected", .{});

    req[3] = Tcp.AnyRequest.MakeDisconnect(tcp, disconnectSocket);
    tcp.Disconnect(&req[3]) catch unreachable;
}

pub fn disconnectSocket(tcp: *Tcp, reqin: *Tcp.AnyRequest, err: ?Tcp.Error) void {
    if (err) |er| {
        @import("std").log.err("tcp disconnect cb : Error message : {s}", .{@tagName(er)});
    }

    @import("std").log.warn("disconnected", .{});

    tcp.Close() catch unreachable;

    _ = reqin;
}
