package mcp

// Streamable HTTP 传输（最小实现）：POST 一条 JSON-RPC，回一条 application/json。
// 不开 SSE 流（GET 返回 405，规范允许）。单线程、逐个连接处理，适合个人自用。
// 鉴权：令牌放在路径 /mcp/<token>，或请求头 Authorization: Bearer <token>。

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_BODY :: 1 << 20

serve_http :: proc(s: ^Server, port: int, token: string) -> bool {
	s.persist = context.allocator
	ep := net.Endpoint{address = net.IP4_Loopback, port = port}
	sock, err := net.listen_tcp(ep)
	if err != nil {
		log("listen 失败:", err)
		return false
	}
	log(fmt.tprintf("odin-gua HTTP 监听 127.0.0.1:%d  路径 /mcp%s", port, "/<token>" if token != "" else ""))
	for {
		c, _, aerr := net.accept_tcp(sock)
		if aerr != nil { continue }
		serve_conn(s, c, token)
		net.close(c)
		free_all(context.temp_allocator)
	}
}

@(private)
Request :: struct {
	method, path, body: string,
	headers:            map[string]string, // 小写键
}

@(private)
read_request :: proc(c: net.TCP_Socket) -> (req: Request, ok: bool) {
	buf := make([dynamic]u8, 0, 8192, context.temp_allocator)
	chunk: [8192]u8
	head_end := -1
	for head_end < 0 {
		n, err := net.recv_tcp(c, chunk[:])
		if err != nil || n == 0 { return }
		append(&buf, ..chunk[:n])
		head_end = strings.index(string(buf[:]), "\r\n\r\n")
		if len(buf) > 65536 && head_end < 0 { return }
	}
	head := string(buf[:head_end])
	lines := strings.split(head, "\r\n", context.temp_allocator)
	parts := strings.fields(lines[0], context.temp_allocator)
	if len(parts) < 2 { return }
	req.method, req.path = parts[0], parts[1]
	req.headers = make(map[string]string, context.temp_allocator)
	for l in lines[1:] {
		i := strings.index_byte(l, ':')
		if i < 0 { continue }
		req.headers[strings.to_lower(strings.trim_space(l[:i]), context.temp_allocator)] = strings.trim_space(l[i + 1:])
	}
	want := 0
	if cl, has := req.headers["content-length"]; has {
		v, vok := strconv.parse_int(cl)
		if !vok || v < 0 || v > MAX_BODY { return }
		want = v
	}
	for len(buf) - (head_end + 4) < want {
		n, err := net.recv_tcp(c, chunk[:])
		if err != nil || n == 0 { return }
		append(&buf, ..chunk[:n])
	}
	req.body = string(buf[head_end + 4:][:want])
	return req, true
}

@(private)
reply :: proc(c: net.TCP_Socket, status: string, ctype, body: string, extra := "") {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n", status, len(body))
	if ctype != "" { fmt.sbprintf(&b, "Content-Type: %s\r\n", ctype) }
	strings.write_string(&b, extra)
	strings.write_string(&b, "\r\n")
	strings.write_string(&b, body)
	data := transmute([]u8)strings.to_string(b)
	for len(data) > 0 {
		n, err := net.send_tcp(c, data)
		if err != nil || n <= 0 { return }
		data = data[n:]
	}
}

@(private)
serve_conn :: proc(s: ^Server, c: net.TCP_Socket, token: string) {
	req, ok := read_request(c)
	if !ok {
		reply(c, "400 Bad Request", "text/plain", "bad request")
		return
	}
	path := req.path
	if q := strings.index_byte(path, '?'); q >= 0 { path = path[:q] }
	authed := token == ""
	if token != "" {
		if path == strings.concatenate({"/mcp/", token}, context.temp_allocator) { authed = true }
		if req.headers["authorization"] == strings.concatenate({"Bearer ", token}, context.temp_allocator) { authed = true }
		if path == "/mcp" || path == "/mcp/" || strings.has_prefix(path, "/mcp/") { path = "/mcp" }
	}
	if path == "/healthz" {
		reply(c, "200 OK", "text/plain", "ok")
		return
	}
	if path != "/mcp" {
		reply(c, "404 Not Found", "text/plain", "not found")
		return
	}
	if !authed {
		reply(c, "401 Unauthorized", "application/json", `{"error":"unauthorized"}`, "WWW-Authenticate: Bearer\r\n")
		return
	}
	switch req.method {
	case "POST":
		body := strings.trim_space(req.body)
		if strings.has_prefix(body, "[") {
			reply(c, "400 Bad Request", "application/json", error_reply("null", ERR_PARSE, "Batch not supported", ""))
			return
		}
		out, has := handle(s, body)
		if has {
			reply(c, "200 OK", "application/json", out)
		} else {
			reply(c, "202 Accepted", "", "")
		}
	case "DELETE":
		reply(c, "200 OK", "", "")
	case:
		reply(c, "405 Method Not Allowed", "text/plain", "use POST", "Allow: POST, DELETE\r\n")
	}
}
