//! FEvent.
//! Author : Farey0
//!
//! Manage a windows tcp socket

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

const Windows = @import("../Windows.zig");

const FireUnexpected = Windows.FireUnexpected;

pub const Socket = ws2_32.SOCKET;
pub const InvalidSocket = ws2_32.INVALID_SOCKET;
pub const Request = win.OVERLAPPED;

pub const Address = ws2_32.sockaddr.in;
pub const AddressMax = ws2_32.sockaddr.storage;

pub const AddressLength = @sizeOf(AddressMax) + 16;
pub const AddressesLength = AddressLength * 2;

pub const Buffer = extern struct {
    len: win.ULONG,
    buf: [*]u8,

    pub fn ToSlice(self: Buffer) []u8 {
        return self.buf[0..self.len];
    }

    pub fn FromSlice(slice: []u8) Buffer {
        return .{
            .len = @intCast(slice.len),
            .buf = @ptrCast(slice.ptr),
        };
    }
};

pub const Error = Windows.Error;

const LPFN_CONNECTEX = *const fn (
    s: ?ws2_32.SOCKET,
    // TODO: what to do with BytesParamIndex 2?
    name: ?*const ws2_32.sockaddr,
    namelen: i32,
    // TODO: what to do with BytesParamIndex 4?
    lpSendBuffer: ?*anyopaque,
    dwSendDataLength: u32,
    lpdwBytesSent: ?*u32,
    lpOverlapped: ?*win.OVERLAPPED,
) callconv(@import("std").os.windows.WINAPI) win.BOOL;

pub const LPFN_DISCONNECTEX = *const fn (
    s: ?ws2_32.SOCKET,
    lpOverlapped: ?*win.OVERLAPPED,
    dwFlags: u32,
    dwReserved: u32,
) callconv(@import("std").os.windows.WINAPI) win.BOOL;

//                          ----------------      Members     ----------------

handle: ws2_32.SOCKET = InvalidSocket,

var ConnectExPtr: LPFN_CONNECTEX = undefined;
var AcceptExPtr: ws2_32.LPFN_ACCEPTEX = undefined;
var DisconnectExPtr: LPFN_DISCONNECTEX = undefined;
var AddrIPv4Any: ws2_32.sockaddr.in = undefined;

//                          ----------------      Public      ----------------

pub fn Init(self: *Self) !void {
    if (self.handle != InvalidSocket)
        unreachable;

    self.handle = ws2_32.socket(ws2_32.AF.INET, ws2_32.SOCK.STREAM, 0);

    if (self.handle == InvalidSocket)
        return FireUnexpected();
}

pub fn Close(self: *Self) void {
    self.ValidateSocket();

    // if this function is called, every operation on the socket is already terminated
    // so an error is UB
    if (ws2_32.closesocket(self.handle) == ws2_32.SOCKET_ERROR)
        unreachable;

    self.handle = InvalidSocket;
}

pub fn CancelRequest(self: Self, ov: *Request) Error!void {
    if (win.kernel32.CancelIoEx(self.handle, ov) == 0)
        return FireUnexpected();
}

pub fn BindAndListen(self: Self, address: *const Address, backlog: ?i32) Error!void {
    self.ValidateSocket();

    if (ws2_32.bind(self.handle, @ptrCast(address), @sizeOf(@TypeOf(address.*))) == ws2_32.SOCKET_ERROR)
        return FireWSAUnexpected();

    if (ws2_32.listen(self.handle, if (backlog != null) backlog.? else ws2_32.SOMAXCONN) == ws2_32.SOCKET_ERROR)
        return FireWSAUnexpected();
}

pub fn AcceptEx(self: Self, in: Self, receiveBuffer: []u8, ov: *Request) Error!bool {
    if (receiveBuffer.len < AddressesLength)
        unreachable;

    self.ValidateSocket();
    in.ValidateSocket();

    var dummyBytesCount: u32 = 0;

    if (AcceptExPtr(
        self.handle,
        in.handle,
        receiveBuffer.ptr,
        0,
        AddressLength,
        AddressLength,
        &dummyBytesCount,
        ov,
    ) == 0) {
        const LastError = ws2_32.WSAGetLastError();

        if (LastError != .WSA_IO_PENDING)
            return win.unexpectedWSAError(LastError);

        return false;
    }

    return true;
}

pub fn MakeAddress(addressRaw: []const u8, port: u16) error{BadAddress}!Address {
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

    return address;
}

// Launch a connect overlapped request
// Return true if the connect immediately succeeded
pub fn Connect(self: Self, ov: *Request, address: *Address) Error!bool {
    self.ValidateSocket();

    if (ws2_32.bind(self.handle, @ptrCast(&AddrIPv4Any), @sizeOf(@TypeOf(AddrIPv4Any))) == ws2_32.SOCKET_ERROR)
        return FireWSAUnexpected();

    if (ConnectExPtr(
        self.handle,
        @ptrCast(address),
        @sizeOf(@TypeOf(address.*)),
        null,
        0,
        null,
        ov,
    ) == 0) {
        const LastError = ws2_32.WSAGetLastError();

        if (LastError != .WSA_IO_PENDING)
            return win.unexpectedWSAError(LastError);

        return false;
    }

    return true;
}

// launch a disconnect overlapped request
// return true if the disconnect immediately succeeded
pub fn Disconnect(self: Self, ov: *Request) Error!bool {
    self.ValidateSocket();

    if (DisconnectExPtr(self.handle, ov, 0, 0) == 0) {
        const LastError = ws2_32.WSAGetLastError();

        if (LastError != .WSA_IO_PENDING)
            return win.unexpectedWSAError(LastError);

        return false;
    }

    return true;
}

// Launch a send overlapped request
// return true if the send request immediately succeeded
pub fn Send(self: Self, buffer: []u8, ov: *Request) Error!bool {
    self.ValidateSocket();

    if (buffer.len == 0) unreachable;

    var winBuffer: Buffer = Buffer.FromSlice(buffer);

    var bytesSend: win.DWORD = 0;

    if (ws2_32.WSASend(
        self.handle,
        @ptrCast(&winBuffer),
        1,
        &bytesSend,
        0,
        ov,
        null,
    ) == 0) {
        return true;
    }

    const lastError = ws2_32.WSAGetLastError();

    if (lastError != .WSA_IO_PENDING)
        return win.unexpectedWSAError(lastError);

    return false;
}

// Launch a read overlapped request
// return true if the read request immediately succeeded
pub fn Read(self: Self, buffer: []u8, ov: *Request) Error!bool {
    self.ValidateSocket();

    if (buffer.len == 0) unreachable;

    var winBuffer: Buffer = Buffer.FromSlice(buffer);

    var bytesReceived: win.DWORD = 0;
    var dummyFlags: win.DWORD = 0;

    if (ws2_32.WSARecv(
        self.handle,
        @ptrCast(&winBuffer),
        1,
        &bytesReceived,
        &dummyFlags,
        ov,
        null,
    ) == 0) {
        return true;
    }

    const lastError = ws2_32.WSAGetLastError();

    if (lastError != .WSA_IO_PENDING)
        return win.unexpectedWSAError(lastError);

    return false;
}

// Init things we need before using this namespace
pub fn InitSystem() Error!void {
    var wsaData: ws2_32.WSADATA = undefined;

    if (ws2_32.WSAStartup((@as(win.DWORD, 2) << 8) | 2, &wsaData) != 0)
        return FireWSAUnexpected();

    AddrIPv4Any = .{
        .addr = ws2_32.inet_addr("0.0.0.0"),
        .port = ws2_32.htons(0),
    };

    var guidConnectEx: win.GUID = ws2_32.WSAID_CONNECTEX;
    var guidAcceptEx: win.GUID = ws2_32.WSAID_ACCEPTEX;
    var guidDisconnectEx: win.GUID = .{
        // see https://github.com/tpn/winsdk-10/blob/master/Include/10.0.10240.0/um/MSWSock.h

        //  {0x7fda2e11,0x8630,0x436f,{0xa0, 0x31, 0xf5, 0x36, 0xa6, 0xee, 0xc1, 0x57}}

        .Data1 = 0x7fda2e11,
        .Data2 = 0x8630,
        .Data3 = 0x436f,
        .Data4 = [8]u8{ 0xa0, 0x31, 0xf5, 0x36, 0xa6, 0xee, 0xc1, 0x57 },
    };

    // need a dummy sock to load a function via WSAIoctl
    var dummyBytes: win.DWORD = undefined;
    const dummySock = ws2_32.socket(ws2_32.AF.INET, ws2_32.SOCK.STREAM, 0);

    if (dummySock == ws2_32.INVALID_SOCKET)
        return FireUnexpected();

    // no reason that our dummy socket can't close
    defer win.closesocket(dummySock) catch unreachable;

    if (ws2_32.WSAIoctl(
        dummySock,
        ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guidConnectEx,
        @sizeOf(@TypeOf(guidConnectEx)),
        @ptrCast(&ConnectExPtr),
        @sizeOf(@TypeOf(ConnectExPtr)),
        &dummyBytes,
        null,
        null,
    ) != 0)
        return FireUnexpected();

    if (ws2_32.WSAIoctl(
        dummySock,
        ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guidAcceptEx,
        @sizeOf(@TypeOf(guidAcceptEx)),
        @ptrCast(&AcceptExPtr),
        @sizeOf(@TypeOf(AcceptExPtr)),
        &dummyBytes,
        null,
        null,
    ) != 0)
        return FireUnexpected();

    if (ws2_32.WSAIoctl(
        dummySock,
        ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guidDisconnectEx,
        @sizeOf(@TypeOf(guidDisconnectEx)),
        @ptrCast(&DisconnectExPtr),
        @sizeOf(@TypeOf(DisconnectExPtr)),
        &dummyBytes,
        null,
        null,
    ) != 0)
        return FireUnexpected();
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------

inline fn ValidateSocket(self: Self) void {
    if (self.handle == InvalidSocket)
        unreachable;
}

fn FireWSAUnexpected() Error {
    return win.unexpectedWSAError(ws2_32.WSAGetLastError());
}
