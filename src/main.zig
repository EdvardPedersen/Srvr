const std = @import("std");

const site = @embedFile("index.html");

pub fn main(init: std.process.Init) !void{
    std.debug.print("Hello world\n", .{});
    const io = init.io;
    const addr = try std.Io.net.IpAddress.resolve(io,"127.0.0.1", 8000);
    var server = try addr.listen(io, .{.reuse_address = true});

    const buf_size = 4096;
    var recv: [buf_size]u8 = undefined;
    var send: [buf_size]u8 = undefined;

    while(true) {
        const stream = try server.accept(io);
        defer stream.close(io);
        var reader = stream.reader(io, &recv);
        var writer = stream.writer(io, &send);
        var serve: std.http.Server = .init(&reader.interface, &writer.interface);
        var request = try serve.receiveHead();
        try request.respond(site, .{.keep_alive = false});
        
    }
}
