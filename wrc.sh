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
    local kill_uri="http://${server}:${port}/kill"
    local body
    if [[ -n "$workdir" ]]; then
        body=$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1], "workdir": sys.argv[2]}))' "$command" "$workdir")
    else
        body=$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$command")
    fi

    printf '\033[36mWRC: Sending to %s:%s ...\033[0m\n' "$server" "$port"

    local headers_file
    headers_file=$(mktemp)

    local exit_code=1
    local remote_pid=""

    # On Ctrl+C: send /kill then clean up
    _wrc_kill() {
        if [[ -n "$remote_pid" ]]; then
            printf '\n\033[33mWRC: Sending kill for PID %s ...\033[0m\n' "$remote_pid"
            curl -sS -X POST \
                -H 'Content-Type: application/json' \
                -d "{\"pid\": $remote_pid}" \
                "$kill_uri" > /dev/null 2>&1
        fi
    }
    trap '_wrc_kill' INT

    # Stream the response; parse each NDJSON line as it arrives
    local line
    while IFS= read -r line; do
        # Extract remote PID from response headers (available after first line)
        if [[ -z "$remote_pid" && -f "$headers_file" ]]; then
            remote_pid=$(grep -i '^X-WRC-PID:' "$headers_file" | tr -d '\r' | awk '{print $2}')
        fi

        local type
        type=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print("exit" if "exit_code" in d else d.get("stream", ""))
' "$line" 2>/dev/null)

        if [[ "$type" == "exit" ]]; then
            exit_code=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["exit_code"])' "$line")
        elif [[ "$type" == "stderr" ]]; then
            printf '\033[31m%s\033[0m\n' "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["line"])' "$line")"
        else
            python3 -c 'import json,sys; print(json.loads(sys.argv[1])["line"])' "$line"
        fi
    done < <(curl -sS --no-progress-meter --no-buffer \
        -X POST \
        -H 'Content-Type: application/json' \
        -d "$body" \
        -D "$headers_file" \
        "$uri" 2>&1)

    local curl_status=$?
    rm -f "$headers_file"
    trap - INT

    if [[ $curl_status -ne 0 ]]; then
        printf '\033[31mWRC: Connection failed\033[0m\n' >&2
        return 1
    fi

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
