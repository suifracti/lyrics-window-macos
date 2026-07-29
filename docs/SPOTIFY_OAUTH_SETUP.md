# Spotify Web OAuth 配置

在 Spotify Developer Dashboard 的 Redirect URI 中只注册：

```text
http://127.0.0.1/callback
```

不要把应用运行时偶然显示的动态端口（例如
`http://127.0.0.1:49153/callback`）填写到 Dashboard。应用授权时会在
`127.0.0.1` 上临时监听一个可用端口，并把带端口的实际地址同时用于：

1. Authorization 请求的 `redirect_uri`；
2. Authorization Code 换取 Token 请求的 `redirect_uri`。

设置页会同时显示 Dashboard 注册地址和当前本地监听地址。未进行授权时，
当前本地监听地址显示为未启动；每次授权都可能使用不同端口。
