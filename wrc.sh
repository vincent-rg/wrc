#!/usr/bin/env bash
# wrc.sh - Remote command launcher client (Linux)
#
# Usage:
#   Direct execution: ./wrc.sh -c <cmd> -s <ip> [-p <port>] [-d <dir>]
#
#   Source and use:   source ./wrc.sh
#                     wrc -c <cmd> -s <ip> [-p <port>] [-d <dir>]
#
# Options:
#   -c, --command   : Command to execute on the WRC server
#   -s, --server    : IP address of the WRC server (wrc_server.py)
#   -p, --port      : Server port (default: 9000)
#   -d, --directory : Working directory on the server (default: server's cwd)

wrc() {
    local command=""
    local server=""
    local port=9000
    local workdir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--command)   command="$2";  shift 2 ;;
            -s|--server)    server="$2";   shift 2 ;;
            -p|--port)      port="$2";     shift 2 ;;
            -d|--directory) workdir="$2";  shift 2 ;;
            *) echo "WRC: Unknown option: $1" >&2; return 1 ;;
        esac
    done

    if [[ -z "$command" || -z "$server" ]]; then
        echo "WRC - Remote Command Launcher"
        echo "Usage: ./wrc.sh -c <cmd> -s <ip> [-p <port>] [-d <dir>]"
        echo ""
        echo "Options:"
        echo "  -c, --command   : Command to execute on the WRC server"
        echo "  -s, --server    : IP address of wrc_server.py"
        echo "  -p, --port      : Server port (default: 9000)"
        echo "  -d, --directory : Working directory on the server (default: server's cwd)"
        echo ""
        echo "To use as a function, source this script:"
        echo "   source ./wrc.sh"
        echo "Then call: wrc -c <cmd> -s <ip> [-p <port>] [-d <dir>]"
        return 1
    fi

    local uri="http://${server}:${port}/run"
    local body
    if [[ -n "$workdir" ]]; then
        body=$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1], "workdir": sys.argv[2]}))' "$command" "$workdir")
    else
        body=$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$command")
    fi

    printf '\033[36mWRC: Sending to %s:%s ...\033[0m\n' "$server" "$port"

    local response
    response=$(curl -sS -X POST \
        -H 'Content-Type: application/json' \
        -d "$body" \
        "$uri")

    if [[ $? -ne 0 ]]; then
        printf '\033[31mWRC: Connection failed\033[0m\n' >&2
        return 1
    fi

    local exit_code
    exit_code=$(printf '%s' "$response" | jq -r '.exit_code')

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
