set -e

chmod +x youtube-d
mitmdump -q -w proxydump & 1>/dev/null 2>/dev/null

trap "kill -INT $!" EXIT
echo Launching proxy...
sleep 2
echo Proxy running in pid $!

echo Installing certificate...
curl -Lo mitmproxy-ca-cert.pem --proxy http://localhost:8080 http://mitm.it/cert/pem
sudo mv mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates

./youtube-d -p --no-progress --proxy http://localhost:8080 https://www.youtube.com/watch?v=R85MK830mMo

filename="Debugging Github actions-R85MK830mMo-18.mp4"
if [ ! -e "$filename" ]; then
    echo "$filename not found"
    exit 1
else
    echo "[1/4] OK, $filename exists"
fi

expected_size=7079820
actual_size=$(du -b "$filename" | cut -f 1)
if [ $expected_size -ne $actual_size ]; then
    echo "Wrong size. Expected $expected_size, found $actual_size"
    exit 1
else
    echo "[2/4] OK, size is correct"
fi

expected_hash="e7160d310e79a5a65f382b8ca0b198dd"
actual_hash=$(md5sum "$filename" | cut -d " " -f 1)
if [ $expected_hash != $actual_hash ]; then
    echo "Wrong hash. Expected $expected_hash, found $actual_hash"
    exit 1
else
    echo "[3/4] OK, md5sum is correct"
fi

urls=$(mitmdump -nr proxydump -s script.py)

for url in  'https://www.youtube.com/watch?v=R85MK830mMo' 'base.js' 'googlevideo.com';
do
    if echo $urls | grep -q $url
    then
        echo "\t[OK] $url"
    else
        echo "[4/4] Missing URL in proxy dump:"
        echo $url
        exit 1
    fi
done
echo "[4/4] OK, proxying worked as expected"
