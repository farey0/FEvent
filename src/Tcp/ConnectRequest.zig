//! FEvent.Tcp
//! Connection Request : Handle an asynchronous request to connect a socket to a distant host
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

const Tcp = @import("Tcp.zig");
const TimerReq = @import("../Timer/Request.zig");
const AnyReq = @import("AnyRequest.zig");

pub const Callback = *const fn (tcp: *Tcp, req: *Self, err: ?win.Win32Error) void;

//                          ----------------      Members     ----------------

address: ws2_32.sockaddr.in = .{
    .port = undefined,
    .addr = undefined,
},

timerReq: TimerReq = .{},
timeout: u64 = undefined,

//                          ----------------      Public      ----------------

pub fn Make(addressRaw: []const u8, port: u16, timeout: u64, tcp: *Tcp, cb: Callback) error{BadAddress}!AnyReq {

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

// We need to make it public so a call to Tcp.Connect can access it
pub fn TimeOutCallback(req: *TimerReq) void {
    const anyReq = req.GetData(AnyReq);
    const tcp = @as(*Tcp, @fieldParentPtr("handle", anyReq.base.handle));

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

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
