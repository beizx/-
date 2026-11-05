# Beizx 阅读器 · Go 后端

这个目录是 App 的可选后端，用 Go 重写了原先 JVM / Kotlin（`LightNovelReader/proxy`）里的代理服务，并补上了「翻译网关」这一层。

两件事：

1. **代理池**：从公开代理列表抓取候选，本地逐个校验后放进队列，客户端按需取用。给网络受限环境下抓取书源/接口用。
2. **翻译网关**：有道 v3 的签名在服务端完成，App 只把文本发给自己的服务器，App ID / Secret 不再下发到手机。

Go 1.21+ 即可运行（本项目在 Go 1.27.3 上验证）。

---

## 快速开始

```bash
cd server
go test ./...                 # 单元测试
go run ./cmd/server           # 默认监听 :8080，代理池开启
```

带翻译能力启动：

```bash
# Windows PowerShell
$env:YOUDAO_APP_KEY="你的应用ID"; $env:YOUDAO_APP_SECRET="你的应用密钥"; $env:GATEWAY_TOKEN="自定义口令"; go run ./cmd/server

# macOS / Linux
YOUDAO_APP_KEY=xxx YOUDAO_APP_SECRET=yyy GATEWAY_TOKEN=zzz go run ./cmd/server
```

构建单文件二进制：

```bash
go build -trimpath -ldflags="-s -w" -o bin/reader-server ./cmd/server
```

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `8080` | 监听端口 |
| `GATEWAY_TOKEN` | 空 | 非空时所有 `/v1/*` 都需要 `Authorization: Bearer <token>` 或 `X-API-Token` |
| `YOUDAO_APP_KEY` | 空 | 有道应用 ID；为空时 `/v1/translate` 返回 503 |
| `YOUDAO_APP_SECRET` | 空 | 有道应用密钥 |
| `GATEWAY_CACHE_ENTRIES` | `512` | 译文缓存条数上限（TTL + LRU）；`0` 关闭缓存 |
| `GATEWAY_CACHE_TTL_SECONDS` | `3600` | 译文缓存有效期（秒）；`0` 关闭缓存 |
| `PROXY_ENABLED` | `true` | 是否启用代理池 |
| `PROXY_TARGET` | `20` | 代理队列目标长度 |
| `PROXY_CHECK_URL` | `https://www.baidu.com/robots.txt` | 校验代理时请求的地址 |
| `PROXY_CHECK_TIMEOUT_MS` | `4000` | 单个代理校验超时 |
| `PROXY_REFRESH_SECONDS` | `300` | 后台补池间隔 |
| `PROXY_SCDN_ENDPOINT` | proxy.scdn.io | 覆盖 JSON 源地址 |
| `PROXY_IP89_ENDPOINT` | api.89ip.cn | 覆盖文本源地址 |
| `LOG_LEVEL` | `info` | `debug` / `info` / `warn` / `error` |

## 接口

### `GET /healthz`

无需鉴权，用于探活与反向代理健康检查。

```json
{"status":"ok","time":"2026-11-05T01:03:31Z","version":"1.1.0","proxyPoolSize":12,"translateCache":{"entries":8,"hits":31,"misses":9,"evictions":0,"expired":2}}
```

`translateCache` 只在缓存开启时出现；`entries` 是当前缓存条数，`hits` / `misses` / `evictions` / `expired` 是累计计数。

### `POST /v1/translate`

```json
// 请求
{"text":"hello world","from":"auto","to":"zh-CHS"}
// 响应
{"text":"你好世界","detectedSource":"en","target":"zh-CHS"}
```

- `from` 缺省 `auto`，`to` 缺省 `zh-CHS`。
- 单次最多 20000 字符，上游单次最多 4800 字符（自动截断，和 App 的分块策略一致）。
- 上游错误码会映射为 HTTP 状态：`108/110` → 401，`411/412` → 429，`401` → 402，其余 → 502，响应体保留 `code`。
- **缓存**：成功译文按 `(from, to, text)` 的 SHA-256 进入 TTL + LRU 缓存，命中时不消耗有道额度；响应头 `X-Cache: hit|miss` 说明本次结果来源。同一段的并发请求会合并成一次上游调用，失败结果永不缓存，避免限频错误被记住。

```bash
curl -s http://127.0.0.1:8080/v1/translate \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer zzz' \
  -d '{"text":"hello","from":"en","to":"zh-CHS"}'
```

### 代理池

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/v1/proxies?limit=20` | 查看队列快照与上次补池统计 |
| `POST` | `/v1/proxies/take` | 取出一个代理（出队），空池返回 503 |
| `POST` | `/v1/proxies/refresh` | 立即补池，返回本次抓取 / 校验 / 加入数量 |

```json
// GET /v1/proxies
{"size":1,"proxies":["http://1.2.3.4:8080"],"stats":{"Fetched":40,"Checked":40,"Rejected":38,"Added":2}}
```

## 目录结构

```
server/
├── cmd/server/main.go            # 启动、配置、后台补池、优雅退出
├── internal/proxypool/           # 代理模型、抓取源、校验与队列
│   ├── proxy.go                  # Proxy + 文本 / JSON 列表解析
│   ├── source.go                 # Source 接口与 HTTP 源（89ip、scdn）
│   └── pool.go                   # 队列、去重、校验、并发补池
├── internal/gateway/             # 有道 v3 签名与翻译
│   ├── youdao.go                 # 签名、请求、错误码映射
│   ├── cache.go                  # TTL + LRU 译文缓存（含并发合并）
│   └── translate_handler.go      # POST /v1/translate
└── internal/httpapi/router.go    # 路由、鉴权、CORS、panic 兜底
```

## 设计取舍

- **代理只接受公网 IPv4**：私网/回环地址几乎都是错误数据或 DNS 重绑定陷阱，`Proxy.Valid()` 直接拒绝；测试用 `Config.AllowPrivate` 打开。
- **补池串行化**：`Refill` 内部再加一把锁，避免并发请求把上游抓取放大成 N 倍。
- **译文缓存**：整书翻译会重复请求同一段（重读章节、多设备共用网关），因此成功结果进 TTL + LRU 缓存，并用 single-flight 把同一段的并发请求合并成一次上游调用；错误不缓存，`/healthz` 暴露命中率计数。
- **密钥只在服务端**：App 端只需要填一个网关地址，泄露风险从「每个用户的密钥」降级为「一个可轮换的口令」。
- **失败不阻塞**：单个源抓取失败只记录并继续下一个源；只有池子仍然为空时才把错误返回给调用方。
