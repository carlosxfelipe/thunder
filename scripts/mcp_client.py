import json
import os
import random
import socket
import sys
import threading
import time
import urllib.request

"""
MCP Client Script for AI Agents
===============================
This script is used by AI assistants (like Antigravity) to interact with Thunder's
local Model Context Protocol (MCP) server running on port 8888. 

Since AI execution environments often lack a native SSE (Server-Sent Events) HTTP client, 
this lightweight script bridges the gap: it opens a persistent SSE connection to listen 
for responses and simultaneously sends JSON-RPC tool calls via HTTP POST.

Usage: 
  python mcp_client.py <tool_name> [json_args]

You can override the default port (8888) by setting the MCP_PORT environment variable:
  MCP_PORT=9000 python mcp_client.py <tool_name>
"""


def listen_sse(tool_name, tool_args, port=8888):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("localhost", port))
    except ConnectionRefusedError:
        print('{"error": "Connection refused"}')
        sys.exit(1)

    s.sendall(f"GET /sse HTTP/1.1\r\nHost: localhost:{port}\r\n\r\n".encode("utf-8"))

    request_id = random.randint(100, 999)

    def send_post():
        time.sleep(0.5)
        payload = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": tool_args},
            "id": request_id,
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"http://localhost:{port}/message",
            data=data,
            headers={"Content-Length": len(data)},
        )
        try:
            urllib.request.urlopen(req)
        except Exception:
            pass  # Server might close connection immediately after response

    threading.Thread(target=send_post).start()

    buffer = b""
    while True:
        try:
            chunk = s.recv(4096)
        except Exception:
            break
        if not chunk:
            break
        buffer += chunk
        if b"event: message" in buffer:
            lines = buffer.decode("utf-8", errors="ignore").split("\n")
            for line in lines:
                if line.startswith("data:"):
                    json_str = line[5:].strip()
                    try:
                        resp = json.loads(json_str)
                        if resp.get("id") == request_id:
                            print(json.dumps(resp, indent=2))
                            s.close()
                            return
                    except Exception:
                        pass


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python mcp_client.py <tool_name> [json_args]")
        sys.exit(1)

    tool_name = sys.argv[1]
    tool_args = {}
    if len(sys.argv) >= 3:
        try:
            tool_args = json.loads(sys.argv[2])
        except Exception:
            pass

    port = int(os.environ.get("MCP_PORT", 8888))
    listen_sse(tool_name, tool_args, port=port)
