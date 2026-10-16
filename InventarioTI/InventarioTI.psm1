$privado = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publico = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

$arquivosPrivados = @(Get-ChildItem -Path $privado -Filter '*.ps1' -ErrorAction SilentlyContinue)
$arquivosPublicos = @(Get-ChildItem -Path $publico -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($arquivo in ($arquivosPrivados + $arquivosPublicos)) {
    . $arquivo.FullName
}

Export-ModuleMember -Function $arquivosPublicos.BaseName
