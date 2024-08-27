//! FEvent.
//! Author : Farey0
//!
//!

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

pub const ErrorCode = win.Win32Error;
pub const Error = @import("std").posix.UnexpectedError;

fn FireUnexpected() Error {
    return win.unexpectedError(win.kernel32.GetLastError());
}

extern "ntdll" fn RtlNtStatusToDosError(win.NTSTATUS) callconv(win.WINAPI) win.Win32Error;

pub const Entry = extern struct {
    lpCompletionKey: win.ULONG_PTR,
    lpOverlapped: *win.OVERLAPPED,
    Internal: win.ULONG_PTR,
    dwNumberOfBytesTransferred: win.DWORD,

    pub fn GetError(self: Entry) ?ErrorCode {
        const ntStatus = @as(win.NTSTATUS, @enumFromInt(self.Internal));

        return if (ntStatus != .SUCCESS) RtlNtStatusToDosError(@enumFromInt(self.Internal)) else null;
    }

    const Request = @import("../Request.zig");

    pub fn GetRequest(self: Entry) *Request {
        return @as(*Request, @fieldParentPtr("overlapped", self.lpOverlapped));
    }
};

//                          ----------------      Members     ----------------

port: win.HANDLE = win.INVALID_HANDLE_VALUE,

//                          ----------------      Public      ----------------

pub fn Make() !Self {
    return .{
        .port = try win.CreateIoCompletionPort(win.INVALID_HANDLE_VALUE, null, 0, 1),
    };
}

pub fn Close(self: *Self) void {
    win.CloseHandle(self.port);

    self.port = win.INVALID_HANDLE_VALUE;
}

pub fn DequeueEntries(self: Self, entries: []Entry, timeoutMs: u32) (error{TimeOut} || Error)!usize {
    if (self.port == win.INVALID_HANDLE_VALUE)
        unreachable;

    var removed: win.ULONG = undefined;

    if (win.kernel32.GetQueuedCompletionStatusEx(
        self.port,
        @ptrCast(entries.ptr),
        @intCast(entries.len),
        &removed,
        timeoutMs,
        @intFromBool(false),
    ) == 0) {
        return switch (win.kernel32.GetLastError()) {
            .WAIT_TIMEOUT => return error.TimeOut,
            else => |err| return win.unexpectedError(err),
        };
    }

    return removed;
}

pub fn AssociateHandle(self: Self, handle: win.HANDLE) Error!void {
    if (self.port == win.INVALID_HANDLE_VALUE or handle == win.INVALID_HANDLE_VALUE)
        unreachable;

    _ = try win.CreateIoCompletionPort(handle, self.port, 0, 0);
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
