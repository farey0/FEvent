//! FEvent.Tcp
//! Author : Farey0
//!
//! Windows general stuff

// Win Error Handling

const win = @import("std").os.windows;

pub const ErrorCode = win.Win32Error;
pub const Error = @import("std").posix.UnexpectedError;

pub const Handle = win.HANDLE;
pub const InvalidHandle = win.INVALID_HANDLE_VALUE;
pub const Request = win.OVERLAPPED;

pub fn InitSystem() Error!void {
    try Tcp.InitSystem();

    try Time.InitSystem();
}

pub fn DeInitSystem() void {
    win.WSACleanup() catch unreachable;
}

pub fn FireUnexpected() Error {
    return win.unexpectedError(win.kernel32.GetLastError());
}

pub const Tcp = @import("Windows/Tcp.zig");
pub const Loop = @import("Windows/Loop.zig");

pub const Time = struct {
    pub var queryFrequency: u64 = undefined;

    pub fn InitSystem() Error!void {
        // cannot fail on XP or later
        queryFrequency = win.QueryPerformanceFrequency() / 1000;
    }

    pub fn Get() u64 {
        // cannot fail on XP or later
        return win.QueryPerformanceCounter() / queryFrequency;
    }
};
