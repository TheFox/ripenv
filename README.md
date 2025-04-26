# RIP envsubst

## Installation

```sh
git clone https://github.com/TheFox/ripenv.git
cd ripenv
zig build
```

## Download

Download the latest binaries from [release page](https://github.com/TheFox/ripenv/releases).

## Dev

```bash
zig run -freference-trace src/main.zig < tmp/tpl.txt
```
