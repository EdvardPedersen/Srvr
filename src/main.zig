const std = @import("std");

const style = @embedFile("style.css");

const map_type = std.StringHashMap(Page);

const Page = struct {
    name : []u8,
    last_modified: std.Io.Timestamp,
    content: []u8,
};

pub fn read_everything(io: std.Io, alloc: std.mem.Allocator, map: *map_type) void {
    const cwd = std.Io.Dir.cwd();
    const www = cwd.openDir(io, "www/", .{.iterate = true}) catch unreachable;
    defer www.close(io);
    
    map.clearRetainingCapacity();

    var iter = www.iterate();
    while(iter.next(io) catch unreachable) |file| {
        std.debug.print("{s}\n", .{file.name});
        var page = alloc.create(Page) catch unreachable;
        page.name = alloc.dupe(u8, file.name) catch unreachable;
        page.content = www.readFileAlloc(io, file.name, alloc, .unlimited) catch unreachable;
        map.put(page.name, page.*) catch unreachable;
    }
}

pub fn render_header(writer: *std.Io.Writer) void {
    writer.print("<!DOCTYPE html>\n", .{}) catch unreachable;
    writer.print("<html>\n", .{}) catch unreachable;
    writer.print("<head>\n", .{}) catch unreachable;
    writer.print("<title>Edvard's homepage</title>\n", .{}) catch unreachable;
    writer.print("<style>{s}</style>", .{style}) catch unreachable;
    writer.print("</head>\n", .{}) catch unreachable;
    writer.print("<body>\n", .{}) catch unreachable;
}

pub fn render_footer(writer: *std.Io.Writer) void {
    writer.print("</body>\n", .{}) catch unreachable;
    writer.print("</html>\n", .{}) catch unreachable;
}

pub fn render_menu(writer: *std.Io.Writer, pages: map_type) void {
    writer.print("<div id=menu>", .{}) catch unreachable;
    writer.print("Menu\n", .{}) catch unreachable;
    var iter = pages.keyIterator();
    writer.print("<ul>", .{}) catch unreachable;
    while(iter.next()) |key| {
        writer.print("<div id=menuitem>", .{}) catch unreachable;
        writer.print("<li><a href={s}>{s}</a></li>\n", .{key.*, key.*}) catch unreachable;
        writer.print("</div>", .{}) catch unreachable;
    }
    writer.print("</ul>", .{}) catch unreachable;
    writer.print("</div>", .{}) catch unreachable;
}

pub fn render_page(writer: *std.Io.Writer, page: [] const u8, pages: map_type) void {
    writer.print("<main>\n", .{}) catch unreachable;
    var to_print: Page = undefined;
    if(std.mem.eql(u8, page[1..], "")) {
        to_print = pages.get("index") orelse unreachable;
    } else {
       to_print = pages.get(page[1..]) orelse unreachable;
    }
    writer.print("{s}", .{to_print.content}) catch unreachable;
    writer.print("</main>\n", .{}) catch unreachable;
}


pub fn main(init: std.process.Init) !void{
    std.debug.print("Hello world\n", .{});
    const io = init.io;
    const addr = try std.Io.net.IpAddress.resolve(io,"127.0.0.1", 8000);
    var server = try addr.listen(io, .{.reuse_address = true});

    const buf_size = 4096;
    var recv: [buf_size]u8 = undefined;
    var send: [buf_size]u8 = undefined;

    var pages = map_type.init(init.gpa);

    read_everything(io, init.gpa, &pages);

    while(true) {
        const stream = try server.accept(io);
        defer stream.close(io);
        var reader = stream.reader(io, &recv);
        var writer = stream.writer(io, &send);
        var serve: std.http.Server = .init(&reader.interface, &writer.interface);
        var request = serve.receiveHead() catch |err| {
            std.debug.print("Error receiving: {}\n", .{err});
            continue;
        };

        var responsewriter = std.Io.Writer.Allocating.init(init.gpa);
        defer responsewriter.deinit();
        read_everything(io, init.gpa, &pages);
        render_header(&responsewriter.writer);
        render_menu(&responsewriter.writer, pages);
        render_page(&responsewriter.writer, request.head.target, pages);
        render_footer(&responsewriter.writer);
        
        request.respond(responsewriter.written(), .{.keep_alive = false}) catch |err| {
            std.debug.print("Error responding: {}\n", .{err});
            continue;
        };
        
    }
}
