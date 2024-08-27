//! FEvent.Tcp
//! Connection Request : Handle an asynchronous request to connect a socket to a distant host
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

const Tcp = @import("Tcp.zig");
const AnyReq = @import("AnyRequest.zig");

pub const Callback = *const fn (tcp: *Tcp, req: *AnyReq, accepted: *Tcp, err: ?win.Win32Error) void;

pub const AddressSize = @sizeOf(ws2_32.sockaddr.storage) + 16;

pub const TotalAddressSize = AddressSize * 2;

//                          ----------------      Members     ----------------

accepting: *Tcp = undefined,
acceptBuffer: []u8 = undefined,
cb: Callback = undefined,

//                          ----------------      Public      ----------------

pub fn Make(tcp: *Tcp, cb: Callback) !AnyReq {
    return .{
        .alive = false,

        .base = .{
            .handle = &tcp.handle,
            .overlapped = @import("std").mem.zeroes(win.OVERLAPPED),
        },

        .req = .{
            .accept = .{},
        },

        .cb = .{
            .accept = cb,
        },
    };
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
