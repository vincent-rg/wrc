#!/usr/bin/env bash
# wrc.sh - Remote command launcher client (Linux)
#
# Usage:
#   Direct execution: ./wrc.sh -c <cmd> -s <ip> [-p <port>]
#
#   Source and use:   source ./wrc.sh
#                     wrc -c <cmd> -s <ip> [-p <port>]
#
# Options:
#   -c, --command : Command to execute on the WRC server
#   -s, --server  : IP address of the WRC server (wrc_server.py)
#   -p, --port    : Server port (default: 9000)

wrc() {
    local command=""
    local server=""
    local port=9000

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--command) command="$2"; shift 2 ;;
            -s|--server)  server="$2";  shift 2 ;;
            -p|--port)    port="$2";    shift 2 ;;
            *) echo "WRC: Unknown option: $1" >&2; return 1 ;;
        esac
    done

    if [[ -z "$command" || -z "$server" ]]; then
        echo "WRC - Remote Command Launcher"
        echo "Usage: ./wrc.sh -c <cmd> -s <ip> [-p <port>]"
        echo ""
        echo "Options:"
        echo "  -c, --command : Command to execute on the WRC server"
        echo "  -s, --server  : IP address of wrc_server.py"
        echo "  -p, --port    : Server port (default: 9000)"
        echo ""
        echo "To use as a function, source this script:"
        echo "   source ./wrc.sh"
        echo "Then call: wrc -c <cmd> -s <ip> [-p <port>]"
        return 1
    fi

    local uri="http://${server}:${port}/run"
    local body
    body=$(printf '{"command":%s}' "$(printf '%s' "$command" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")

    printf '\033[36mWRC: Sending to %s:%s ...\033[0m\n' "$server" "$port"

    local response
    response=$(curl -sS --no-progress-meter \
        -X POST \
        -H 'Content-Type: application/json' \
        -d "$body" \
        "$uri" 2>&1)

    if [[ $? -ne 0 ]]; then
        printf '\033[31mWRC: Connection failed - %s\033[0m\n' "$response" >&2
        return 1
    fi

    local exit_code
    exit_code=$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["exit_code"])')

    if [[ "$exit_code" -eq 0 ]]; then
        printf '\033[32mWRC: Done (exit_code=0)\033[0m\n'
    else
        printf '\033[31mWRC: Done (exit_code=%s)\033[0m\n' "$exit_code"
    fi

    return "$exit_code"
}

# Run directly if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    wrc "$@"
    exit $?
fi
# When sourced: load silently
