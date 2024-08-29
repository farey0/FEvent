//! FEvent.Tcp
//! AnyRequest : Union of all the tcp's requests with base type.
//! Use this one if you allocate memory for requests
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const Win = @import("../Windows.zig");
const WTcp = Win.Tcp;

const Tcp = @import("Tcp.zig");

pub const Connect = @import("Request/Connect.zig");
pub const Accept = @import("Request/Accept.zig");
pub const Disconnect = @import("Request/Disconnect.zig");

const TimerReq = @import("../Timer/Request.zig");

const BaseReq = @import("../Request.zig");

pub const Callback = *const fn (tcp: *Tcp, req: *Self, err: ?Win.ErrorCode) void;

pub const ReqUnion = union(enum) {
    connection: Connect,
    accept: Accept,
    disconnect: Disconnect,
};

//                          ----------------      Members     ----------------

req: ReqUnion,

// don't use directly Callback type see : https://ziggit.dev/t/avoid-dependency-loop-detected-with-function-pointers/4717/22?page=2
cb: *const fn (tcp: *Tcp, req: *Self, err: ?Win.ErrorCode) void = undefined,

alive: bool = undefined,

base: BaseReq = .{},

//                          ----------------      Public      ----------------

// Public so the loop can access it. Don't use it as an user
pub fn HandleCompletion(baseReq: *BaseReq, err: ?Win.ErrorCode) void {
    const anyReq = @as(*Self, @fieldParentPtr("base", baseReq));
    const tcp = @as(*Tcp, @fieldParentPtr("handle", anyReq.base.handle));

    switch (anyReq.req) {
        .connection => {
            if (err == null) tcp.state = .Connected;
        },
        .accept => {
            const accept = &anyReq.req.accept;

            if (err == null) accept.accepting.state = .Connected;
        },
        .disconnect => {
            if (err == null) tcp.state = .Disconnected;
        },
    }

    anyReq.alive = false;
    tcp.DecReqCount();
    anyReq.CleanOV();

    anyReq.cb(tcp, anyReq, err);
}

pub fn CleanOV(self: *Self) void {
    self.base.overlapped = @import("std").mem.zeroes(Win.Request);
}

pub fn MakeConnect(address: []const u8, port: u16, timeout: u64, tcp: *Tcp, cb: Callback) error{BadAddress}!Self {
    return .{
        .req = .{
            .connection = .{
                .address = try WTcp.MakeAddress(address, port),
                .timeout = timeout,
                .timerReq = .{
                    .cb = TimeOutConnectCallback,
                },
            },
        },

        .cb = cb,
        .alive = false,
        .base = BaseReq.Make(&tcp.handle),
    };
}

pub fn MakeAccept(tcp: *Tcp, cb: Callback) Self {
    return .{
        .alive = false,
        .base = BaseReq.Make(&tcp.handle),
        .req = .{
            .accept = .{},
        },
        .cb = cb,
    };
}

pub fn MakeDisconnect(tcp: *Tcp, cb: Callback) Self {
    return .{
        .alive = false,
        .base = BaseReq.Make(&tcp.handle),
        .req = .{
            .disconnect = .{},
        },
        .cb = cb,
    };
}

//                          ------------- Public Getters/Setters -------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    self.base.SetData(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    return self.base.GetData(T);
}

pub fn GetConnect(self: *Self) *Connect {
    if (self.req != .connection)
        unreachable;

    return &self.req.connection;
}

pub fn GetAccept(self: *Self) *Accept {
    if (self.req != .accept)
        unreachable;

    return &self.req.accept;
}

pub fn GetDisconnect(self: *Self) *Disconnect {
    if (self.req != .close)
        unreachable;

    return &self.req.disconnect;
}

//                          ----------------      Private     ----------------

fn TimeOutConnectCallback(req: *TimerReq) void {
    const anyReq = req.GetData(Self);
    const tcp = @as(*Tcp, @fieldParentPtr("handle", anyReq.base.handle));

    tcp.socket.CancelRequest(&anyReq.base.overlapped) catch unreachable;
}
