//! FEvent.Tcp
//! Connection Request : Handle an asynchronous request to connect a socket to a distant host
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const Win = @import("../Windows.zig");
const WTcp = Win.Tcp;

const Tcp = @import("Tcp.zig");
const TimerReq = @import("../Timer/Request.zig");
const AnyReq = @import("AnyRequest.zig");

pub const Callback = *const fn (tcp: *Tcp, req: *Self, err: ?Win.ErrorCode) void;

//                          ----------------      Members     ----------------

address: WTcp.Address = .{
    .port = undefined,
    .addr = undefined,
},

timerReq: TimerReq = .{},
timeout: u64 = undefined,

//                          ----------------      Public      ----------------

pub fn Make(address: []const u8, port: u16, timeout: u64, tcp: *Tcp, cb: Callback) error{BadAddress}!AnyReq {
    return .{
        .req = .{
            .connection = .{
                .address = try WTcp.MakeAddress(address, port),
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
            .overlapped = @import("std").mem.zeroes(Win.Request),
        },
    };
}

// We need to make it public so a call to Tcp.Connect can access it
pub fn TimeOutCallback(req: *TimerReq) void {
    const anyReq = req.GetData(AnyReq);
    const tcp = @as(*Tcp, @fieldParentPtr("handle", anyReq.base.handle));

    tcp.socket.CancelRequest(&anyReq.base.overlapped) catch unreachable;
}

pub fn GetAnyReq(self: *Self) *AnyReq {
    return @as(*AnyReq, @fieldParentPtr("req", @as(*AnyReq.ReqUnion, @fieldParentPtr("connection", self))));
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
