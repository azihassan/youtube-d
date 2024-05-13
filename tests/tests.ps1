Start-Job { mitmdump -q -w proxydump }

Write-Host "Launching proxy..."
sleep 2
Write-Host "Proxy running"

Write-Host "Installing certificate..."
curl.exe -vLo mitmproxy-ca-cert.cer --proxy http://localhost:8080 http://mitm.it/cert/cer
dir *.cer

Import-Certificate -FilePath .\mitmproxy-ca-cert.cer -CertStoreLocation Cert:\LocalMachine\Root
certlm

Write-Host "Certificate installed"

& ".\youtube-d.exe" -p --no-progress --proxy http://localhost:8080 https://www.youtube.com/watch?v=R85MK830mMo

$filename = "Debugging Github actions-R85MK830mMo-18.mp4"

if (!(Test-Path $filename)) {
    Write-Host "$filename not found"
    exit 1
}

Write-Host "[1/3] OK, $filename exists"

$expected_size = 7079820
$actual_size = (Get-Item $filename).Length

if($actual_size -ne $expected_size) {
    Write-Host "Wrong size. Expected $expected_size, found $actual_size"
    exit 1
}
Write-Host "[2/3] OK, size is correct"

$expected_hash = "e7160d310e79a5a65f382b8ca0b198dd"
$actual_hash = (Get-FileHash -path $filename -algorithm MD5).Hash

if($expected_hash -ne $actual_hash) {
    Write-Host "Wrong hash. Expected $expected_hash, found $actual_hash"
}

Write-Host "[3/3] OK, md5sum is correct"
