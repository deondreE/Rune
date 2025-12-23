#+feature dynamic-literals
package lsp
import "../"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:thread"

LSP_Message :: struct {
	jsonrpc: string,
	id:      Maybe(json.Value),
	method:  string,
	params:  json.Object,
	result:  json.Object,
	erorr:   Maybe(LSP_Error),
}

LSP_Error :: struct {
	code:    int,
	message: string,
	data:    Maybe(json.Value),
}

Position :: struct {
	line:      int,
	character: int,
}

Range :: struct {
	start: Position,
	end:   Position,
}

Text_Doucment_Indentifier :: struct {
	uri: string,
}

Versioned_Text_Document_Identifier :: struct {
	uri:     string,
	version: int,
}

Diagnostic_Severity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

Diagnostic :: struct {
	range:    Range,
	severity: Diagnostic_Severity,
	code:     string,
	source:   string,
	message:  string,
}

// Kind of completion item.
Completion_Item_Kind :: enum {
	Text          = 1,
	Method        = 2,
	Function      = 3,
	Constructor   = 4,
	Field         = 5,
	Variable      = 6,
	Class         = 7,
	Interface     = 8,
	Module        = 9,
	Property      = 10,
	Unit          = 11,
	Value         = 12,
	Enum          = 13,
	Keyword       = 14,
	Snippet       = 15,
	Color         = 16,
	File          = 17,
	Reference     = 18,
	Folder        = 19,
	EnumMember    = 20,
	Constant      = 21,
	Struct        = 22,
	Event         = 23,
	Operator      = 24,
	TypeParameter = 25,
}

Completion_Item :: struct {
	label:         string,
	kind:          Completion_Item_Kind,
	detail:        string,
	documentation: string,
	insert_text:   string,
	filter_text:   string,
	sort_text:     string,
}

Hover :: struct {
	contents: string,
	range:    Maybe(Range),
}

LSP_Client :: struct {
	allocator:           mem.Allocator,
	process:             os2.Process,
	stdin:               ^os2.File,
	stdout:              ^os2.File,
	initialized:         bool,
	server_capabilities: json.Object,
	pending_requests:    map[int]LSP_Request_Context,
	next_request_id:     int,
	message_queue:       [dynamic]LSP_Message,
	reader_thread:       ^thread.Thread,
	running:             bool,
	document_uri:        string,
	document_version:    int,
}

LSP_Request_Context :: struct {
	id:       int,
	method:   string,
	callback: proc(result: json.Object, error: Maybe(LSP_Error)),
}

lsp_client_init :: proc(client: ^LSP_Client, allocator := context.allocator) -> bool {
	client.allocator = allocator
	client.next_request_id = 1
	client.pending_requests = make(map[int]LSP_Request_Context, allocator)
	client.message_queue = make([dynamic]LSP_Message, allocator)
	client.running = false
	client.initialized = false
	return true
}

lsp_client_start :: proc(client: ^LSP_Client, server_command: string, args: []string) -> bool {
	context.allocator = client.allocator

	// Create pipes for stdin/stdout
	stdin_read, stdin_write, _ := os2.pipe()
	stdout_read, stdout_write, _ := os2.pipe()

	command := make([dynamic]string, client.allocator)
	append(&command, server_command)
	for arg in args {
		append(&command, arg)
	}

	process_desc := os2.Process_Desc {
		command = command[:],
		stdin   = stdin_read,
		stdout  = stdout_write,
		stderr  = os2.stderr,
	}

	process, err := os2.process_start(process_desc)
	if err != nil {
		log.errorf("Failed to start LSP server: %v", err)
		return false
	}

	client.process = process
	client.stdin = stdin_write
	client.stdout = stdout_read
	client.running = true

	// Start reader thread
	client.reader_thread = thread.create_and_start_with_poly_data(client, lsp_reader_thread)

	return true
}

lsp_reader_thread :: proc(client: ^LSP_Client) {
	context.allocator = client.allocator

	buffer := make([dynamic]u8, client.allocator)
	defer delete(buffer)

	for client.running {
		// Read headers
		headers := make(map[string]string, client.allocator)
		defer delete(headers)

		for {
			line := lsp_read_line(client.stdout, &buffer) or_break
			if len(line) == 0 {
				break
			}

			parts := strings.split(line, ": ", client.allocator)
			if len(parts) == 2 {
				headers[parts[0]] = parts[1]
			}
		}

		// Get content length
		content_length_str, ok := headers["Content-Length"]
		if !ok {
			continue
		}

		content_length, _ := strconv.parse_int(content_length_str)

		// Read content
		content_buf := make([]u8, content_length, client.allocator)
		defer delete(content_buf)

		n, err := os2.read(client.stdout, content_buf)
		if err != nil || n != content_length {
			log.errorf("Failed to read LSP message content")
			continue
		}

		// Parse JSON
		msg, parse_err := lsp_parse_message(string(content_buf), client.allocator)
		if parse_err != nil {
			log.errorf("Failed to parse LSP message: %v", parse_err)
			continue
		}

		// Handle message
		lsp_handle_message(client, msg)
	}
}

lsp_read_line :: proc(handle: ^os2.File, buffer: ^[dynamic]u8) -> (string, bool) {
	clear(buffer)

	byte_buf: [1]u8
	for {
		n, err := os2.read(handle, byte_buf[:])
		if err != nil || n == 0 {
			return "", false
		}

		if byte_buf[0] == '\n' {
			// Remove trailing \r if present
			if len(buffer) > 0 && buffer[len(buffer) - 1] == '\r' {
				pop(buffer)
			}
			return string(buffer[:]), true
		}

		append(buffer, byte_buf[0])
	}
}

lsp_parse_message :: proc(
	content: string,
	allocator := context.allocator,
) -> (
	LSP_Message,
	json.Error,
) {
	msg := LSP_Message{}

	data, err := json.parse_string(content, nil, false, allocator)
	if err != nil {
		return msg, err
	}

	obj := data.(json.Object) or_else {}

	msg.jsonrpc = obj["jsonrpc"].(json.String) or_else "2.0"
	msg.id = obj["id"]
	msg.method = obj["method"].(json.String) or_else ""
	msg.params = obj["params"].(json.Object) or_else {}
	msg.result = obj["result"].(json.Object) or_else {}

	if error_obj, has_error := obj["error"].(json.Object); has_error {
		lsp_err := LSP_Error {
			code    = int(error_obj["code"].(json.Integer) or_else 0),
			message = error_obj["message"].(json.String) or_else "",
		}
		msg.erorr = lsp_err
	}

	return msg, nil
}

lsp_handle_message :: proc(client: ^LSP_Client, msg: LSP_Message) {
	// Response to a request
	if id, ok := msg.id.?; ok {
		request_id := int(id.(json.Integer))

		if ctx, found := client.pending_requests[request_id]; found {
			if ctx.callback != nil {
				ctx.callback(msg.result, msg.erorr)
			}
			delete_key(&client.pending_requests, request_id)
		}
		return
	}

	// Notification or request from server
	switch msg.method {
	case "textDocument/publishDiagnostics":
		lsp_handle_diagnostics(client, msg.params)
	case "window/showMessage":
		lsp_handle_show_message(client, msg.params)
	}
}

lsp_send_request :: proc(
	client: ^LSP_Client,
	method: string,
	params: json.Object,
	callback: proc(result: json.Object, error: Maybe(LSP_Error)) = nil,
) -> int {
	context.allocator = client.allocator

	request_id := client.next_request_id
	client.next_request_id += 1

	request := json.Object {
		"jsonrpc" = json.String("2.0"),
		"id"      = json.Integer(request_id),
		"method"  = json.String(method),
		"params"  = params,
	}

	// Store callback
	if callback != nil {
		client.pending_requests[request_id] = LSP_Request_Context {
			id       = request_id,
			method   = method,
			callback = callback,
		}
	}

	// Serialize and send
	lsp_write_message(client, request)

	return request_id
}

lsp_send_notification :: proc(client: ^LSP_Client, method: string, params: json.Object) {
	context.allocator = client.allocator

	notification := json.Object {
		"jsonrpc" = json.String("2.0"),
		"method"  = json.String(method),
		"params"  = params,
	}

	lsp_write_message(client, notification)
}

lsp_write_message :: proc(client: ^LSP_Client, obj: json.Object) {
	context.allocator = client.allocator

	content, marshal_err := json.marshal(obj, {}, client.allocator)
	if marshal_err != nil {
		log.errorf("Failed to marshal LSP message: %v", marshal_err)
		return
	}
	defer delete(content)

	header := fmt.tprintf("Content-Length: %d\r\n\r\n", len(content))

	os2.write_string(client.stdin, header)
	os2.write(client.stdin, transmute([]u8)content)
}

lsp_initialize :: proc(client: ^LSP_Client, root_uri: string) {
	params := json.Object {
		"processId" = json.Integer(os2.get_pid()),
		"rootUri" = json.String(root_uri),
		"capabilities" = json.Object {
			"textDocument" = json.Object {
				"synchronization" = json.Object {
					"didOpen" = json.Boolean(true),
					"didChange" = json.Boolean(true),
					"didSave" = json.Boolean(true),
				},
				"completion" = json.Object {
					"completionItem" = json.Object{"snippetSupport" = json.Boolean(true)},
				},
				"hover" = json.Object{"contentFormat" = json.Array{json.String("plaintext")}},
			},
		},
	}

	lsp_send_request(
		client,
		"initialize",
		params,
		proc(result: json.Object, error: Maybe(LSP_Error)) {
			// Handle initialization response
		},
	)

	// Send initialized notification
	lsp_send_notification(client, "initialized", {})
	client.initialized = true
}

lsp_did_open :: proc(client: ^LSP_Client, uri: string, language_id: string, text: string) {
	client.document_uri = uri
	client.document_version = 1

	params := json.Object {
		"textDocument" = json.Object {
			"uri" = json.String(uri),
			"languageId" = json.String(language_id),
			"version" = json.Integer(client.document_version),
			"text" = json.String(text),
		},
	}

	lsp_send_notification(client, "textDocument/didOpen", params)
}

lsp_did_change :: proc(client: ^LSP_Client, uri: string, text: string) {
	client.document_version += 1

	params := json.Object {
		"textDocument" = json.Object {
			"uri" = json.String(uri),
			"version" = json.Integer(client.document_version),
		},
		"contentChanges" = json.Array{json.Object{"text" = json.String(text)}},
	}

	lsp_send_notification(client, "textDocument/didChange", params)
}

lsp_request_completion :: proc(
	client: ^LSP_Client,
	uri: string,
	line: int,
	character: int,
	callback: proc(items: []Completion_Item),
) {
	params := json.Object {
		"textDocument" = json.Object{"uri" = json.String(uri)},
		"position" = json.Object {
			"line" = json.Integer(line),
			"character" = json.Integer(character),
		},
	}

	lsp_send_request(
		client,
		"textDocument/completion",
		params,
		proc(result: json.Object, error: Maybe(LSP_Error)) {
			// Parse completion items and call callback
		},
	)
}

lsp_handle_diagnostics :: proc(client: ^LSP_Client, params: json.Object) {
	uri := params["uri"].(json.String) or_else ""
	diagnostics := params["diagnostics"].(json.Array) or_else {}

	log.infof("Received %d diagnostics for %s", len(diagnostics), uri)
}

lsp_handle_show_message :: proc(client: ^LSP_Client, params: json.Object) {
	message := params["message"].(json.String) or_else ""
	log.infof("LSP Message: %s", message)
}

lsp_client_shutdown :: proc(client: ^LSP_Client) {
	if !client.running {
		return
	}

	lsp_send_request(client, "shutdown", {})
	lsp_send_notification(client, "exit", {})

	client.running = false

	if client.reader_thread != nil {
		thread.destroy(client.reader_thread)
	}

	os2.close(client.stdin)
	os2.close(client.stdout)
	t, _ := os2.process_wait(client.process)

	delete(client.pending_requests)
	delete(client.message_queue)
}

editor_init_lsp :: proc(
	editor: ^editor.Editor,
	server_command: string,
	language_id: string,
) -> bool {
	lsp_client := new(LSP_Client, editor.allocator)

	if !lsp_client_init(lsp_client, editor.allocator) {
		return false
	}

	if !lsp_client_start(lsp_client, server_command, {}) {
		return false
	}

	root_uri := fmt.tprintf("file://%s", os.get_current_directory())
	lsp_initialize(lsp_client, root_uri)

	text := gap_buffer_to_string(&editor.gap_buffer)
	uri := "file:///untitled.txt"
	lsp_did_open(lsp_client, uri, language_id, text)

	return true
}

editor_notify_lsp_change :: proc(editor: ^editor.Editor, lsp_client: ^LSP_Client) {
	text := gap_buffer_to_string(&editor.gap_buffer)
	lsp_did_change(lsp_client, lsp_client.document_uri, text)
}

gap_buffer_to_string :: proc(buffer: ^editor.Gap_Buffer) -> string {
	// Implementation depends on your Gap_Buffer structure
	return ""
}
