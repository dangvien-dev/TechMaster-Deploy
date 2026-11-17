# Functions only: dot-sourcing this file never changes the machine.
$script:OfficeApplicationId = '0ff1ce15-a989-479d-af46-f275c6370663'

function Get-OfficeCleanupInventory {
    # Query failure must not be mistaken for an empty inventory.
    $keys = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$script:OfficeApplicationId' AND PartialProductKey IS NOT NULL" -ErrorAction Stop)
    $ids = @()
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\Office\ClickToRun\Configuration')
            if ($null -ne $key) {
                try { $ids += @(([string]$key.GetValue('ProductReleaseIds')) -split ',|\s+' | Where-Object { $_ }) }
                finally { $key.Dispose() }
            }
        } finally { $base.Dispose() }
    }
    [pscustomobject]@{ Products = @($ids | Sort-Object -Unique); Keys = $keys }
}

function Get-OfficeCleanupPlan($inventory, [ValidateSet('Keys', 'Remove')][string]$mode) {
    $products = @($inventory.Products | Where-Object {
        $_ -match '^(ProPlus|Standard|Professional|HomeBusiness|HomeStudent|Home)(2021|2024)(Retail|Volume)$'
    })
    $keys = @($inventory.Keys | Where-Object {
        $_.ApplicationID -eq $script:OfficeApplicationId -and $_.PartialProductKey -match '^[A-Za-z0-9]{5}$' -and
        ($mode -eq 'Keys' -or ($_.Name -match '(Office21|Office24|2021|2024)' -and $_.Name -notmatch '(Visio|Project)'))
    })
    [pscustomobject]@{
        Mode = $mode
        Products = @($(if ($mode -eq 'Remove') { $products }))
        Keys = $keys
        PreservedKeys = @()
    }
}

function Get-OfficeLicenseKind($license) {
    $text = "$($license.Name) $($license.Description)"
    if ($license.Name -match 'Grace|Trial') { return 'Grace / dùng thử' }
    if ($license.Name -match 'Retail') { return 'Retail' }
    if ($text -match 'KMS|GVLK') { return 'KMS' }
    if ($text -match 'MAK') { return 'MAK' }
    if ($text -match 'Retail') { return 'Retail' }
    return 'Khác / chưa xác định'
}

function Test-OfficeTemporaryLicense($license) {
    $status = 0
    return $license.ApplicationID -eq $script:OfficeApplicationId -and
        $license.PartialProductKey -match '^[A-Za-z0-9]{5}$' -and
        $license.Name -match '(Office21|Office24|2021|2024)' -and $license.Name -notmatch '(Visio|Project)' -and
        ($license.Name -match 'Grace|Trial') -and
        [int]::TryParse([string]$license.LicenseStatus, [ref]$status) -and $status -in 0,2,3,4,5,6
}

function Get-OfficeTemporaryPlan($inventory) {
    $plan = Get-OfficeCleanupPlan $inventory 'Keys'
    [pscustomobject]@{
        Mode='Keys'; Products=@(); TemporaryOnly=$true
        Keys=@($plan.Keys | Where-Object { Test-OfficeTemporaryLicense $_ })
        PreservedKeys=@($plan.Keys | Where-Object { -not (Test-OfficeTemporaryLicense $_) })
    }
}

function Assert-OfficeInventoryUnchanged($before, $after) {
    if ((($before.Products | Sort-Object) -join ',') -cne (($after.Products | Sort-Object) -join ',') -or
        (($before.Keys | ForEach-Object { "$($_.ID):$($_.PartialProductKey):$($_.LicenseStatus)" } | Sort-Object) -join ',') -cne
        (($after.Keys | ForEach-Object { "$($_.ID):$($_.PartialProductKey):$($_.LicenseStatus)" } | Sort-Object) -join ',')) {
        throw 'Office đã thay đổi trong lúc xác nhận. Làm mới danh sách trước khi tiếp tục.'
    }
}

function New-OfficeSelectedPlan($inventory, [string[]]$selectedIds, [ValidateSet('Keys','Remove')][string]$mode) {
    $plan = Get-OfficeCleanupPlan $inventory $mode
    foreach ($id in $selectedIds) {
        if ($id -notin @($plan.Keys.ID)) { throw 'Có key ngoài phạm vi thao tác. Làm mới hoặc dùng chức năng chỉ xoá key.' }
    }
    $indices = @(for ($i=0; $i -lt $plan.Keys.Count; $i++) { if ($plan.Keys[$i].ID -in $selectedIds) { $i+1 } })
    return Select-OfficeCleanupKeys $plan ($indices -join ',')
}

function Select-OfficeCleanupKeys($plan, [string]$selection) {
    # Input refers to the displayed rows, not the last five characters, which
    # can be identical across multiple license records. Never select by default.
    $indices = @()
    $selection = $selection.Trim()
    if ($selection) {
        if ($selection -notmatch '^[0-9]+(\s*,\s*[0-9]+)*$') { throw 'Nhập số thứ tự cách nhau bằng dấu phẩy (ví dụ 1,3), hoặc Enter để không chọn.' }
        foreach ($token in ($selection -split ',')) {
            $index = 0
            if (-not [int]::TryParse($token.Trim(), [ref]$index) -or $index -lt 1 -or $index -gt $plan.Keys.Count) {
                throw "Số thứ tự key không hợp lệ: $token"
            }
            $indices += ($index - 1)
        }
    }
    $indices = @($indices | Sort-Object -Unique)
    $chosen = @()
    $preserved = @()
    for ($i = 0; $i -lt $plan.Keys.Count; $i++) {
        if ($i -in $indices) { $chosen += $plan.Keys[$i] }
        else { $preserved += $plan.Keys[$i] }
    }
    if ($plan.Mode -eq 'Remove' -and $preserved.Count) {
        throw 'Bạn đang giữ lại key của bộ Office sẽ gỡ. Đã dừng vì gỡ cả bộ có thể ảnh hưởng license này. Bấm Xoá key đã chọn để chỉ dọn key và giữ Office / Retail.'
    }
    [pscustomobject]@{ Mode = $plan.Mode; Products = @($plan.Products); Keys = $chosen; PreservedKeys = $preserved }
}

function Assert-OfficeCleanupAppsClosed {
    $running = @(Get-Process -Name WINWORD, EXCEL, POWERPNT, OUTLOOK, ONENOTE, MSACCESS, MSPUB, VISIO, WINPROJ, lync -ErrorAction SilentlyContinue)
    if ($running.Count) { throw ('Lưu tài liệu và đóng ứng dụng Office trước: ' + (($running.ProcessName | Sort-Object -Unique) -join ', ')) }
}

function Get-OfficeCleanupSetup([string]$directory) {
    $setup = Join-Path $directory 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing -ErrorAction Stop
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $setup -ErrorAction Stop
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw 'ODT không có chữ ký Microsoft hợp lệ; không chạy. Thay setup.exe bằng bản chính thức rồi thử lại.'
    }
    return $setup
}

function New-OfficeRemovalXml([string[]]$products) {
    if (-not $products.Count) { throw 'Không có sản phẩm Office 2021/2024 được nhận diện để gỡ.' }
    foreach ($id in $products) {
        if ($id -notmatch '^(ProPlus|Standard|Professional|HomeBusiness|HomeStudent|Home)(2021|2024)(Retail|Volume)$') {
            throw "Không cho phép gỡ Product ID: $id"
        }
    }
    $nodes = ($products | ForEach-Object { '    <Product ID="{0}" />' -f $_ }) -join "`r`n"
    # No Remove All, RemoveMSI or FORCEAPPSHUTDOWN: preserve other products and documents.
    return "<Configuration>`r`n  <Remove>`r`n$nodes`r`n  </Remove>`r`n  <Display Level=`"Full`" AcceptEULA=`"TRUE`" />`r`n</Configuration>"
}

function Invoke-OfficeLicenseMethod($license, [ValidateSet('ClearKeyManagementServiceMachine', 'ClearKeyManagementServicePort', 'UninstallProductKey')][string]$method) {
    if ($license.ApplicationID -ne $script:OfficeApplicationId) { throw 'Từ chối thay đổi license ngoài Office.' }
    $result = Invoke-CimMethod -InputObject $license -MethodName $method -ErrorAction Stop
    # Some SPP providers return no output/ReturnValue for successful methods.
    # CIM errors still terminate via ErrorAction Stop. Never invent an error code.
    if ($null -ne $result.ReturnValue -and $result.ReturnValue -ne 0) {
        throw ("{0} thất bại, mã {1}." -f $method, $result.ReturnValue)
    }
    if ($null -eq $result.ReturnValue -and $method -ne 'UninstallProductKey') {
        $fresh = Get-CimInstance -InputObject $license -ErrorAction Stop
        $property = if ($method -eq 'ClearKeyManagementServiceMachine') { 'KeyManagementServiceMachine' } else { 'KeyManagementServicePort' }
        if ($null -eq $fresh -or $null -eq $fresh.PSObject.Properties[$property]) {
            throw "$method không trả mã và không đọc được $property để xác minh."
        }
        $value = $fresh.$property
        $cleared = if ($property -eq 'KeyManagementServiceMachine') {
            [string]::IsNullOrWhiteSpace([string]$value)
        } else { $null -eq $value -or [int]$value -eq 0 }
        if (-not $cleared) { throw "$method chưa xoá được cấu hình $property; dừng để tránh báo thành công nhầm." }
    }
    # UninstallProductKey is verified by the final fresh inventory, including
    # providers that return no result. A surviving selected key is always a failure.
}

function Invoke-OfficeCleanupPlan($plan, [string]$setup, [string]$workDirectory) {
    if (-not $plan.Keys.Count -and -not $plan.Products.Count) {
        Write-Host 'Không chọn key; không thay đổi máy.'
        return
    }
    $removalXml = ''
    if ($plan.Mode -eq 'Remove') {
        if (-not $setup) { throw 'Chưa xác minh Office Deployment Tool.' }
        $removalXml = New-OfficeRemovalXml $plan.Products
    }
    Assert-OfficeCleanupAppsClosed
    $failures = @()
    foreach ($license in $plan.Keys) {
        try {
            Write-Host ("Dọn key Office: {0} (đuôi {1})" -f $license.Name, $license.PartialProductKey)
            if (-not $plan.TemporaryOnly) {
                Invoke-OfficeLicenseMethod $license 'ClearKeyManagementServiceMachine'
                Invoke-OfficeLicenseMethod $license 'ClearKeyManagementServicePort'
            }
            Invoke-OfficeLicenseMethod $license 'UninstallProductKey'
        } catch {
            $failures += $_.Exception.Message
            Write-Warning $_.Exception.Message
        }
    }
    # Do not remove the Office programs if license cleanup failed halfway through.
    if ($failures.Count) { throw ('Chưa dọn xong key. Dừng gỡ Office; xem các lỗi ở trên. Số lỗi: ' + $failures.Count) }
    if ($plan.Mode -eq 'Remove' -and $plan.Products.Count) {
        Assert-OfficeCleanupAppsClosed
        $cfg = Join-Path $workDirectory 'remove.xml'
        [IO.File]::WriteAllText($cfg, $removalXml, [Text.UTF8Encoding]::new($false))
        try {
            $p = Start-Process -FilePath $setup -ArgumentList ('/configure "{0}"' -f $cfg) -Wait -PassThru -ErrorAction Stop
            try {
                if ($null -eq $p.ExitCode -or $p.ExitCode -ne 0) {
                    throw "ODT chưa gỡ thành công (mã $($p.ExitCode)). Xem nhật ký ODT trong %TEMP%; có thể cần khởi động lại."
                }
            } finally { $p.Dispose() }
        } finally { Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue }
    }
    $after = Get-OfficeCleanupInventory
    $leftIds = @($plan.Keys | ForEach-Object { $_.ID })
    $leftKeys = @($after.Keys | Where-Object { $_.ID -in $leftIds })
    $leftProducts = @($after.Products | Where-Object { $_ -in $plan.Products })
    if ($leftKeys.Count -or $leftProducts.Count) {
        throw 'Kiểm tra lại vẫn thấy key hoặc sản phẩm đã chọn. Chưa xác nhận dọn xong; khởi động lại rồi kiểm tra lại.'
    }
    foreach ($kept in $plan.PreservedKeys) {
        $stillPresent = @($after.Keys | Where-Object { $_.ID -eq $kept.ID -and $_.PartialProductKey -eq $kept.PartialProductKey })
        if (-not $stillPresent.Count) { throw 'Key đã chọn giữ lại không còn khớp khi đọc lại. Chưa xác nhận kết quả; kiểm tra nhật ký.' }
    }
    Write-Host 'Đã kiểm tra: key / sản phẩm đã chọn được xoá; các key chọn giữ lại vẫn còn.' -ForegroundColor Green
}
