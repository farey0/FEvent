//! FEvent
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const FLib = @import("FLib");

const Loop = @import("Loop.zig");
const Handle = @import("Handle.zig");
const BaseReq = @import("BaseReq.zig");

const TimerReq = @import("TimerReq.zig");

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

pub const AddressFamily = enum(i32) {
    Unspecified = ws2_32.AF.UNSPEC,
    IPv4 = ws2_32.AF.INET,
    IPv6 = ws2_32.AF.INET6,
};

const ConCallback = *const fn (tcp: *Self, req: *ConnectRequest, err: ?win.Win32Error) void;

pub const ConnectRequest = struct {
    address: ws2_32.sockaddr.in = .{
        .port = undefined,
        .addr = undefined,
    },

    timerReq: TimerReq = .{},
    timeout: u64 = undefined,

    pub fn TimeOutCallback(req: *TimerReq) void {
        const anyReq = req.GetData(AnyReq);
        const tcp = @as(*Self, @fieldParentPtr("handle", anyReq.base.handle));

        const success = win.kernel32.CancelIoEx(tcp.socket, &anyReq.base.overlapped) != 0;

        // idk why CancelIoEx don't fire a completion in the IO port for ConnectEx
        // so we check with GetOverlappedResult

        if (!success) {
            @import("std").log.err("CancelIoEx failed with error code : {s}", .{@tagName(win.kernel32.GetLastError())});
            @panic("");
        } else {
            var dummyBytes: win.DWORD = undefined;

            const ret = win.kernel32.GetOverlappedResult(
                tcp.socket,
                &anyReq.base.overlapped,
                &dummyBytes,
                @intFromBool(false),
            );

            if (ret == 0) {
                const winError = win.kernel32.GetLastError();

                if (winError == .OPERATION_ABORTED) {
                    anyReq.alive = false;
                    tcp.DecReqCount();
                    anyReq.cb.con(tcp, &anyReq.req.connection, winError);
                } else {
                    @import("std").log.err("GetOverlappedResult failed with error code : {s}", .{@tagName(winError)});
                    @panic("");
                }
            } else {
                // operation completed when we was trying to cancel it, idk how to handle it rn
                unreachable;
            }
        }
    }

    pub fn Make(addressRaw: []const u8, port: u16, timeout: u64, tcp: *Self, cb: ConCallback) error{BadAddress}!AnyReq {

        // need null terminated string for inet_addr
        var buffer: [12]u8 = undefined;

        if (addressRaw.len > 11)
            return error.BadAddress;

        @memcpy(buffer[0..addressRaw.len], addressRaw[0..addressRaw.len]);

        buffer[addressRaw.len] = 0;

        const address: ws2_32.sockaddr.in = .{
            .addr = ws2_32.inet_addr(&buffer),
            .port = ws2_32.htons(port),
        };

        if (address.addr == ws2_32.INADDR_NONE)
            return error.BadAddress;

        return .{
            .req = .{
                .connection = .{
                    .address = address,
                    .timeout = timeout,
                    .timerReq = .{
                        .cb = TimeOutCallback,
                    },
                },
            },

            .cb = .{
                .con = cb,
            },

            .alive = false,

            .base = .{
                .handle = &tcp.handle,
                .overlapped = @import("std").mem.zeroes(win.OVERLAPPED),
            },
        };
    }
};

pub const AnyReq = struct {
    req: union(enum) {
        connection: ConnectRequest,
    },

    cb: union {
        con: ConCallback,
    },

    alive: bool = undefined,

    base: BaseReq = .{},

    pub fn SetData(self: *AnyReq, dataPtr: anytype) void {
        self.base.SetData(dataPtr);
    }

    pub fn GetData(self: *AnyReq, comptime T: type) *T {
        return self.base.GetData(T);
    }

    pub fn HandleCompletion(baseReq: *BaseReq, err: ?win.Win32Error) void {
        const anyReq = @as(*AnyReq, @fieldParentPtr("base", baseReq));
        const tcp = @as(*Self, @fieldParentPtr("handle", anyReq.base.handle));

        switch (anyReq.req) {
            .connection => {
                const connect = &anyReq.req.connection;

                anyReq.alive = false;
                tcp.DecReqCount();

                anyReq.cb.con(tcp, connect, err);
            },
        }
    }
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

pub fn Connect(self: *Self, req: *AnyReq) !void {
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
