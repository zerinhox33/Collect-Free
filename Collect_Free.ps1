#Requires -RunAsAdministrator
<#
    Collect Free - Menu Interativo
    Foco: Limpeza, privacidade e otimizacao total.
    Requer: Windows 10/11 | Admin
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# ─── REGISTRY HELPER ──────────────────────────────────────────────────────────
function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
    } catch { }
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force } catch { }
}

# ─── OUTPUT HELPER ────────────────────────────────────────────────────────────
function Write-Center {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'White',
        [switch]$NoNewline
    )
    $width = $Host.UI.RawUI.WindowSize.Width
    if ($width -le 0) { $width = 80 }
    $pad     = [Math]::Max([int](($width - $Text.Length) / 2), 0)
    $padding = ' ' * $pad
    if ($NoNewline) {
        Write-Host ($padding + $Text) -ForegroundColor $Color -NoNewline
    } else {
        Write-Host ($padding + $Text) -ForegroundColor $Color
    }
}

# ─── LOG ──────────────────────────────────────────────────────────────────────
$script:LogPath = "C:\Collect\logs_Collect\Collect_Free_$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).log"
function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Msg"
    try {
        $dir = Split-Path $script:LogPath
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $script:LogPath -Value $line
    } catch { }
    switch ($Level) {
        'WARN'  { Write-Center "[!] $Msg" 'Yellow' }
        'ERROR' { Write-Center "[X] $Msg" 'Red'    }
        default { Write-Center "$Msg"     'Gray'    }
    }
}


# ─── GITHUB (repositório público) ────────────────────────────────────────────
$script:GHBase    = 'https://raw.githubusercontent.com/Zerinhox33/Collect-Free/main/apps'
$script:GHRelease = 'https://github.com/Zerinhox33/Collect-Free/releases/download'
$script:CollectDir   = 'C:\Collect'
$script:Version      = '1.0'
$script:GHVersionUrl = 'https://raw.githubusercontent.com/Zerinhox33/Collect-Free/main/version.txt'

# Detecta ponteiro Git LFS ou corpo de erro (HTML/JSON) salvo no lugar do binario.
function Test-BadDownload {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
        if ((Get-Item -LiteralPath $Path).Length -le 0) { return $true }
        $fs  = [IO.File]::OpenRead($Path)
        $buf = New-Object 'byte[]' 128
        $n   = $fs.Read($buf, 0, 128)
        $fs.Dispose()
        if ($n -le 0) { return $true }
        $head = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
        if ($head -like 'version https://git-lfs.github.com/spec*') { return $true }
        if ($head -match '^\s*(<!DOCTYPE|<html|\{"message")') { return $true }
        return $false
    } catch { return $true }   # fail-closed: arquivo ilegivel/travado = trata como ruim (re-baixa)
}

# ─── DOWNLOAD HÍBRIDO ─────────────────────────────────────────────────────────
function Invoke-HybridDownload {
    param(
        [string]$WingetId,      # ID do Winget (vazio = pular Winget)
        [string]$FileName,      # Nome do arquivo no GitHub
        [string]$ReleaseTag     # Tag da release (vazio = raw main)
    )

    $dest = Join-Path $script:CollectDir $FileName

    # Se ja existe, pula
    if (Test-Path -LiteralPath $dest) {
        if (-not (Test-BadDownload $dest)) {
            Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
            Write-Log "Ja existe: $FileName"
            return
        }
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }

    # 1. Tenta Winget
    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget: instalando $WingetId..."
        & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Winget OK: $WingetId"
            return
        }
        Write-Log "Winget falhou para $WingetId -- tentando GitHub..." 'WARN'
    }

    # 2. Fallback GitHub (repo público -- sem autenticação)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288

        $enc = [Uri]::EscapeDataString($FileName)
        if ($ReleaseTag) {
            Invoke-WebRequest -Uri "$script:GHRelease/$ReleaseTag/$enc" -OutFile $dest -UseBasicParsing -ErrorAction Stop | Out-Null
        } else {
            # repo PUBLICO sem LFS -> raw serve o binario real direto
            Invoke-WebRequest -Uri "$script:GHBase/$enc" -OutFile $dest -UseBasicParsing -ErrorAction Stop | Out-Null
        }

        if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0 -and -not (Test-BadDownload $dest)) {
            Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
            Write-Log "GitHub OK: $FileName"
        } else {
            Write-Log "Falha ao baixar (conteudo invalido): $FileName" 'WARN'
        }
    } catch {
        Write-Log "Erro GitHub ($FileName): $($_.Exception.Message)" 'WARN'
    }
}

# ─── TELA DE DOWNLOAD ─────────────────────────────────────────────────────────
function Invoke-BootstrapDownloads {
    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Center $script:Sep 'DarkCyan'
    Write-Center '||         C O L L E C T   F R E E                       ||' 'Cyan'
    Write-Center '||              Preparando o ambiente...                  ||' 'DarkGray'
    Write-Center $script:Sep 'DarkCyan'
    Write-Host ''

    # Verificacao de versao
    try {
        $remoteVer = (Invoke-WebRequest -Uri $script:GHVersionUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop).Content.Trim()
        if ($remoteVer -and $remoteVer -ne $script:Version) {
            Write-Host ''
            Write-Center ">> NOVA VERSAO DISPONIVEL: v$remoteVer (voce tem v$($script:Version)) <<" 'Yellow'
            Write-Center 'Baixe em: github.com/Zerinhox33/Collect-Free' 'DarkCyan'
            Write-Host ''
        }
    } catch { }
    Write-Center 'Baixando ferramentas necessarias (Winget > GitHub)...' 'Gray'
    Write-Host ''

    # Garante pasta C:\Collect
    if (-not (Test-Path $script:CollectDir)) {
        New-Item -Path $script:CollectDir -ItemType Directory -Force | Out-Null
    }

    # Lista: WingetId | FileName | ReleaseTag (vazio = raw main)
    $items = @(
        @{ W = 'CPUID.CPU-Z';                     F = 'cpu-z_2.19-en.exe';              R = '' },
        @{ W = 'REALiX.HWiNFO';                   F = 'hwi64_846.exe';                  R = '' },
        @{ W = 'Geekuninstaller.Geekuninstaller';  F = 'geek.exe';                       R = '' },
        @{ W = 'Wagnardsoft.DDU';                  F = 'DDU v18.1.5.2.exe';              R = '' },
        @{ W = 'NVIDIACorporation.NVCleanstall';   F = 'NVCleanstall_1.19.0.exe';        R = '' },
        @{ W = '';                                 F = 'ISLC v1.0.4.5.exe';             R = '' },
        @{ W = '';                                 F = 'MSI_util_v3.exe';               R = '' },
        @{ W = '';                                 F = 'Autoruns.exe';                  R = '' },
        @{ W = '';                                 F = 'DirectX.exe';                   R = '' },
        @{ W = '';                                 F = 'nvidiaInspector.zip';    R = '' },
        @{ W = '';                                 F = 'Collect_Nvidia_Free.nip';       R = '' },
        @{ W = '';                                 F = 'Collect_Power_Plan_Free.pow';   R = '' },
        @{ W = '';                                 F = 'Collect_AMD_Free.reg';          R = '' },
        @{ W = '';                                 F = 'Collect_AMD_Free_Guia.pdf';    R = '' },
        @{ W = '';                                 F = 'WallPaper Collect.png';         R = '' },
        @{ W = '';                                 F = 'Visual-C-Runtimes-All-in-One-Dec-2025.zip'; R = 'Runtimes' }
    )

    $total = $items.Count
    $i     = 0
    foreach ($item in $items) {
        $i++
        Write-Center ("[$i/$total] $($item.F)") 'Gray'
        Invoke-HybridDownload -WingetId $item.W -FileName $item.F -ReleaseTag $item.R
    }

    # Extrair e instalar Visual C++ Runtimes silenciosamente
    $vcZip = Join-Path $script:CollectDir 'Visual-C-Runtimes-All-in-One-Dec-2025.zip'
    $vcDir = Join-Path $script:CollectDir 'Visual-C-Runtimes-All-in-One-Dec-2025'
    # Se a pasta ja existe com outro nome, encontra ela
    if (-not (Test-Path $vcDir)) {
        $found = Get-ChildItem -LiteralPath $script:CollectDir -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'Visual-C-Runtimes' } | Select-Object -First 1
        if ($found) { $vcDir = $found.FullName }
    }
    if ((Test-Path $vcZip) -and -not (Test-Path $vcDir)) {
        Write-Center 'Extraindo Visual C++ Runtimes...' 'Gray'
        try {
            Expand-Archive -LiteralPath $vcZip -DestinationPath $script:CollectDir -Force -ErrorAction Stop
            Get-ChildItem -LiteralPath $script:CollectDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
            Write-Log 'Visual-C-Runtimes extraido.'
        } catch { Write-Log "Falha ao extrair Runtimes: $($_.Exception.Message)" 'WARN' }
    }
    $vcFlagFile = Join-Path $script:CollectDir 'vc_runtimes_installed.flag'
    if ((Test-Path $vcDir) -and -not (Test-Path $vcFlagFile)) {
        # Buscar install_all.bat dentro da pasta extraida (pode estar em subpasta)
        $bat = Get-ChildItem -LiteralPath $vcDir -Filter 'install_all.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bat) {
            Write-Log "Instalando Visual C++ Runtimes via $($bat.FullName)..."
            try {
                $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$($bat.FullName)`"" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    Write-Log 'Visual C++ Runtimes instalados com sucesso.'
                    '1' | Set-Content -LiteralPath $vcFlagFile -Force
                } else {
                    Write-Log "install_all.bat retornou codigo $($proc.ExitCode)" 'WARN'
                }
            } catch { Write-Log "Falha ao instalar Runtimes: $($_.Exception.Message)" 'WARN' }
        } else {
            Write-Log "install_all.bat nao encontrado em $vcDir" 'WARN'
        }
    } elseif (Test-Path $vcFlagFile) {
        Write-Log 'Visual C++ Runtimes ja instalados anteriormente -- pulando.'
    } else {
        Write-Log 'Pasta Visual C++ Runtimes nao encontrada apos extracao' 'WARN'
    }

    Write-Host ''
    Write-Center 'Download concluido!' 'Green'
    Start-Sleep -Seconds 1
}

# ─── TELA DE RESTORE POINT ────────────────────────────────────────────────────
function Show-RestorePointScreen {
    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Center $script:Sep 'DarkCyan'
    Write-Center '||         C O L L E C T   F R E E                       ||' 'Cyan'
    Write-Center $script:Sep 'DarkCyan'
    Write-Host ''
    Write-Center 'PONTO DE RESTAURACAO DO SISTEMA' 'White'
    Write-Host ''
    Write-Center 'Deseja criar um ponto de restauracao antes de otimizar?' 'Gray'
    Write-Host ''
    Write-Center '[S] Sim, criar ponto de restauracao  (recomendado)' 'Green'
    Write-Center '[N] Nao criar' 'DarkGray'
    Write-Host ''
    Write-Center $script:Sep 'DarkCyan'
    Write-Host ''
    Write-Center 'Escolha [S/N] (padrao: S): ' 'White' -NoNewline

    $choice = (Read-Host).Trim().ToUpper()
    if ($choice -ne 'N') {
        Write-Host ''
        Write-Center 'Criando ponto de restauracao...' 'Cyan'
        Invoke-RestorePoint
        Write-Host ''
        Write-Center 'Ponto de restauracao criado! Pressione Enter para continuar...' 'Green'
        [void][Console]::ReadLine()
    }
}

# ─── 1. GENERAL SYSTEM ────────────────────────────────────────────────────────
function Invoke-GeneralSystem {
    Write-Log 'Otimizando Sistema Geral (BCD, Priority, Delays)...'
    & bcdedit /set disabledynamictick yes        | Out-Null
    & bcdedit /set useplatformtick yes           | Out-Null
    & bcdedit /deletevalue useplatformclock 2>&1 | Out-Null

    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38

    Set-RegValue 'HKCU:\Control Panel\Desktop' 'AutoEndTasks'          '1'    'String'
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'HungAppTimeout'        '1000' 'String'
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout'  '1000' 'String'
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'LowLevelHooksTimeout'  '1000' 'String'
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'         '0'    'String'

    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics' 'Enabled' 0
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' 'MaintenanceDisabled' 1

    Write-Log 'Desativando Telemetria Basica e Recursos desnecessarios...'
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds'       0
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'        'EnableActivityFeed' 0
    Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1

    Write-Log 'Otimizacao Geral concluida.'
}

# ─── 2. POWER OPTIMIZATIONS ───────────────────────────────────────────────────
function Invoke-PowerOpt {
    Write-Log 'Otimizando Energia (registro e hibernacao)...'
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'    0
    & powercfg /h off | Out-Null
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'SleepStudyDisabled'  1
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff'  1

    Write-Log 'Desativando HIPM, DIPM e HDD Parking...'
    $services    = @('EnableHIPM', 'EnableDIPM', 'EnableHDDParking')
    $searchRoots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\storahci',
        'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme',
        'HKLM:\SYSTEM\CurrentControlSet\Services\iaStorAV',
        'HKLM:\SYSTEM\CurrentControlSet\Services\disk'
    )
    foreach ($svc in $services) {
        foreach ($root in $searchRoots) {
            if (Test-Path $root) {
                Get-ChildItem -Path $root -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                    Where-Object { $_.GetValueNames() -contains $svc } |
                    ForEach-Object { Set-RegValue $_.PSPath $svc 0 }
            }
        }
    }
    Write-Log 'Energia Otimizada.'
}

# ─── 13. POWER PLAN ───────────────────────────────────────────────────────────
function Invoke-PowerPlan {
    $planFile = Join-Path $script:CollectDir 'Collect_Power_Plan_Free.pow'

    Write-Log 'Importando plano de energia Collect Free...'

    if (-not (Test-Path -LiteralPath $planFile)) {
        Write-Log "Arquivo nao encontrado: $planFile" 'WARN'
        return
    }

    # Verifica se o plano ja existe pelo nome antes de importar
    $list = & powercfg /LIST 2>&1
    $existing = $list | Where-Object { $_ -match 'Collect Power Plan' } | Select-Object -Last 1
    $importedGuid = $null

    if ($existing -and $existing -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
        $importedGuid = $Matches[1]
        Write-Log "Plano Collect ja existe no sistema (GUID: $importedGuid) -- reutilizando."
    } else {
        # Nao existe -- importa agora
        $output = & powercfg /IMPORT "$planFile" 2>&1
        if ($output -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $importedGuid = $Matches[1]
            Write-Log "Plano Collect Free importado com sucesso (GUID: $importedGuid)."
        } else {
            Write-Log 'Falha ao importar plano de energia Collect Free.' 'WARN'
            return
        }
    }

    # Ativa o plano
    & powercfg /S $importedGuid 2>&1 | Out-Null
    Write-Log 'Plano Collect Free definido como ativo.'
}

# ─── 3. KEYBOARD & MOUSE ──────────────────────────────────────────────────────
function Invoke-KBM {
    Write-Log 'Otimizando Teclado e Mouse...'
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions' 'CpuPriorityClass' 3
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions' 'IoPriority'       3

    # Mouse 1:1, sem aceleracao
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      '0'  'String'
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0'  'String'
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0'  'String'
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSensitivity' '10' 'String'

    # Teclado Max
    Set-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0'  'String'
    Set-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'

    # Acessibilidade
    Set-RegValue 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags'    '122' 'String'
    Set-RegValue 'HKCU:\Control Panel\Accessibility\ToggleKeys'        'Flags'    '58'  'String'
    Set-RegValue 'HKCU:\Control Panel\Accessibility\StickyKeys'        'Flags'    '506' 'String'
    Set-RegValue 'HKCU:\Control Panel\Accessibility\MouseKeys'         'Flags'    '0'   'String'

    # Data Queue Size (baixa latencia)
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize'    65
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' 65
    Write-Log 'KBM Otimizado.'
}

# ─── 4. GPU OPTIMIZATIONS ─────────────────────────────────────────────────────
function Invoke-GPUOpt {
    Write-Log 'Identificando GPU e aplicando otimizacoes...'
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' 'Start' 4


    # Pega GPU dedicada: NVIDIA > AMD > Intel Arc > qualquer nao-Microsoft
    # NOTA: AdapterRAM eh uint32 e transborda para 0 em GPUs >= 8GB — nao usar para ordenar!
    $allGPUs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $gpu = $allGPUs | Where-Object { $_.AdapterCompatibility -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) {
        $gpu = $allGPUs | Where-Object { $_.AdapterCompatibility -match 'AMD|Advanced Micro' } | Select-Object -First 1
    }
    if (-not $gpu) {
        $gpu = $allGPUs | Where-Object {
            $_.Name -notmatch 'Microsoft Basic|Remote|Virtual|RDP|Hyper-V' -and
            $_.AdapterCompatibility -notmatch 'Microsoft'
        } | Select-Object -First 1
    }
    if (-not $gpu) { $gpu = $allGPUs | Select-Object -First 1 }
    $gpuName = $gpu.Name

    # HAGS -- apenas GPUs compativeis
    if ($gpuName -match 'RTX|GTX 16|RX 5[0-9]{3}|RX 6[0-9]{3}|RX 7[0-9]{3}|RX 8[0-9]{3}|RX 9[0-9]{3}|Arc|Xe') {
        Write-Log "Ativando HAGS em: $gpuName"
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    } else {
        Write-Log "HAGS ignorado: '$gpuName' pode nao suportar sem risco." 'WARN'
    }

    # ── NVIDIA ──
    if ($gpuName -match 'NVIDIA|GeForce|RTX|GTX') {
        Write-Log "Aplicando perfil NVIDIA em: $gpuName"

        # Desativa preempcao de GPU (reduz micro-stutters)
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak' 'DisablePreemption'  1
        # Desativa GC6 power save
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak' 'DisableGC6SBR'      1
        # Mantem GPU em estado de performance maxima (sem P-States dinamicos)
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'                'DisableDynamicPstate' 1

        # Desativa telemetria NVIDIA
        foreach ($svc in @('NvTelemetryContainer', 'NvOaWrapper')) {
            & "$env:SystemRoot\system32\sc.exe" stop   $svc 2>&1 | Out-Null
            & "$env:SystemRoot\system32\sc.exe" config $svc start= disabled 2>&1 | Out-Null
        }

        # Desativa tasks de telemetria NVIDIA
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match '^NvTm' } |
            ForEach-Object { Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null }

        Write-Log 'Perfil NVIDIA aplicado.'
    }

    # ── AMD ──
    if ($gpuName -match 'AMD|Radeon|ATI') {
        Write-Log "Aplicando perfil AMD em: $gpuName"

        $amdClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        Get-ChildItem $amdClass -ErrorAction SilentlyContinue | ForEach-Object {
            $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
            if ($desc -match 'AMD|Radeon|ATI') {
                # Desativa Ultra Low Power State (ULPS) -- elimina stutters ao alternar janelas
                Set-RegValue $_.PSPath 'EnableUlps'              0
                Set-RegValue $_.PSPath 'EnableUlps_NA'           0
                # Desativa deep sleep do shader clock
                Set-RegValue $_.PSPath 'PP_SclkDeepSleepDisable' 1
                # Desativa deep sleep do memory clock (VRAM nunca adormece)
                Set-RegValue $_.PSPath 'PP_MclkDeepSleepDisable' 1
            }
        }

        Write-Log 'Perfil AMD aplicado.'
    }

    Write-Log 'GPU Otimizada.'
}

# ─── 5. CPU OPTIMIZATIONS ─────────────────────────────────────────────────────
function Invoke-CPUOpt {
    Write-Log 'Otimizando CPU (Core Parking e Sleep States)...'
    & powercfg -setacvalueindex scheme_current sub_processor CPMINCORES 100 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT                                       2>&1 | Out-Null
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CoreParkingDisabled' 1

    $isLaptop = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if (-not $isLaptop) {
        & powercfg -setacvalueindex scheme_current sub_sleep hybridsleep 0 2>&1 | Out-Null
        & powercfg -setacvalueindex scheme_current sub_sleep standbyidle 0 2>&1 | Out-Null
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'PlatformAoAcOverride' 0
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CsEnabled'            0
    } else {
        Write-Log 'Sleep States preservados (dispositivo portatil detectado).' 'WARN'
    }
    Write-Log 'CPU Otimizada.'
}

# ─── 6. PC CLEAN ──────────────────────────────────────────────────────────────
function Invoke-PCClean {
    Write-Log 'Limpando Arquivos Temporarios e Cache...'
    $paths = @($env:TEMP, [IO.Path]::GetTempPath(), 'C:\Windows\Temp')
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Force -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log 'Arquivos temporarios e Lixeira limpos.'
}

# ─── 7. SYSTEM DEBLOAT ────────────────────────────────────────────────────────
function Invoke-DebloatSystem {
    Write-Log 'Removendo Bloatware e Desativando Telemetria Pesada...'
    Set-RegValue 'HKCU:\System\GameConfigStore'                              'GameDVR_Enabled'              0
    Set-RegValue 'HKCU:\Software\Microsoft\GameBar'                          'AllowAutoGameMode'            0
    Set-RegValue 'HKCU:\Software\Microsoft\GameBar'                          'AutoGameModeEnabled'          0
    Set-RegValue 'HKCU:\Software\Microsoft\GameBar'                          'ShowStartupPanel'             0
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'        'AllowGameDVR'                 0
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR' 'value' 0
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'              0

    foreach ($svc in @('xbgm', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc')) {
        & "$env:SystemRoot\system32\sc.exe" config $svc start= disabled 2>&1 | Out-Null
    }
    Write-Log 'Debloat Concluido.'
}

# ─── 8. STORAGE OPTIMIZATIONS ─────────────────────────────────────────────────
function Invoke-StorageOpt {
    Write-Log 'Otimizando Armazenamento (TRIM, NTFS)...'
    & fsutil behavior set memoryusage       2 | Out-Null
    & fsutil behavior set mftzone           2 | Out-Null  # 25% MFT reserve (acima do default 12.5%)
    & fsutil behavior set Disabledeletenotify 0 | Out-Null  # TRIM ativo
    & fsutil behavior set disableLastAccess 1 | Out-Null    # timestamps de acesso desativados
    & fsutil behavior set disable8dot3      1 | Out-Null

    # Write Cache Buffer -- controladoras conhecidas sem recursao full
    $enumRoots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SCSI',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\IDE'
        # USBSTOR removido — Write Cache em USB causa perda de dados se removido sem eject
    )
    foreach ($root in $enumRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue |
            Get-ChildItem -ErrorAction SilentlyContinue |
            Get-ChildItem -ErrorAction SilentlyContinue |
            Where-Object { Test-Path "$($_.PSPath)\Device Parameters\Disk" } |
            ForEach-Object {
                Set-RegValue "$($_.PSPath)\Device Parameters\Disk" 'UserWriteCacheSetting'  1
                Set-RegValue "$($_.PSPath)\Device Parameters\Disk" 'CacheIsPowerProtected'  1
            }
    }
    Write-Log 'Armazenamento Otimizado.'
}

# ─── 9. MEMORY OPTIMIZATIONS ──────────────────────────────────────────────────
function Invoke-MemoryOpt {
    Write-Log 'Otimizando Memoria...'

    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 0
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB)
    if ($ramGB -ge 16) {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
        Write-Log "DisablePagingExecutive=1 (RAM: ${ramGB}GB >= 16GB)"
    } else {
        Write-Log "DisablePagingExecutive: PULADO (RAM: ${ramGB}GB < 16GB -- risco de instabilidade)" 'WARN'
    }

    # ── PROTECAO (padrao Pro, vale para os 3 scripts) ──
    # Prefetch/SysMain sao INTOCAVEIS: NAO parar/desabilitar o servico SysMain
    # nem setar EnablePrefetcher/EnableSuperfetch=0; NAO apagar a pasta Prefetch.
    # Servicos protegidos no projeto: dps, diagtrack, pcasvc, sysmain.

    # MemoryCompression + PageCombining: desativa apenas com RAM >= 16GB.
    # Em <16GB ambos economizam RAM e ajudam -- preservados.
    if ($ramGB -ge 16) {
        Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        Disable-MMAgent -PageCombining     -ErrorAction SilentlyContinue
        Write-Log "MemoryCompression + PageCombining desativados (RAM: ${ramGB}GB >= 16GB)"
    } else {
        Write-Log "MemoryCompression + PageCombining PRESERVADOS (RAM: ${ramGB}GB < 16GB -- ajudam em RAM baixa)"
    }

    $memMB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1MB
    if ($memMB -ge 8000) {
        $threshKB = [int]($memMB * 1024)
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' $threshKB
        Write-Log "SvcHostSplitThresholdInKB = ${threshKB}KB (RAM: ${memMB}MB)"
    }
    Write-Log 'Memoria Otimizada.'
}

# ─── 10. ADDITIONAL / QOL ─────────────────────────────────────────────────────
function Invoke-QOL {
    Write-Log 'Aplicando Configuracoes QOL e Efeitos Visuais...'

    Set-RegValue 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 96
    Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt'    0
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0

    # Efeitos visuais -- modo performance (desativa animacoes desnecessarias)
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    Set-RegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate'                              '0' 'String'
    Set-RegValue 'HKCU:\Control Panel\Desktop'               'DragFullWindows'                         '0' 'String'
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations'  0
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow'     0
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0

    Write-Log 'QOL e Efeitos Visuais aplicados.'
}

# ─── 11. UNINSTALL USELESS APPS ───────────────────────────────────────────────
function Invoke-UninstallApps {
    Write-Log 'Desinstalando Apps Nativos Inuteis...'
    $apps = @(
        # Windows 10 + 11
        'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
        'Microsoft.Messaging', 'Microsoft.Microsoft3DViewer',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.ZuneMusic',
        'Microsoft.YourPhone', 'Microsoft.People',
        'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp',
        'Microsoft.windowscommunicationsapps',
        # Windows 11 especifico
        'Microsoft.GamingApp', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.Todos',
        'Clipchamp.Clipchamp', 'MicrosoftTeams', 'MicrosoftCorporationII.MicrosoftFamily'
    )
    foreach ($app in $apps) {
        Get-AppxPackage *$app* -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    Write-Log 'Apps Inuteis removidos.'
}

# ─── 12. NETWORK TWEAKING ─────────────────────────────────────────────────────
function Invoke-NetworkTweaks {
    Write-Log 'Otimizando Rede (TCP, DNS, Latencia)...'
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' 'DnsPriority'   6
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' 'LocalPriority' 4
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' 'HostsPriority' 5
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' 'NetbtPriority' 7

    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxUserPort'      65534
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'TcpTimedWaitDelay' 30
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DefaultTTL'        64

    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 4294967295

    & netsh int tcp set global autotuninglevel=normal                      2>&1 | Out-Null
    & netsh int tcp set heuristics       disabled                          2>&1 | Out-Null
    & netsh int tcp set global rsc=disabled                                2>&1 | Out-Null
    & netsh int tcp set global netdma=disabled                             2>&1 | Out-Null
    & netsh int tcp set supplemental template=internet congestionprovider=newreno 2>&1 | Out-Null

    # Preferencia IPv4 sobre IPv6 (valor 32 = desativa IPv6 em interfaces nao-tunnel)
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\services\TCPIP6\Parameters'          'DisabledComponents'  32
    Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\services\NlaSvc\Parameters\Internet' 'EnableActiveProbing' 0
    Write-Log 'Rede Otimizada.'
}

# ─── 14. NIC OPTIMIZATION ─────────────────────────────────────────────────────
function Invoke-NICOpt {
    Write-Log 'Otimizando Adaptadores de Rede (NIC)...'

    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }

    if (-not $adapters) {
        Write-Log 'Nenhum adaptador de rede ativo encontrado.' 'WARN'
        return
    }

    foreach ($adapter in $adapters) {
        $n = $adapter.Name
        Write-Log "Configurando NIC: $n"

        # Desativa economia de energia na NIC
        $props = @(
            @{ D = 'Energy Efficient Ethernet';    V = 'Disabled' },
            @{ D = 'Green Ethernet';                V = 'Disabled' },
            @{ D = 'Wake on Magic Packet';          V = 'Disabled' },
            @{ D = 'Wake on Pattern Match';         V = 'Disabled' },
            @{ D = 'Interrupt Moderation';          V = 'Disabled' },
            @{ D = 'Flow Control';                  V = 'Disabled' },
            @{ D = 'Auto Disable Gigabit';          V = 'Disabled' },
            @{ D = 'Gigabit Lite';                  V = 'Disabled' },
            @{ D = 'Advanced EEE';                  V = 'Disabled' },
            @{ D = 'Receive Buffers';               V = '2048'     },
            @{ D = 'Transmit Buffers';              V = '2048'     }
        )
        foreach ($p in $props) {
            Set-NetAdapterAdvancedProperty -Name $n -DisplayName $p.D -DisplayValue $p.V -ErrorAction SilentlyContinue
        }

        # Desativa gerenciamento de energia pelo SO na NIC (PnP)
        $pnpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
        Get-ChildItem $pnpPath -ErrorAction SilentlyContinue | ForEach-Object {
            $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
            if ($desc -and $adapter.InterfaceDescription -like "*$desc*") {
                Set-RegValue $_.PSPath 'PnPCapabilities' 24
            }
        }
    }

    Write-Log 'NICs Otimizadas.'
}

# ─── 15. SCHEDULED TASKS CLEANUP ─────────────────────────────────────────────
function Invoke-TasksCleanup {
    Write-Log 'Desativando Scheduled Tasks de Telemetria e Compatibilidade...'

    $tasks = @(
        @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'Microsoft Compatibility Appraiser' },
        @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'ProgramDataUpdater'                },
        @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'StartupAppTask'                    },
        @{ P = '\Microsoft\Windows\Autochk\';                                 N = 'Proxy'                             },
        @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator'                      },
        @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'KernelCeipTask'                    },
        @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip'                           },
        @{ P = '\Microsoft\Windows\DiskDiagnostic\';                          N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClient'                          },
        @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClientOnScenarioDownload'        },
        @{ P = '\Microsoft\Windows\Windows Error Reporting\';                 N = 'QueueReporting'                    },
        @{ P = '\Microsoft\Windows\CloudExperienceHost\';                     N = 'CreateObjectTask'                  },
        @{ P = '\Microsoft\Windows\PI\';                                      N = 'Sqm-Tasks'                         },
        @{ P = '\Microsoft\Windows\NetTrace\';                                N = 'GatherNetworkInfo'                 }
    )

    foreach ($t in $tasks) {
        Disable-ScheduledTask -TaskPath $t.P -TaskName $t.N -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Log 'Scheduled Tasks de Telemetria desativadas.'
}

# ─── RESTORE POINT ────────────────────────────────────────────────────────────
function Invoke-RestorePoint {
    Write-Log 'Criando ponto de restauracao...'
    try {
        # Protecao do Sistema vem DESLIGADA por padrao no Win10/11 -> habilitar antes
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        # Remove o limite de 1 ponto a cada 24h (senao o 2o checkpoint do dia falha)
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description 'Collect Free Restore Point' -RestorePointType MODIFY_SETTINGS
        Write-Log 'Ponto de restauracao criado.'
    } catch {
        Write-Log 'Falha no ponto de restauracao (Protecao do Sistema pode estar desativada).' 'WARN'
    }
}

function Invoke-BackupRegistry {
    $backupDir = Join-Path $script:CollectDir 'registry_backup'
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $paths = @(
        @{ Key = 'HKCU\Control Panel';                                                             File = 'ControlPanel'     },
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl';                        File = 'PriorityControl'  },
        @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; File = 'SystemProfile'    },
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters';                     File = 'TcpipParameters'  },
        @{ Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';           File = 'ExplorerAdvanced' }
    )
    $ok = 0
    foreach ($entry in $paths) {
        $outFile = Join-Path $backupDir "${stamp}_$($entry.File).reg"
        & reg export $entry.Key $outFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++ }
    }
    Write-Log "Backup de registry: $ok/$($paths.Count) chaves salvas em $backupDir"
}

# ═══════════════════════════════════════════════════════════════════
#  ESTRUTURA DO MENU
# ═══════════════════════════════════════════════════════════════════



# -- IMPORTAR PERFIL NVIDIA ----------------------------------------------------
function Invoke-ImportNvidiaProfile {
    # Pega GPU dedicada: NVIDIA > AMD > Intel Arc > qualquer nao-Microsoft
    # NOTA: AdapterRAM eh uint32 e transborda para 0 em GPUs >= 8GB — nao usar para ordenar!
    $allGPUs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $gpu = $allGPUs | Where-Object { $_.AdapterCompatibility -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) {
        $gpu = $allGPUs | Where-Object { $_.AdapterCompatibility -match 'AMD|Advanced Micro' } | Select-Object -First 1
    }
    if (-not $gpu) {
        $gpu = $allGPUs | Where-Object {
            $_.Name -notmatch 'Microsoft Basic|Remote|Virtual|RDP|Hyper-V' -and
            $_.AdapterCompatibility -notmatch 'Microsoft'
        } | Select-Object -First 1
    }
    if (-not $gpu) { $gpu = $allGPUs | Select-Object -First 1 }
    $gpuName = $gpu.Name
    if ($gpuName -notmatch 'NVIDIA|GeForce|RTX|GTX') {
        Write-Log 'GPU nao NVIDIA detectada -- pulando import do perfil NPI.'
        return
    }

    Write-Log 'Importando perfil NVIDIA (Collect_Nvidia_Free.nip)...'
    $nipFile   = Join-Path $script:CollectDir 'Collect_Nvidia_Free.nip'

    # Extrair nvidiaInspector.zip se ainda nao extraido
    $zipPath = Join-Path $script:CollectDir 'nvidiaInspector.zip'
    $candidateFolders = @(
        (Join-Path $script:CollectDir 'nvidiaInspector'),
        (Join-Path $script:CollectDir 'nvidiaProfileInspector')
    )
    $alreadyExtracted = $candidateFolders | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ((Test-Path $zipPath) -and -not $alreadyExtracted) {
        try {
            Expand-Archive -LiteralPath $zipPath -DestinationPath 'C:\Collect' -Force -ErrorAction Stop
            $candidateFolders | Where-Object { Test-Path $_ } | ForEach-Object {
                Get-ChildItem -LiteralPath $_ -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
            }
            Write-Log 'nvidiaInspector.zip extraido com sucesso.'
        } catch {
            Write-Log "Falha ao extrair nvidiaInspector.zip: $($_.Exception.Message)" 'WARN'
        }
    }

    # O zip pode extrair como 'nvidiaInspector' ou 'nvidiaProfileInspector'
    $npiFolder = $candidateFolders | Where-Object { Test-Path $_ } | Select-Object -First 1
    $npiFolder = if ($npiFolder) { $npiFolder
    } else { '' }

    $npiExe = $null
    if ($npiFolder -ne '' -and (Test-Path -LiteralPath $npiFolder)) {
        $found = Get-ChildItem -LiteralPath $npiFolder -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Inspector' -and $_.Extension -eq '.exe' } | Select-Object -First 1
        if ($found) { $npiExe = $found.FullName }
    }

    if ($npiExe -and (Test-Path -LiteralPath $nipFile)) {
        try {
            Start-Process -FilePath $npiExe -ArgumentList '-import', "`"$nipFile`"" -WindowStyle Hidden -Wait -ErrorAction Stop
            Write-Log 'Perfil Collect_Nvidia_Free.nip importado com sucesso.'
        } catch {
            Write-Log "Falha ao importar perfil NVIDIA: $($_.Exception.Message)" 'WARN'
        }
    } else {
        Write-Log 'nvidiaProfileInspector.exe ou .nip nao encontrado -- pulando.' 'WARN'
    }
}

$script:Done = @{}

function Invoke-PauseWindowsUpdate {
    Write-Log "Pausando Windows Update ate 2099..."
    try {
        $wuPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        $now  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $end  = "2099-12-31T00:00:00Z"
        Set-RegValue $wuPath "FlightSettingsMaxPauseDays"       3000   "DWord"
        Set-RegValue $wuPath "PauseFeatureUpdatesStartTime"     $now   "String"
        Set-RegValue $wuPath "PauseFeatureUpdatesEndTime"       $end   "String"
        Set-RegValue $wuPath "PauseQualityUpdatesStartTime"     $now   "String"
        Set-RegValue $wuPath "PauseQualityUpdatesEndTime"       $end   "String"
        Set-RegValue $wuPath "PauseUpdatesStartTime"            $now   "String"
        Set-RegValue $wuPath "PauseUpdatesExpiryTime"           $end   "String"
        # Bloqueia via Group Policy tambem
        $gpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $gpPath)) { New-Item -Path $gpPath -Force | Out-Null }
        Set-RegValue $gpPath "NoAutoUpdate"     1 "DWord"
        Set-RegValue $gpPath "AUOptions"        2 "DWord"
        Write-Log "Windows Update pausado ate 31/12/2099."
    } catch {
        Write-Log "Erro ao pausar Windows Update: $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-ApplyWallpaper {
    Write-Log "Aplicando wallpaper Collect..."
    $wpPath = Join-Path $script:CollectDir "WallPaper Collect.png"
    if (-not (Test-Path $wpPath)) {
        Write-Log "Wallpaper nao encontrado em $wpPath" 'WARN'
        return
    }
    try {
        Set-RegValue "HKCU:\Control Panel\Desktop" "WallpaperStyle" "10" "String"
        Set-RegValue "HKCU:\Control Panel\Desktop" "TileWallpaper"  "0"  "String"
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CollectWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue
        [CollectWallpaper]::SystemParametersInfo(20, 0, $wpPath, 3) | Out-Null
        Write-Log "Wallpaper aplicado com sucesso."
    } catch {
        Write-Log "Erro ao aplicar wallpaper: $($_.Exception.Message)" 'WARN'
    }
}

$script:Categories = @(
    @{ CK = '1';  Name = 'General System Optimizations';   F = { Invoke-GeneralSystem  } },
    @{ CK = '2';  Name = 'Power Optimizations';            F = { Invoke-PowerOpt       } },
    @{ CK = '3';  Name = 'Keyboard and Mouse Opts';        F = { Invoke-KBM            } },
    @{ CK = '4';  Name = 'GPU Optimizations';              F = { Invoke-GPUOpt         } },
    @{ CK = '5';  Name = 'CPU Optimizations';              F = { Invoke-CPUOpt         } },
    @{ CK = '6';  Name = 'PC Clean';                       F = { Invoke-PCClean        } },
    @{ CK = '7';  Name = 'System Debloat';                 F = { Invoke-DebloatSystem  } },
    @{ CK = '8';  Name = 'Storage Optimizations';          F = { Invoke-StorageOpt     } },
    @{ CK = '9';  Name = 'Memory Optimizations';           F = { Invoke-MemoryOpt   } },
    @{ CK = '10'; Name = 'Additional / QOL + Visual';      F = { Invoke-QOL            } },
    @{ CK = '11'; Name = 'Uninstall Useless Apps';         F = { Invoke-UninstallApps  } },
    @{ CK = '12'; Name = 'Network Tweaking Utility';       F = { Invoke-NetworkTweaks  } },
    @{ CK = '13'; Name = 'Power Plan (Collect Free)';      F = { Invoke-PowerPlan      } },
    @{ CK = '14'; Name = 'NIC Optimization';               F = { Invoke-NICOpt         } },
    @{ CK = '15'; Name = 'Scheduled Tasks Cleanup';        F = { Invoke-TasksCleanup   } },
    @{ CK = '16'; Name = 'NVIDIA Profile Import';           F = { Invoke-ImportNvidiaProfile } },
    @{ CK = '17'; Name = 'Apply Wallpaper (Collect)';         F = { Invoke-ApplyWallpaper      } },
    @{ CK = '18'; Name = 'Pause Windows Update (ate 2099)';   F = { Invoke-PauseWindowsUpdate  } }
    # Ponto de restauracao movido para tela inicial (antes do menu)
)

# ─── HELPERS ──────────────────────────────────────────────────────────────────
$script:Sep  = '=' * 66
$script:Sep2 = '-' * 66

function Write-Banner {
    Write-Center $script:Sep 'DarkCyan'
    Write-Center '||         C O L L E C T   F R E E                       ||' 'Cyan'
    Write-Center '||       v1.0 | Windows 10 / 11                           ||' 'DarkGray'
    Write-Center $script:Sep 'DarkCyan'
}

function Show-MainMenu {
    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Banner
    Write-Host ''
    Write-Center 'Selecione uma categoria:' 'DarkGray'
    Write-Host ''
    foreach ($cat in $script:Categories) {
        $status = if ($script:Done[$cat.CK]) { '[OK]' } else { '' }
        $color  = if ($script:Done[$cat.CK]) { 'Green' } else { 'White' }
        $line   = ('[{0,2}]  {1,-55} {2}' -f $cat.CK, $cat.Name, $status).PadRight(66)
        Write-Center $line $color
    }
    Write-Host ''
    Write-Center $script:Sep 'DarkCyan'
    Write-Center '[A] Aplicar Tudo                                  [0] Sair' 'White'
    Write-Center $script:Sep 'DarkCyan'
    Write-Host ''
}

# ─── ENTRYPOINT ───────────────────────────────────────────────────────────────
try {
    # 1. Downloads automaticos (Winget > GitHub)
    Invoke-BootstrapDownloads

    # 2. Pergunta sobre ponto de restauracao (padrao: Sim)
    Show-RestorePointScreen

    $script:CatKeys = $script:Categories | ForEach-Object { $_.CK }

    $running = $true
    while ($running) {
        Show-MainMenu
        Write-Center 'Escolha: ' 'White' -NoNewline
        $choice = (Read-Host).Trim().ToUpper()

        switch ($choice) {
            { $_ -in $script:CatKeys } {
                $cat = $script:Categories | Where-Object { $_.CK -eq $choice }
                Clear-Host
                Write-Host ''
                Write-Host ''
                Write-Host ''
                Write-Host ''
                Write-Center "Aplicando: $($cat.Name)..." 'Cyan'
                Write-Center $script:Sep2 'DarkGray'
                & $cat.F
                $script:Done[$cat.CK] = $true
                Write-Center $script:Sep2 'DarkGray'
                Write-Host ''
                Write-Center 'Concluido! Pressione Enter para continuar...' 'DarkGray'
                [void][Console]::ReadLine()
            }
            'A' {
                Clear-Host
                Write-Host ''
                Write-Host ''
                Write-Host ''
                Write-Host ''
                Write-Center 'Aplicando TODAS as otimizacoes...' 'Cyan'
                Write-Host ''
                Write-Center 'Criando backup de registry e ponto de restauracao...' 'DarkGray'
                Invoke-BackupRegistry
                Invoke-RestorePoint
                Write-Host ''
                # Power Plan PRIMEIRO: Invoke-CPUOpt grava em scheme_current via
                # powercfg; ativar o plano Collect depois descartaria esses
                # ajustes. Importar/ativar o plano antes resolve.
                Write-Center '-- Power Plan (Collect Free) --' 'DarkCyan'
                Invoke-PowerPlan
                $script:Done['13'] = $true
                Write-Host ''
                foreach ($cat in $script:Categories | Where-Object { $_.F -and $_.CK -ne '13' }) {
                    Write-Center "-- $($cat.Name) --" 'DarkCyan'
                    & $cat.F
                    $script:Done[$cat.CK] = $true
                    Write-Host ''
                }
                Write-Host ''
                Write-Center $script:Sep 'DarkCyan'
                Write-Center '||          COLLECT FREE  -  CONCLUIDO !                  ||' 'Green'
                Write-Center $script:Sep 'DarkCyan'
                Write-Host ''
                Write-Center '>> REINICIE O PC AGORA para ativar todas as mudancas <<' 'Yellow'
                Write-Host ''
                Write-Center "Log: C:\Collect\logs_Collect\" 'Gray'
                Write-Center 'Discord: https://discord.gg/HGgpgHnZ6q' 'DarkCyan'
                Write-Host ''
                Write-Center $script:Sep 'DarkCyan'
                Write-Host ''
                Write-Center 'Pressione Enter para voltar ao menu...' 'DarkGray'
                [void][Console]::ReadLine()
            }
            '0' { $running = $false }
            default {
                Write-Center 'Opcao invalida.' 'Red'
                Start-Sleep -Milliseconds 600
            }
        }
    }

    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Center 'Collect Free encerrado.' 'Cyan'
    Write-Center 'Reinicie o PC para aplicar todas as alteracoes.' 'DarkGray'
    Write-Host ''
    Start-Sleep -Seconds 2

} catch {
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Host ''
    Write-Center "ERRO: $($_.Exception.Message)" 'Red'
    Write-Center 'Pressione Enter para sair...' 'Yellow'
    [void][Console]::ReadLine()
}
