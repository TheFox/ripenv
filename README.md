# ripenv — R.I.P. envsubst

ripenv is a tool for injecting environment variables into templates — inspired by the name of ripgrep. It supports the same variable syntax and can be used as a drop-in replacement in most shell scripts.

## Installation

```sh
git clone https://github.com/TheFox/ripenv.git
cd ripenv
zig build --release
```

## Download

Download the latest binaries from [release page](https://github.com/TheFox/ripenv/releases).

## Dev

```bash
zig run -freference-trace src/main.zig < tmp/tpl.txt
```
