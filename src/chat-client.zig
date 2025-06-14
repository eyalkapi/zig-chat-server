const std = @import("std");
const os = std.posix;
const net = std.net;
const io = std.io;
const c = std.c;

const MessageSendError = os.SendError || error{MissingTerminatorError};

fn send_message(sockfd: os.socket_t, msg_buf: []const u8) MessageSendError!usize {
    if (msg_buf[msg_buf.len - 1] != '\n') {
        return MessageSendError.MissingTerminatorError;
    }
    const bytes_sent = os.send(sockfd, msg_buf, 0) catch |err| return err;
    return bytes_sent;
}

fn read_message_from_input(reader: anytype, in_buf: []u8) !usize {
    const bytes_read = try reader.read(in_buf);
    return bytes_read;
}

fn make_poll_fd(fd: os.fd_t, events: comptime_int) os.pollfd {
    return .{ .fd = fd, .events = events, .revents = 0 };
}

pub fn main() !void {
    const PORT = 2028;
    const my_sock: i32 = try os.socket(os.AF.INET, os.SOCK.STREAM, 0);
    var my_addr: std.net.Address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, PORT);

    const stdout = std.io.getStdOut().writer();

    os.connect(my_sock, @ptrCast(&my_addr), my_addr.getOsSockLen()) catch |err| switch (err) {
        os.ConnectError.ConnectionRefused => try stdout.print("Connection was refused\n", .{}),
        else => try stdout.print("{?}", .{err}),
    };

    defer os.close(my_sock);

    try stdout.print("connected to server.\n", .{});
    const stdin = io.getStdIn();
    var in_buf: [100]u8 = undefined;
    var cr = io.countingReader(stdin.reader());
    const reader = cr.reader();
    const flags = try os.fcntl(stdin.handle, c.F.GETFL, 0);
    // make stdin read opeartion non blocking so the application can read user input and
    // print in the same thread
    _ = try os.fcntl(stdin.handle, c.F.SETFL, flags | c.SOCK.NONBLOCK);

    var pfds: [1]os.pollfd = .{make_poll_fd(my_sock, os.POLL.IN)};
    const my_pfd = &pfds[0];

    var recv_buf: [100]u8 = undefined;

    try stdout.print(">", .{});
    while (true) loop: {
        _ = try os.poll(&pfds, 200);
        if (my_pfd.*.revents & (os.POLL.NVAL | os.POLL.HUP) != 0) {
            break :loop;
        }
        if (my_pfd.*.revents & os.POLL.IN != 0) {
            const bytes_read = try os.recv(my_sock, &recv_buf, 0);
            if (bytes_read < 2) {
                break :loop;
            }
            try stdout.print("{s}", .{recv_buf[0..bytes_read]});
        }
        const bytes_read_from_input = read_message_from_input(reader, &in_buf) catch |err| switch (err) {
            os.ReadError.WouldBlock => continue,
            else => return err,
        };
        _ = try send_message(my_sock, in_buf[0..bytes_read_from_input]);
        try stdout.print(">", .{});
        // try try stdout.print("{s}", .{in_buf[0..bytes_read_from_input]});
    }

    try stdout.print("here", .{});
    os.close(my_sock);
}
