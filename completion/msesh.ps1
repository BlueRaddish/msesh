# PowerShell argument completer for msesh.
#
# Installed by .\install.cmd, or add it yourself to $PROFILE:
#     . C:\path\to\msesh\completion\msesh.ps1
#
# The candidate lists come from `msesh complete-names KIND`, one name per line —
# the same source the bash completion uses, so the two shells cannot drift
# apart. See completion/msesh.bash for why they are not parsed out of the
# human-readable listings.

Register-ArgumentCompleter -Native -CommandName msesh -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    function Get-MseshNames([string]$Kind) {
        # SilentlyContinue throughout: a completer that throws leaves the
        # console in a worse state than one that offers nothing.
        try { & msesh complete-names $Kind 2>$null } catch { @() }
    }

    $tokens = @($commandAst.CommandElements | Select-Object -Skip 1 |
                ForEach-Object { $_.ToString() })

    # Options that take a value, so the word after them is not the verb.
    $valued = @('-s', '-d', '-e', '-w', '--session', '--dir', '--effort',
                '--width', '--notify', '--windows')

    $cmd = $null
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($valued -contains $t) { $i++; continue }
        if ($t.StartsWith('-'))   { continue }
        # The word being typed is not yet a verb.
        if ($i -eq $tokens.Count - 1 -and $t -eq $wordToComplete) { break }
        $cmd = $t; break
    }

    # The token before the one being completed, for value completion.
    $prev = $null
    if ($tokens.Count -ge 1) {
        $last = $tokens[$tokens.Count - 1]
        if ($last -eq $wordToComplete -and $tokens.Count -ge 2) {
            $prev = $tokens[$tokens.Count - 2]
        } elseif ($last -ne $wordToComplete) {
            $prev = $last
        }
    }

    $candidates = @()

    switch -Regex ($prev) {
        '^(-e|--effort)$'  { $candidates = @('low','medium','high','xhigh','ladder') }
        '^(-s|--session)$' { $candidates = Get-MseshNames 'sessions' }
        '^(-w|--width|--notify|--windows|-d|--dir)$' { return }
        default {
            if (-not $cmd) {
                $candidates = Get-MseshNames 'commands'
            }
            elseif ($wordToComplete.StartsWith('-')) {
                $candidates = @('-s','-d','-e','-w','-n','--session','--dir',
                    '--effort','--width','--windows','--notify','--no-notify',
                    '--lazy','--ephemeral','--no-tab','--no-trust','--dry-run','--all')
                if ($cmd -eq 'send') { $candidates += '--no-enter' }
            }
            else {
                switch ($cmd) {
                    { $_ -in 'build','rebuild','add' } { $candidates = Get-MseshNames 'buildable' }
                    { $_ -in 'attach','restore' }      { $candidates = Get-MseshNames 'restorable' }
                    { $_ -in 'kill','status','send' }  { $candidates = Get-MseshNames 'sessions' }
                    'forget'                           { $candidates = Get-MseshNames 'manifests' }
                    'help'                             { $candidates = Get-MseshNames 'topics' }
                    'preset' {
                        $candidates = if ($prev -eq 'preset') {
                            @('list','show','make','remove','edit')
                        } elseif ($prev -in 'show','remove') { Get-MseshNames 'presets' } else { @() }
                    }
                    'layout' {
                        $candidates = if ($prev -eq 'layout') {
                            @('list','show','make','save','remove','edit')
                        } elseif ($prev -in 'show','remove','edit') { Get-MseshNames 'layouts' }
                          elseif ($prev -eq 'save') { Get-MseshNames 'manifests' } else { @() }
                    }
                }
            }
        }
    }

    $candidates |
        Where-Object { $_ -and $_.ToString().StartsWith($wordToComplete) } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_)
        }
}
