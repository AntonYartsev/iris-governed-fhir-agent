#!/bin/sh
# Demo MCP call with handshake, call and print the payload as result
#   ./scripts/mcp-call.sh FindPatient '{"name":"Kuphal"}'

MCP=${MCP_URL:-http://localhost:8080/mcp}
CT='Content-Type: application/json'
AC='Accept: application/json, text/event-stream'

SID=$(curl -s -D- -o /dev/null "$MCP" -H "$CT" -H "$AC" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-call","version":"0"}}}' \
  | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
[ -n "$SID" ] || { echo "no MCP session from $MCP" >&2; exit 1; }
curl -s -o /dev/null "$MCP" -H "$CT" -H "$AC" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
curl -s "$MCP" -H "$CT" -H "$AC" -H "Mcp-Session-Id: $SID" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_governed-fhir_$1\",\"arguments\":$2}}" \
  | sed -n 's/^data: //p' | jq -r '.result.content[0].text'
