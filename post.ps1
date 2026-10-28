# KOMFIT Instagram 업로드 스크립트
# 사용법:
#   검증만 (게시 안 함):  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\komfit-insta\post.ps1" -ImageUrl "https://..."
#   실제 게시:             위 명령 끝에 -Publish 추가
# 필요 환경변수: IG_ACCOUNT_ID, IG_ACCESS_TOKEN (사용자 환경변수)
param(
    [Parameter(Mandatory = $true)][string]$ImageUrl,
    [string]$CaptionFile = (Join-Path $PSScriptRoot 'caption.txt'),
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
$ApiVersion = 'v26.0'
$Base = "https://graph.instagram.com/$ApiVersion"

$AccountId = $env:IG_ACCOUNT_ID
$Token = $env:IG_ACCESS_TOKEN
if (-not $AccountId) { $AccountId = [Environment]::GetEnvironmentVariable('IG_ACCOUNT_ID', 'User') }
if (-not $Token) { $Token = [Environment]::GetEnvironmentVariable('IG_ACCESS_TOKEN', 'User') }
if (-not $AccountId -or -not $Token) { Write-Host '[중단] IG_ACCOUNT_ID 또는 IG_ACCESS_TOKEN 환경변수가 없습니다.' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $CaptionFile)) { Write-Host "[중단] 캡션 파일이 없습니다: $CaptionFile" -ForegroundColor Red; exit 1 }
if ($ImageUrl -notmatch '^https://') { Write-Host '[중단] ImageUrl은 https:// 로 시작하는 공개 주소여야 합니다.' -ForegroundColor Red; exit 1 }

$Caption = (Get-Content -Raw -Encoding UTF8 $CaptionFile).Trim()

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-IG([string]$Method, [string]$Path, [string]$Data) {
    try {
        if ($Method -eq 'GET') {
            $q = 'access_token=' + (Enc $Token)
            if ($Data) { $q = $Data + '&' + $q }
            return Invoke-RestMethod -Method Get -Uri ($Base + '/' + $Path + '?' + $q)
        }
        $body = 'access_token=' + (Enc $Token)
        if ($Data) { $body = $Data + '&' + $body }
        return Invoke-RestMethod -Method Post -Uri ($Base + '/' + $Path) -ContentType 'application/x-www-form-urlencoded' -Body $body
    }
    catch {
        $detail = $null
        if ($_.ErrorDetails) { $detail = $_.ErrorDetails.Message }
        if (-not $detail) { $detail = $_.Exception.GetType().Name }
        throw ('API 오류 (' + $Path.Split('/')[-1] + '): ' + $detail)
    }
}

try {
    Write-Host '1/3 컨테이너 생성 중...'
    $c = Invoke-IG 'POST' ($AccountId + '/media') ('image_url=' + (Enc $ImageUrl) + '&caption=' + (Enc $Caption))
    $cid = $c.id
    Write-Host ('    컨테이너 ID: ' + $cid)

    Write-Host '2/3 처리 상태 확인 중...'
    $deadline = (Get-Date).AddSeconds(120)
    $status = $null
    while ((Get-Date) -lt $deadline) {
        $s = Invoke-IG 'GET' $cid 'fields=status_code,status'
        $status = $s.status_code
        if ($status -eq 'FINISHED') { break }
        if ($status -eq 'ERROR' -or $status -eq 'EXPIRED') { throw ('컨테이너 상태 ' + $status + ': ' + $s.status) }
        Start-Sleep -Seconds 3
    }
    if ($status -ne 'FINISHED') { throw '처리 대기 시간 초과 (120초)' }
    Write-Host '    상태: FINISHED (이미지 주소와 형식 정상)' -ForegroundColor Green

    if (-not $Publish) {
        Write-Host ''
        Write-Host '[검증 완료] 게시하지 않았습니다. 실제로 게시하려면 같은 명령 끝에 -Publish 를 붙여 다시 실행하세요.' -ForegroundColor Yellow
        exit 0
    }

    Write-Host '3/3 게시 중...'
    $p = Invoke-IG 'POST' ($AccountId + '/media_publish') ('creation_id=' + (Enc $cid))
    $mediaId = $p.id
    $info = Invoke-IG 'GET' $mediaId 'fields=permalink,timestamp'
    Write-Host ''
    Write-Host ('[게시 완료] 게시물 ID: ' + $mediaId) -ForegroundColor Green
    Write-Host ('            링크: ' + $info.permalink)
}
catch {
    Write-Host ('[실패] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
