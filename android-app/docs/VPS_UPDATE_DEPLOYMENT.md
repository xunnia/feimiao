# 肥喵 Android 更新分发：VPS 迁移交接

## 当前生产入口

### 2026-09-12 启动完整性发布（当前）

- 正常版 1.293.0+308 / `v308-73df20b0ba3c`，117936705 字节。
- SHA256 `73df20b0ba3c1a3af1cfe5f0f9ef7cc0f0a38c5df155239493a54cf3dcdc213e`。
- 发布脚本 exit 0；新旧版本接口一致，Range 下载片段匹配；线上保留 306/307/308 三包，305 线上副本及回退目录条目已清理，本地 305 原包保留。
- rollback.json 当前 versions 为空；保留正常版本包不代表可以直接降级覆盖安装。真机安装/冷启动、完整公网下载哈希复验尚未完成。

### 2026-09-11 抽屉修复发布（当前）

- 当前正常版：1.292.0+307 / `v307-cdae672e13db`，117920321 字节。
- SHA256：`cdae672e13db58e1926781293216d2007b1cf69d2613790eba8591de2ced2daf`。
- 现有发布脚本及 APK 身份门禁成功；服务器保留 305、306、307 三包，304 线上副本已清理，本地安装包仍保留。
- 公网新旧 version.json 均指向 307；Range 206 内容片段与本地包一致，回退目录仍含专用 305 包。保留旧包不表示其低安装序号可直接覆盖新版本。
- 1217 项 Flutter 测试通过；真实安装/冷启动及公网整包下载哈希复验尚未完成。

### 2026-09-10 正常版发布

- 已通过 `ci/publish_update.sh` 发布 `1.291.0+306`，releaseId `v306-9f53f8216ba8`，117920317 字节。
- SHA256：`9f53f8216ba8671c2ded45a73cb6a09b51ef253b08dec951ae9b8a2cd8b658a6`。
- 发布脚本返回成功，公网 version.json 已确认 306；保留 v304、v305 专用回退包及 v306，共 3 个 APK，本次无旧包删除。
- Bash 工具在真实用户权限下显式设置 `/usr/bin:/mingw64/bin` 后可用，固定证书/V2/16 KiB 校验脚本实际通过。
- 注意：v305 回退包被保留不表示它能覆盖安装到 v306；安装更高序号后的回退仍需另制兼容包并验证数据库。
- 手机安装和冷启动尚未验收；以下迁移初始版本状态保留为历史记录，以本节为准。

- 新入口：`https://updates.xunni.dpdns.org/version.json`
- APK：`https://updates.xunni.dpdns.org/feimiao-latest.apk?release=<releaseId>`
- 历史回退目录：`https://updates.xunni.dpdns.org/rollback.json`
- 旧域名 `updates.xunni9481.dpdns.org` 的三个接口以 307 跳转到新域名，保留路径及查询参数；旧 App 不必先升级才能检查更新。
- 旧 Worker 当前部署版本：`36c8996c-b10c-455e-a15b-8429b73a9b9a`。
- 没有修改 Android 功能、数据库、安装包版本或签名；客户端硬编码旧域名仍通过兼容入口工作。

## 版本与保留规则

- 当前正常版：`1.289.0+304`，`v304-eab0de7bd68d`，117822013 字节。
- 当前专用回退包：源 `1.279.0+293`，安装序号 `305`，`v305-4ded431ba419`，58438392 字节。
- **305 已被回退包占用，下次正常版本必须大于 305。不要发布本机同序号的普通开发包。**
- VPS 目前只有上述两个不同 APK，总计约 168 MiB。`current.apk` 是软链接，不另占一份包空间。
- 每次正常发布后最多保留 **3 个 APK**：当前正常版及按安装序号排序的最新两包（包括已发布专用回退包）。不足三包不凑数。
- 新包完成校验与发布后才清理更旧包；同步删除回退目录中不再保留的条目，避免失效入口。发现未知文件、哈希不符、身份冲突时停止。
- 此次未删除 Cloudflare 原 KV 分片，暂留作迁移回退。它们不会随新发布自动更新。

## VPS 布局及隔离

- `/srv/feimiao-updates/public/releases/`：APK 及单包元数据。
- `/srv/feimiao-updates/public/version.json`、`rollback.json`：公开元数据。
- `/srv/feimiao-updates/bin/finalize.py`：锁定发布事务和三包清理。
- `/srv/feimiao-updates/incoming/`：上传暂存，不公开。
- `/srv/feimiao-updates/migration-staging/`：迁移时旧元数据，不含额外 APK。
- Caddy 只读访问肥喵公开目录；无额外数据库、后台 App 进程或开放业务端口。程序/元数据由 root 发布，不允许 Caddy 写入。
- 本轮只实现肥喵文件权限隔离，共享现有 Caddy。其他项目的容器、运行用户和资源限制并未重新配置；不能据此宣称整台 VPS 已完成隔离审计。

## 今后正常发布

在 Git Bash 中继续使用原入口：

```bash
bash ci/publish_update.sh <APK路径> <versionName> <versionCode> "更新说明"
```

原入口已转到 `ci/publish_update_vps.sh`。流程：固定签名/包名/内部版本/16 KiB 检查 → 在线发布身份检查 → SSH/SCP 上传 → VPS 上锁并再次检查哈希、身份与回退保留序号 → 切换公开版本 → 清理至最多三包 → 公网元数据复验。

本机默认使用 `dedirock_ed25519` SSH 密钥及同目录 `known_hosts`；严格主机指纹检查保持开启。可显式设置 `FEIMIAO_SSH_KEY`、`FEIMIAO_KNOWN_HOSTS`、`FEIMIAO_SSH_HOST`。不能关闭指纹校验绕过连接问题。

**旧 `publish_rollback_apk.sh`、`publish_rollback_catalog.sh` 仍属于 CF 流程，不可用于新的 VPS 回退包发布。** 现有回退入口已经迁移且可下载；未来新增专用回退包需另行适配 VPS 发布流程及其签名、序号、数据库兼容性门禁。不要手改 JSON 绕过这些检查。

## 实际验收

- 两个 APK 从新域名完整 HTTPS 下载：大小、SHA256 均与迁移前线上一致。
- 新域名 Range：206、Content-Length、Content-Range 正常；未知 release 返回404。
- 旧域名 version.json 跳转后最终为新域名；旧 APK URL 跟随跳转后 Range 实测206、16字节。
- 6 个 Worker 跳转检查、9 个既有版本门禁测试、5 个三包策略/身份检查通过。
- VPS 实际同版发布事务通过；完整本机发布入口使用原304包端到端跑通，16 KiB/V2/固定证书验证、SCP、哈希核对、发布均成功，线上版本未变化。
- 没有重新构建 APK，也没有执行 Flutter 全量功能测试；本轮未改 App 功能。手机更新检查/下载/安装体验仍待真机验证。

## 回退与安全

- Caddy 修改前备份：`/root/feimiao-caddy-backup-20260908-105749/Caddyfile`。恢复前必须比较之后的其他站点变更，不能直接覆盖整个文件。
- 原 Worker/发布脚本本地备份：`C:\project\VPS搭建\feimiao-pre-vps-20260909`。
- Worker 回退：可使用 Cloudflare 旧部署版本，或经检查后恢复备份源码并部署。VPS 发布新版本以后，旧 KV 不再是最新版本，不能盲目切回。
- DNS Token 已在当前 Windows 用户下加密保存；限制 xunni.dpdns.org 区域以及 VPS IPv4 来源。不要复制明文到仓库、VPS磁盘或聊天。
- APK 签名私钥未上传 VPS；现有 CPA/Sub2API/Komari/Xray/HY2 没有因迁移重装或重配。
- 本轮源码修改尚未提交或推送 Git；用户原有 `ci-artifacts/` 未纳入提交。
