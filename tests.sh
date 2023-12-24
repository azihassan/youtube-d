chmod +x youtube-d

./youtube-d -p -d --no-progress https://www.youtube.com/watch?v=R85MK830mMo

filename="Debugging Github actions-R85MK830mMo-18.mp4"
if [ ! -e "$filename" ]; then
    echo "$filename not found"
    exit 1
fi
echo "[1/3] OK, $filename exists"

expected_size=7079820
actual_size=$(du -b "$filename" | cut -f 1)
if [ $expected_size -ne $actual_size ]; then
    echo "Wrong size. Expected $expected_size, found $actual_size"
    exit 1
fi
echo "[2/3] OK, size is correct"

expected_hash="e7160d310e79a5a65f382b8ca0b198dd"
actual_hash=$(md5sum "$filename" | cut -d " " -f 1)
if [ $expected_hash != $actual_hash ]; then
    echo "Wrong hash. Expected $expected_hash, found $actual_hash"
    exit 1
fi

echo "[3/3] OK, md5sum is correct"
