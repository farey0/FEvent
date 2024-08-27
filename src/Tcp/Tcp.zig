//! FEvent
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const FLib = @import("FLib");

const Loop = @import("../Loop.zig");
const Handle = @import("../Handle.zig");
const BaseReq = @import("../Request.zig");

pub const AnyRequest = @import("AnyRequest.zig");
pub const ConnectRequest = @import("ConnectRequest.zig");

const Win = @import("../Windows.zig");
const WTcp = Win.Tcp;

pub const Error = Win.ErrorCode;

pub const State = enum {
    Undefined,
    Created, // default state when created
    Connecting, // performing a connection
    Connected,
    Accepting, // accepting a connection on this socket
    Listening,
};

//                          ----------------      Members     ----------------

socket: WTcp = .{},
handle: Handle = undefined,
reqCount: usize = undefined,
state: State = .Undefined,

//                          ----------------      Public      ----------------

pub fn Create(self: *Self, loop: *Loop) Win.Error!void {
    self.* = .{
        .handle = .{
            .loop = loop,
            .type = .Tcp,
        },

        .reqCount = 0,
    };

    try self.socket.Init();

    self.state = .Created;

    errdefer self.socket.Close();

    try loop.RegisterHandle(&self.handle, self.socket.handle);
}

pub fn Close(self: *Self) Win.Error!void {
    if (self.reqCount != 0)
        unreachable;

    self.socket.Close();

    self.handle.loop.UnregisterHandle(&self.handle);
}

pub fn BindAndListen(self: *Self, address: []const u8, port: u16, backlog: ?i32) (Win.Error || error{BadAddress})!void {
    if (self.state != .Created)
        unreachable;

    const wAddress = try WTcp.MakeAddress(address, port);

    try self.socket.BindAndListen(&wAddress, backlog);

    self.state = .Listening;
}

pub fn Accept(self: *Self, accepting: *Self, acceptBuffer: [WTcp.AddressesLength]u8, req: *AnyRequest) !void {
    if (self.state != .Listening or req.req != .accept)
        unreachable;

    req.req.accept.acceptBuffer = acceptBuffer[0..];

    if (try self.socket.AcceptEx(accepting.*, acceptBuffer, &req.base.overlapped)) {
        accepting.state = .Connected;
        req.req.accept.cb(self, req, accepting, null);
    } else self.AddReqCount();
}

pub fn Connect(self: *Self, req: *AnyRequest) !void {
    if (req.req != .connection or self.state != .Created)
        unreachable;

    const connectReq = &req.req.connection;

    if (try self.socket.Connect(&req.base.overlapped, &connectReq.address)) {
        self.state = .Connected;
        req.cb.con(self, connectReq, null);
        return;
    }

    self.AddReqCount();
    connectReq.timerReq.SetData(req);
    self.handle.loop.timerManager.RegisterReq(&connectReq.timerReq, connectReq.timeout);
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------

pub fn AddReqCount(self: *Self) void {
    self.reqCount += 1;

    self.handle.loop.activeReqCount += 1;
}

pub fn DecReqCount(self: *Self) void {
    self.reqCount -= 1;

    self.handle.loop.activeReqCount -= 1;
}
