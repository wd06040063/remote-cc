# RemoteCC 使用说明

## 当前安装信息

- Web 地址: `http://localhost:8310`
- 局域网地址: `http://10.35.111.19:8310`
- 登录账号: `admin`
- 登录密码: `admin`
- 项目目录: `/home/wd/remote-cc`
- 服务日志: `/tmp/rcc.log`

## 启动和停止服务

在当前目录执行:

```bash
bash rcc-server start
```

停止服务:

```bash
bash rcc-server stop
```

重启服务:

```bash
bash rcc-server restart
```

查看状态:

```bash
bash rcc-server status
```

查看日志:

```bash
bash rcc-server log
```

## 浏览器使用

1. 打开 `http://localhost:8310`。
2. 输入账号 `admin` 和密码 `admin` 登录。
3. 在 Web 页面中创建或进入终端会话。
4. 选择 Codex Agent 后即可在浏览器中使用远程终端。

## 命令行工具

本次安装没有权限写入 `/usr/local/bin`，所以全局命令链接被跳过。可以在当前目录直接使用:

```bash
./remotecc
./rcc-tui
bash ./rcc-server status
```

如果以后需要全局命令，可手动创建软链接:

```bash
sudo ln -sf /home/wd/remote-cc/remotecc /usr/local/bin/remotecc
sudo ln -sf /home/wd/remote-cc/rcc-tui /usr/local/bin/rcc-tui
sudo ln -sf /home/wd/remote-cc/rcc-server /usr/local/bin/rcc-server
```

## 配置文件

安装配置写在当前目录的 `.env` 文件中，权限为 `600`。

常用配置:

```bash
RC_USER=admin
RC_PASS=admin
PORT=8310
RCC_AGENT=codex
```

修改 `.env` 后重启服务:

```bash
bash rcc-server restart
```

## 常见排查

检查服务是否运行:

```bash
bash rcc-server status
```

检查端口是否响应:

```bash
curl -I http://localhost:8310
```

查看最近日志:

```bash
tail -80 /tmp/rcc.log
```

验证 `node-pty` 是否可加载:

```bash
node -e "require('/home/wd/remote-cc/server/node_modules/node-pty'); console.log('node-pty ok')"
```

重新执行安装:

```bash
bash install.sh -u admin -p admin -y
```
