# wrc.ps1 - Remote command launcher client
#
# Usage:
#   Direct execution: .\wrc.ps1 -Command <cmd> -Server <ip> [-Port <port>]
#
#   Source and use:   . .\wrc.ps1
#                     wrc -Command <cmd> -Server <ip> [-Port <port>]
#
# Options:
#   -Command  : Command to execute inside WSB
#   -Server   : IP address of the WRC server (wrc_server.py) running in WSB
#   -Port     : Server port (default: 9000)

function wrc {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Command,

        [Parameter(Mandatory=$true)]
        [string]$Server,

        [int]$Port = 9000
    )

    $uri = "http://${Server}:${Port}/run"
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json @{command = $Command} -Compress)
    )

    Write-Host "WRC: Sending to ${Server}:${Port} ..." -ForegroundColor Cyan

    try {
        $request = [System.Net.WebRequest]::Create($uri)
        $request.Method = 'POST'
        $request.ContentType = 'application/json'
        $request.Timeout = -1  # No timeout - wait as long as the command runs
        $request.ContentLength = $bodyBytes.Length

        $stream = $request.GetRequestStream()
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
        $stream.Close()

        $response = $request.GetResponse()
        $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
        $result = $reader.ReadToEnd() | ConvertFrom-Json
        $reader.Close()
        $response.Close()
    }
    catch {
        Write-Host "WRC: Connection failed - $_" -ForegroundColor Red
        return 1
    }

    if ($result.exit_code -eq 0) {
        Write-Host "WRC: Done (exit_code=0)" -ForegroundColor Green
    } else {
        Write-Host "WRC: Done (exit_code=$($result.exit_code))" -ForegroundColor Red
    }

    return $result.exit_code
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -gt 0) {
        $exitCode = wrc @args
        exit $exitCode
    } else {
        Write-Host "WRC - Remote Command Launcher" -ForegroundColor Green
        Write-Host "Usage: .\wrc.ps1 -Command <cmd> -Server <ip> [-Port <port>]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  -Command  : Command to execute inside WSB" -ForegroundColor Gray
        Write-Host "  -Server   : IP address of wrc_server.py running in WSB" -ForegroundColor Gray
        Write-Host "  -Port     : Server port (default: 9000)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To use as a function, source this script:" -ForegroundColor Cyan
        Write-Host "   . .\wrc.ps1" -ForegroundColor White
        Write-Host "Then call: wrc -Command <cmd> -Server <ip> [-Port <port>]" -ForegroundColor White
    }
}
# When sourced: load silently
