#!/usr/bin/env bash

for cpu in $(seq 1 3) ; do
    zig build --verbose --summary all --release -Dtarget=aarch64-macos -Dcpu=apple_m${cpu}
done

zig build --verbose --summary all --release -Dtarget=x86_64-linux -Dcpu=x86_64
