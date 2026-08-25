# dldns

`dldns` 是面向 OpenWrt 的 Linode 动态 DNS 管理脚本。它从 `ubus` 读取接口地址，并将指定记录名下的 A、AAAA 记录同步为期望状态。

当前实现是单文件 Shell 程序，不需要编译，也不区分 CPU 架构。脚本提供以下三个子命令：

- `ip`：只读查看 OpenWrt 接口的 IPv4、IPv6 地址。
- `update`：将一个 Linode 记录名下指定地址族的记录更新为命令行给出的地址列表。
- `sync`：读取 `/etc/config/dldns`，发现接口地址并同步所有已配置记录。

## 运行要求

脚本面向 OpenWrt 的 BusyBox `ash`，运行时按功能使用以下组件：

| 功能 | 依赖 |
| --- | --- |
| `ip` | `ubus`、`jsonfilter` |
| `ip --format json` | 以上依赖及 `/usr/share/libubox/jshn.sh` |
| `ip --external` | 以上依赖及 `curl` |
| `update` | `curl`、`jsonfilter` |
| `sync` | `ubus`、`curl`、`jsonfilter`、`/lib/functions.sh` |

脚本还会使用 OpenWrt 基础系统提供的 `awk`、`sed`、`tail` 和 `tr` 等工具。

## 安装

从最新的 GitHub Release 下载脚本，并赋予可执行权限：

```sh
curl -L -o dldns https://github.com/erning/dldns/releases/latest/download/dldns
chmod +x dldns
scp dldns root@router:/usr/bin/dldns
```

脚本是架构无关的，不再提供 `amd64`、`mips64`、`mipsle` 或 `arm64` 等独立构建产物。

## 查看接口地址

```sh
dldns ip [options] [INTERFACE...]
```

未指定接口时，脚本自动发现所有 `proto=pppoe` 的网络接口。PPPoE 接口及其对应的 `_6` 接口会合并显示。

常用示例：

```sh
dldns ip
dldns ip pppoe1 pppoe2
dldns ip -4 --format value pppoe2
dldns ip --format json
dldns ip --external --probe-url https://example.net/ip pppoe1
```

`--external` 会通过指定接口访问纯文本 IP 回显地址；不使用该选项时，`ip` 只读取本机 `ubus` 状态。`ip` 不修改网络、路由、DNS、计划任务或文件。

完整参数见：

```sh
dldns ip --help
```

## 更新单个记录名

```sh
dldns update --domain-id ID --token-file FILE [options] RECORD
```

`-4`、`--ipv4`、`-6` 和 `--ipv6` 可以重复使用。未选择的地址族保持不变；`--clear-ipv4` 或 `--clear-ipv6` 会删除对应地址族的全部记录。

```sh
dldns update --domain-id 123 --token-file /root/linode.token \
    -4 192.0.2.10 host

dldns update --domain-id 123 --token-file /root/linode.token \
    -6 2001:db8::10 -6 2001:db8::11 host

dldns update --domain-id 123 --token-file /root/linode.token \
    --clear-ipv6 host
```

对于已选择的地址族，脚本会保留完全匹配的记录、创建缺失记录、更新可复用记录，并删除多余或重复记录。创建 A 或 AAAA 记录前，同名 CNAME 记录会被删除。

默认 TTL 为 300 秒，可设置为任意正整数；Linode 可能调整不支持的值。

## 按配置同步

在 `/etc/config/dldns` 中创建一个名为 `main` 的 UCI 段：

```uci
config dldns 'main'
        option domain_id '12345'
        option token '@/root/linode.token'
        option ttl '300'
        option notify '/usr/libexec/dldns-notify'
        list interface 'pppoe1'
        list interface 'pppoe2'
        list record 'soda 4 6'
        list record 'soda-v4 4'
        list record 'soda-v6 6'
```

字段含义如下：

| 字段 | 说明 |
| --- | --- |
| `domain_id` | Linode 域名 ID，必填 |
| `token` | API 令牌；以 `@` 开头时，其余内容是绝对文件路径 |
| `ttl` | 记录 TTL，默认 300 秒 |
| `notify` | 可选的通知钩子绝对路径，必须可执行 |
| `interface` | 可重复；需要读取的 OpenWrt 网络接口 |
| `record` | 可重复；格式为 `RECORD 4`、`RECORD 6` 或 `RECORD 4 6` |

建议把令牌单独保存在权限为 `0600` 的文件中：

```sh
printf '%s\n' 'LINODE_API_TOKEN' >/root/linode.token
chmod 600 /root/linode.token
```

执行同步：

```sh
dldns sync
dldns sync --verbose
dldns sync --verbose pppoe1 pppoe2
```

命令行接口优先于 UCI 中的 `list interface`。两者都没有配置时，脚本自动发现全部 PPPoE 接口。

### 同步语义

`sync` 对每个 `list record` 同时核对 A 和 AAAA 记录：

- `list record 'host 4 6'` 使用发现的全部公网 IPv4、IPv6 地址。
- `list record 'host 4'` 同步 A 记录，并清空同名 AAAA 记录。
- `list record 'host 6'` 同步 AAAA 记录，并清空同名 A 记录。

这是精确状态同步，不是只增不删的更新。脚本还会删除同名 CNAME 和多余的重复记录。正式运行前，可先执行 `dldns ip` 检查地址发现结果。`dldns sync --verbose` 会显示同步目标和 API 请求，但仍会真实执行变更，不是预演模式。

脚本仅接受公网 IPv4 地址和 `2000::/3` 范围内的 IPv6 地址参与同步。若某个已配置地址族没有发现可用地址，同步会失败，不会把该地址族误清空。

### 通知钩子

仅当同步实际产生变更时，脚本才调用 `notify`。钩子可读取：

- 环境变量 `DLDNS_SYNC_STATUS`：`success` 或 `failed`。
- 环境变量 `DLDNS_CHANGE_COUNT`：已执行的变更数。
- 标准输入：首行为 `status STATUS`，后续每行是 `ACTION TYPE RECORD OLD NEW`。

通知钩子失败会使 `sync` 返回失败状态。

## 测试

测试使用本地模拟的 `ubus`、`jsonfilter`、UCI 函数和 Linode API，不会访问真实路由器或 Linode 账户。

```sh
shellcheck -s dash \
    dldns tests/test-dldns-*.sh \
    tests/mocks/curl tests/mocks/functions.sh \
    tests/mocks/notify tests/mocks/ubus
tests/test-dldns-ip.sh
tests/test-dldns-update.sh
tests/test-dldns-sync.sh
```

## 退出状态

| 状态 | 含义 |
| --- | --- |
| `0` | 成功 |
| `1` | 运行时失败，例如接口、依赖、探测、API 或通知错误 |
| `2` | 命令行参数或 UCI 配置错误 |

## License

MIT
