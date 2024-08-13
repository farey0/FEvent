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

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

pub const AddressFamily = enum(i32) {
    Unspecified = ws2_32.AF.UNSPEC,
    IPv4 = ws2_32.AF.INET,
    IPv6 = ws2_32.AF.INET6,
};

//                          ----------------      Members     ----------------

socket: ws2_32.SOCKET = ws2_32.INVALID_SOCKET,
handle: Handle = undefined,
reqCount: usize = undefined,

//                          ----------------      Public      ----------------

pub fn Create(self: *Self, loop: *Loop, family: AddressFamily) !void {
    self.* = .{
        .handle = .{
            .loop = loop,
            .type = .Tcp,
        },

        .reqCount = 0,
    };

    self.socket = ws2_32.socket(@intFromEnum(family), ws2_32.SOCK.STREAM, 0);

    if (self.socket == ws2_32.INVALID_SOCKET) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }

    loop.RegisterHandle(&self.handle);
}

pub fn Close(self: *Self) (error{ActiveRequest} || @import("std").posix.UnexpectedError)!void {
    try win.closesocket(self.socket);

    self.socket = ws2_32.INVALID_SOCKET;

    self.handle.loop.UnregisterHandle(&self.handle);
}

pub fn Connect(self: *Self, req: *AnyRequest) !void {
    if (req.req != .connection)
        unreachable;

    const connectReq = &req.req.connection;

    const localAddr = Loop.StaticManager.GetAddrIPv4Any();

    {
        const ret = ws2_32.bind(self.socket, @ptrCast(&localAddr), @sizeOf(@TypeOf(localAddr)));

        if (ret == ws2_32.SOCKET_ERROR)
            return win.unexpectedError(win.kernel32.GetLastError());
    }

    const ret = Loop.StaticManager.ConnectEx(
        self.socket,
        &connectReq.address,
        null,
        0,
        null,
        &req.base.overlapped,
    );

    if (ret == 0) {
        const lastError = ws2_32.WSAGetLastError();

        if (lastError != .WSA_IO_PENDING)
            return win.unexpectedWSAError(lastError);

        connectReq.timerReq.SetData(req);
        self.handle.loop.timerManager.RegisterReq(&connectReq.timerReq, connectReq.timeout);

        self.AddReqCount();
    } else {
        // ConnectEx completed immediately

        req.cb.con(self, connectReq, null);
    }
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
