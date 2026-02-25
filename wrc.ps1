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

    $uri     = "http://${Server}:${Port}/run"
    $killUri = "http://${Server}:${Port}/kill"
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json @{command = $Command} -Compress)
    )

    Write-Host "WRC: Sending to ${Server}:${Port} ..." -ForegroundColor Cyan

    $remotePid = $null
    $exitCode  = 1

    try {
        # Connect with retries
        $response   = $null
        $maxRetries = 10
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                $request = [System.Net.HttpWebRequest]::Create($uri)
                $request.Method      = 'POST'
                $request.ContentType = 'application/json'
                $request.Timeout     = -1  # No timeout - wait as long as the command runs

                $request.ContentLength = $bodyBytes.Length
                $reqStream = $request.GetRequestStream()
                $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $reqStream.Close()

                $response = $request.GetResponse()
                break
            } catch {
                if ($attempt -lt $maxRetries) {
                    Write-Host "WRC: Attempt $attempt/$maxRetries failed, retrying in 1s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                } else {
                    throw
                }
            }
        }

        $remotePid = $response.Headers['X-WRC-PID']
        $reader    = [System.IO.StreamReader]::new($response.GetResponseStream(), [System.Text.Encoding]::UTF8)

        # Register Ctrl+C handler to send /kill
        $killBlock = {
            if ($remotePid) {
                Write-Host "`nWRC: Sending kill for PID $remotePid ..." -ForegroundColor Yellow
                try {
                    $kr = [System.Net.WebRequest]::Create($killUri)
                    $kr.Method      = 'POST'
                    $kr.ContentType = 'application/json'
                    $kb = [System.Text.Encoding]::UTF8.GetBytes(("{""pid"":$remotePid}"))
                    $kr.ContentLength = $kb.Length
                    $ks = $kr.GetRequestStream(); $ks.Write($kb, 0, $kb.Length); $ks.Close()
                    $kr.GetResponse().Close()
                } catch {}
            }
        }
        [Console]::TreatControlCAsInput = $false
        $null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action $killBlock -SourceIdentifier 'WRC.Kill'

        # Read and print NDJSON lines as they arrive
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not $line) { continue }

            $obj = $line | ConvertFrom-Json

            if ($null -ne $obj.exit_code) {
                $exitCode = $obj.exit_code
            } elseif ($obj.stream -eq 'stderr') {
                Write-Host $obj.line -ForegroundColor Red
            } else {
                Write-Host $obj.line
            }
        }

        $reader.Close()
        $response.Close()
    }
    catch {
        Write-Host "WRC: Connection failed - $_" -ForegroundColor Red
        return 1
    }
    finally {
        Unregister-Event -SourceIdentifier 'WRC.Kill' -ErrorAction SilentlyContinue
    }

    if ($exitCode -eq 0) {
        Write-Host "WRC: Done (exit_code=0)" -ForegroundColor Green
    } else {
        Write-Host "WRC: Done (exit_code=$exitCode)" -ForegroundColor Red
    }

    return $exitCode
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
