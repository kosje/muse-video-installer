# Muse 视频工作台 · 一键安装

> 在**你自己的服务器**上，一条命令装好一个「输入文字就能生成视频」的网页工具。
> 装完后：浏览器打开网址 → 写一句话 → 出视频。还能让别的软件（Cherry Studio、NextChat 等）连上它调用接口。

**不需要懂 Linux，不需要懂 Docker。** 脚本会自己把该装的都装好。

---

## 目录

- [装之前要准备什么](#装之前要准备什么)
- [30 秒开始安装](#30-秒开始安装)
- [安装过程会问你什么](#安装过程会问你什么)
- [装完之后怎么用](#装完之后怎么用)
- [常用命令](#常用命令)
- [怎么卸载](#怎么卸载)
- [遇到问题怎么办](#遇到问题怎么办)
- [进阶：绑域名 + HTTPS](#进阶绑域名--https)
- [全部参数一览](#全部参数一览)

---

## 装之前要准备什么

| 需要 | 说明 |
|---|---|
| **一台服务器** | Linux（Debian / Ubuntu / CentOS / RHEL / Alpine 都行），能 SSH 登录，有 root 权限 |
| **至少 2 核 4G** | 因为要跑一个无头浏览器。内存小了会卡 |
| **至少 10G 空闲磁盘** | 程序本体 + 浏览器大约几百 MB |
| **能访问外网** | 第一次安装要从 GitHub 下载程序，网速慢会久一点 |
| **两个没被占用的端口** | 默认用 `18610`（接口）和 `8090`（网页）。被占了脚本会自动换 |
| **一个 muse.ai 账号** | 这是"燃料"。装完必须导入一个账号才能生成视频（见下文第 4 步） |

> ⚠️ **端口一定要在云服务商控制台放行**
> 阿里云 / 腾讯云 / AWS / Oracle 等都有"安全组"或"防火墙规则"。
> 装完如果网页打不开，九成是这里没放行 `8090` 和 `18610`。

---

## 30 秒开始安装

SSH 登录到你的服务器，然后：

```bash
# 1. 下载安装脚本（<你的仓库地址> 发布后会自动替换成真实链接）
curl -fsSL -o install.sh https://raw.githubusercontent.com/<你的GitHub账号>/muse-video-installer/main/install.sh

# 2. 跑起来（会问你 1-2 个问题）
sudo bash install.sh
```

> 📌 **拿不到脚本？** 三种办法任选：
> 1. 用 `scp` 把 `install.sh` 传到服务器：`scp install.sh root@你的服务器IP:/root/`
> 2. 或者直接把脚本内容复制粘贴到服务器上新建的文件里
> 3. 装完脚本后**别删**，以后 `--status` / `--upgrade` / `--uninstall` 都要用它

想**全自动、不问任何问题**：

```bash
sudo bash install.sh --yes
```

想**先看看它会做什么、但不动系统**：

```bash
sudo bash install.sh --dry-run
```

---

## 安装过程会问你什么

脚本只会问你 **1-2 个问题**，拿不准的直接按 **回车** 用默认值就行。

| 问题 | 默认 | 说明 |
|---|---|---|
| 装到哪个目录？ | `/opt/muse-video` | 一般不用改 |
| 用哪个端口？ | 自动挑 | 会先看 `18610` / `8090` 有没有被占，占了就往后找 |

然后它就自己干活了，大概 **2-5 分钟**：

```
▸ 开始检查环境
  ✓ 系统：debian 12（用 apt 装东西）
▸ 检查并安装 git / docker / docker compose
  ✓ docker 已就绪
▸ 准备程序文件
  ✓ 程序本体下载完成
▸ 配置密钥
  ✓ 已生成一把随机密钥（只显示在最后，请留意）
▸ 写入配置
  ✓ 接口端口 18610，网页端口 8090
▸ 启动服务
  ✓ 容器已启动
▸ 等待接口就绪
  ✓ 接口已响应（HTTP 401 属正常，说明在跑）
▸ 配置网页服务
  ✓ 网页服务已启动
```

最后会打印一份**"下一步"清单**，照着做就行。

---

## 装完之后怎么用

安装结束时会给你这些信息，**请截图保存**（尤其是 API Key）：

```
网页地址：      http://你的服务器IP:8090/
接口地址：      http://你的服务器IP:18610/v1
API Key：       m2a_xxxxxxxxxxxxxxxxxxxx
安装目录：      /opt/muse-video
账号池面板：    http://你的服务器IP:18610/admin?key=你的Key
```

### 第 1 步：打开网页看看

浏览器访问 `http://你的服务器IP:8090/`。
看到左边有「生成视频」按钮、右上角状态灯是**绿色**，就说明装好了。

### 第 2 步：导入你的 muse.ai 账号（⚠️ 必须做）

视频工作台是靠 **muse.ai 的账号**来出片的，所以得先给它一个账号。
你的服务器上**没有浏览器**，所以这一步要在**你自己的电脑**上做：

**a)** 下载导号小工具（在你自己电脑上，Windows 装了 Chrome 就能跑）：

```
https://github.com/czg86389-hub/muse2api/raw/main/tools/get_muse_cookie.py
```

**b)** 在同一个文件夹里打开命令行（Windows 按 `Win+R` 输入 `cmd` 回车，然后 `cd` 到那个文件夹），跑：

```bash
python get_muse_cookie.py --base http://你的服务器IP:18610 --key 你的Key
```

> 没装 Python？去 [python.org](https://www.python.org/downloads/) 下载安装，
> 安装时记得勾选 **"Add Python to PATH"**。

**c)** 会弹出一个浏览器窗口 → 在里面登录你的 muse.ai 账号。
登录完脚本会**自动把账号传上服务器**，看到「导入成功」就好了。

**d)** 去账号池面板确认一下：`http://你的服务器IP:18610/admin?key=你的Key`
里面应该有 **1 个账号**。

### 第 3 步：回到网页，测试生成

接口地址和 Key 脚本已经**自动填好了**。直接写一段描述，点「生成视频」，
等 **1-2 分钟**出片。

### 第 4 步（可选）：让别的软件连上它

任何支持 **OpenAI 兼容接口**的客户端都能连：

| 填什么 | 填什么值 |
|---|---|
| API 地址 / Base URL | `http://你的服务器IP:18610/v1` |
| API Key | `m2a_xxxxxxxxxxxx` |
| 模型名 | 见账号池面板里列出的模型 |

> ⚠️ **注意地址末尾只有一个 `/v1`，不要写成 `//v1`**（多一个斜杠会连不上）。

---

## 常用命令

脚本支持"记住上次的配置"，所以重跑这些命令**不用再带参数**：

```bash
sudo bash install.sh --status      # 看运行状态 + 找回地址和 API Key
sudo bash install.sh --upgrade     # 升级到最新版（Key 不变）
sudo bash install.sh --uninstall   # 卸载（默认保留数据）
sudo bash install.sh --help        # 看全部用法
```

### 再跑一次 `install.sh` 会怎样？

直接 `sudo bash install.sh` 会**接上已有安装**，不会重头来：

| 东西 | 行为 |
|---|---|
| 端口 | 沿用上次的（除非你显式给新端口） |
| **API Key** | **沿用上次的**（客户端不用重配）✅ |
| 账号数据 | 保留 |
| 程序本体 | 拉取最新代码 |
| 容器 | 原地重建 |

所以"想改点东西再装一遍"是安全的。

### 直接管容器（进阶）

```bash
# 看日志
cd /opt/muse-video && docker compose logs -f

# 重启
cd /opt/muse-video && docker compose restart

# 看网页服务日志
journalctl -u muse-video-web.service -f
```

---

## 怎么卸载

```bash
sudo bash install.sh --uninstall
```

默认行为：

| 东西 | 卸载后 |
|---|---|
| 容器（muse-video） | ✅ 删除 |
| 网页 systemd 服务 | ✅ 停止并删除 |
| **安装目录 `/opt/muse-video`（含账号数据）** | **保留**（怕你误删） |

想**连数据一起删干净**，卸载后手动执行：

```bash
sudo rm -rf /opt/muse-video
```

---

## 遇到问题怎么办

### ❌ 网页打不开 / 转圈

1. **先查云服务商安全组** —— 90% 是这个原因。放行 TCP `8090` 和 `18610`。
2. 在服务器上本地试一下：
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/
   ```
   返回 `200` 说明服务没问题，就是防火墙/安全组的事。
3. 看网页服务状态：
   ```bash
   sudo bash install.sh --status
   ```

### ❌ 客户端报「连接失败」

**99% 是地址写错了。** 检查：

- 末尾是不是**只有一个** `/v1`（`http://IP:18610//v1` ← 错，多了一个斜杠）
- 端口对不对（默认 `18610`，装的时候可能自动换过）
- 服务器安全组放行了没

### ❌ 我忘了 API Key 是多少

不用重装，直接查：

```bash
sudo bash install.sh --status
```

输出里有一段「**连接信息**」，会把网页地址、接口地址、API Key、账号池面板链接全列出来。

### ❌ 重跑一遍安装，会不会把 Key 换掉？

**不会。** 脚本会沿用上次的 Key，并在输出里告诉你「沿用上次的密钥（客户端不用重配）」。
所以你可以放心重跑（改端口、改目录都可以），已配置好的客户端不受影响。

> 如果你**确实想换一把新 Key**：手动删掉安装目录里的 `install.conf`，
> 或者改掉 `docker-compose.yml` 里的 `MUSE2API_KEY`，再重跑。

### ❌ 网页能开，但生成视频报错 / 一直转

账号没导入或掉线了。先看 `--status`，如果提示「账号池是空的」：

```
http://你的服务器IP:18610/admin?key=你的Key
```

账号数量是 `0` → 重跑[第 2 步](#第-2-步导入你的-museai-账号-必须做)导号。
有账号但报错 → 重新导一次（账号会过期，脚本会每 48 小时自动续期，但偶尔会失效）。

### ❌ 安装时报「端口已被占用」

```bash
# 看谁占了 8090
sudo ss -lntp | grep 8090
```

要么停掉那个服务，要么换个端口：

```bash
sudo bash install.sh --api-port 19000 --web-port 9000
```

### ❌ 自定义端口后，本地通了但远程连不上

这是**上游程序的一个坑**（它的 Dockerfile 把端口写死成 18610）。
**本脚本已经处理好了**（用 `command` 显式覆盖端口）。
如果你是自己手动部署遇到这个，需要在 `docker-compose.yml` 里加：

```yaml
command: ["sh", "-c", "python -m uvicorn app:app --host 0.0.0.0 --port 你的端口"]
```

### ❌ 内存不够 / 容器被 OOM 杀掉

无头浏览器吃内存。2G 内存的机器建议升到 4G，或者在云控制台加 swap。

### ❌ 安装卡在「下载程序本体」

服务器访问 GitHub 慢。可以：
- 换个时间再试
- 或者在你本地下载好，用 `scp` 传上去，再跑安装

---

## 进阶：绑域名 + HTTPS

如果你的域名已经解析到了这台服务器，装的时候加一个参数就自动配好 HTTPS：

```bash
sudo bash install.sh --domain video.你的域名.com
```

脚本会自动：
- 用 Caddy 起一个反代
- 自动申请 Let's Encrypt 免费证书
- 装完直接 `https://video.你的域名.com/` 访问

> ⚠️ 前提：域名**必须**已经解析到这台服务器的公网 IP，且 **80 / 443 端口没被别的程序占用**。
> 如果这台机器上已经有 Caddy/Nginx 在跑，脚本会提示你，需要手动加一段配置。

不要域名（默认）：

```bash
sudo bash install.sh --no-domain
```

---

## 全部参数一览

```
用法：sudo bash install.sh [选项]

常用：
  --yes, -y            全自动安装，所有问题用默认值（适合脚本/CI）
  --dry-run            只显示会做什么，不实际改动系统
  --status             看当前运行状态
  --upgrade            升级到最新版
  --uninstall          卸载
  --help, -h           显示帮助

进阶：
  --dir <路径>         安装到哪个目录（默认 /opt/muse-video）
  --api-port <端口>    接口服务端口（默认自动挑，常用 18610）
  --web-port <端口>    网页端口（默认自动挑，常用 8090）
  --domain <域名>      给网页绑域名并自动配 HTTPS
  --no-domain          不要域名（默认就是不要）
  --no-deps            不自动装依赖，缺什么只告诉你
```

**示例：**

```bash
# 全自动，指定网页端口
sudo bash install.sh --yes --web-port 8090

# 装到自定义目录，用自定义端口
sudo bash install.sh --dir /data/video --api-port 19000 --web-port 9000

# 绑域名
sudo bash install.sh --domain video.example.com
```

---

## 同一台机器装多份？

**可以。** 脚本会**从安装目录自动派生容器名和服务名**，所以：

```bash
sudo bash install.sh --dir /opt/muse-video-2 --api-port 18620 --web-port 8100
```

两份互不干扰，各自独立端口、独立账号池。

---

## 卸载 / 排障速查

| 我想… | 命令 |
|---|---|
| 看状态 | `sudo bash install.sh --status` |
| 升级 | `sudo bash install.sh --upgrade` |
| 卸载 | `sudo bash install.sh --uninstall` |
| 看容器日志 | `cd /opt/muse-video && docker compose logs -f` |
| 看网页日志 | `journalctl -u muse-video-web.service -f` |
| 看谁占端口 | `sudo ss -lntp \| grep <端口>` |

---

## 关于

- 程序本体：[czg86389-hub/muse2api](https://github.com/czg86389-hub/muse2api)（MIT 协议）
- 本安装脚本：把部署、导号、网页工作台串成一条命令，面向不懂 Linux 的用户
- 安装脚本版本：`1.0.0`

### 文件说明

| 文件 | 用途 |
|---|---|
| `install.sh` | **主脚本**，你要用的就是它 |
| `README.md` | 本说明文档 |
| `test-install.sh` | 回归测试套件（开发者用，会自动装一份到 `/opt/muse-regress` 再卸载） |

### 跑回归测试（可选）

```bash
sudo cp install.sh /root/install-muse-video.sh
sudo bash test-install.sh
```

会依次验证：语法、参数校验、dry-run 无副作用、真实安装、结果核验、
`--status`、幂等重跑、端口冲突拦截、卸载、卸载后复检、清理。

> ⚠️ 测试会在 `/opt/muse-regress` 和端口 `28710/28711` 上操作。
> 如果这台机器上有**正式服务也叫 `muse-regress-*`**，请先改测试脚本里的变量名。

> 💡 **免责声明**：本脚本只是部署工具，视频生成能力来自 muse.ai 的账号。
> 请遵守 muse.ai 的服务条款，不要滥用。
