$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Replace-Exact {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New
    )

    $path = Join-Path $root $RelativePath
    $content = [System.IO.File]::ReadAllText($path)
    if (-not $content.Contains($Old)) {
        throw "Expected text was not found in $RelativePath`n--- expected ---`n$Old"
    }
    $updated = $content.Replace($Old, $New)
    [System.IO.File]::WriteAllText($path, $updated, $utf8NoBom)
}

# Keep the private Windows application physically distinct from upstream FlClash.
Replace-Exact 'windows/CMakeLists.txt' `
    'set(BINARY_NAME "FlClash")' `
    'set(BINARY_NAME "PenrixFlClash")'

Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "CompanyName", "com.follow" "\0"' `
    'VALUE "CompanyName", "Penrix" "\0"'
Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "FileDescription", "FlClash" "\0"' `
    'VALUE "FileDescription", "Penrix FlClash" "\0"'
Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "InternalName", "clash" "\0"' `
    'VALUE "InternalName", "PenrixFlClash" "\0"'
Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "LegalCopyright", "Copyright (C) 2025 com.follow. All rights reserved." "\0"' `
    'VALUE "LegalCopyright", "Private Penrix build of FlClash" "\0"'
Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "OriginalFilename", "FlClash.exe" "\0"' `
    'VALUE "OriginalFilename", "PenrixFlClash.exe" "\0"'
Replace-Exact 'windows/runner/Runner.rc' `
    'VALUE "ProductName", "clash" "\0"' `
    'VALUE "ProductName", "Penrix FlClash" "\0"'

# Give Inno Setup a stable private product identity so installing/updating it can
# never replace the upstream FlClash installation.
Replace-Exact 'windows/packaging/exe/make_config.yaml' `
    'app_id: 728B3532-C74B-4870-9068-BE70FE12A3E6' `
    'app_id: DC58A175-857C-44ED-A3F0-00813F0307B7'
Replace-Exact 'windows/packaging/exe/make_config.yaml' 'app_name: FlClash' 'app_name: Penrix FlClash'
Replace-Exact 'windows/packaging/exe/make_config.yaml' 'publisher: chen08209' 'publisher: Penrix'
Replace-Exact 'windows/packaging/exe/make_config.yaml' `
    'publisher_url: https://github.com/chen08209/FlClash' `
    'publisher_url: https://github.com/Penrix/FlClash'
Replace-Exact 'windows/packaging/exe/make_config.yaml' 'display_name: FlClash' 'display_name: Penrix FlClash'
Replace-Exact 'windows/packaging/exe/make_config.yaml' 'executable_name: FlClash.exe' 'executable_name: PenrixFlClash.exe'
Replace-Exact 'windows/packaging/exe/make_config.yaml' 'output_base_file_name: FlClash.exe' 'output_base_file_name: Penrix-FlClash-Private'

# Never taskkill the upstream app/core/helper by image name. Unregistering our
# own helper service first stops the private managed Core through its Job object.
Replace-Exact 'windows/packaging/exe/inno_setup.iss' `
    "Processes := ['FlClash.exe', 'FlClashCore.exe', 'FlClashHelperService.exe'];" `
    "Processes := ['PenrixFlClash.exe'];"

# The private app talks only to its own Windows helper service and endpoint.
Replace-Exact 'lib/common/constant.dart' "const appName = 'FlClash';" "const appName = 'Penrix FlClash';"
Replace-Exact 'lib/common/constant.dart' `
    "const appHelperService = 'FlClashHelperService';" `
    "const appHelperService = 'PenrixFlClashHelperService';"
Replace-Exact 'lib/common/constant.dart' "const packageName = 'com.follow.clash';" "const packageName = 'com.penrix.flclash';"
Replace-Exact 'lib/common/constant.dart' `
    "final windowsPipeName = '\\\\.\\pipe\\FlClashCore_${_randomPipeId()}';" `
    "final windowsPipeName = '\\\\.\\pipe\\PenrixFlClashCore_${_randomPipeId()}';"
Replace-Exact 'lib/common/constant.dart' 'const helperPort = 47890;' 'const helperPort = 47891;'

Replace-Exact 'services/helper/src/service/windows.rs' `
    'const SERVICE_NAME: &str = "FlClashHelperService";' `
    'const SERVICE_NAME: &str = "PenrixFlClashHelperService";'
Replace-Exact 'services/helper/src/service/hub.rs' `
    'const LISTEN_PORT: u16 = 47890;' `
    'const LISTEN_PORT: u16 = 47891;'
Replace-Exact 'services/helper/src/service/hub.rs' `
    'const CORE_PIPE_PREFIX: &str = r"\\.\pipe\FlClashCore_";' `
    'const CORE_PIPE_PREFIX: &str = r"\\.\pipe\PenrixFlClashCore_";'

# Force private settings/state into a separate subtree even if path_provider
# ever resolves the same Windows base directory as upstream.
Replace-Exact 'lib/common/path.dart' `
@'
    supportDirectory().then((value) {
      dataDir.complete(value);
    });
'@ `
@'
    supportDirectory().then((value) async {
      final privateDir = Directory(join(value.path, 'PenrixPrivate'));
      await privateDir.create(recursive: true);
      dataDir.complete(privateDir);
    });
'@
Replace-Exact 'lib/common/path.dart' `
@'
    cacheDirectory().then((value) {
      cacheDir.complete(value);
    });
'@ `
@'
    cacheDirectory().then((value) async {
      final privateDir = Directory(join(value.path, 'PenrixPrivate'));
      await privateDir.create(recursive: true);
      cacheDir.complete(privateDir);
    });
'@

Write-Host 'Prepared isolated Penrix private Windows identity.'
Write-Host '  exe:     PenrixFlClash.exe'
Write-Host '  service: PenrixFlClashHelperService'
Write-Host '  port:    47891'
Write-Host '  AppId:   DC58A175-857C-44ED-A3F0-00813F0307B7'
