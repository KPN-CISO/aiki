#!/usr/bin/env bash
source=aiki.go
filename="${source%.*}"
gooss=(linux)
goarchs=(386 amd64)
for goos in ${gooss[@]};do
for goarch in ${goarchs[@]};do
echo "building ${filename}-${goos}-${goarch} from ${source}"
env GOOS=${goos} GOARCH=${goarch} go build -o ${filename}-${goos}-${goarch} ${source}
done
done
exit
