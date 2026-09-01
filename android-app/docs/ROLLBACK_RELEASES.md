# Android 历史版本回退

## 为什么原始旧 APK 会被拒绝

Android 普通安装器把 `applicationId`、签名证书和 `versionCode` 作为升级边界。同包名且同签名只能保证“有资格覆盖”，不能绕过版本保护；待安装包的 `versionCode` 低于已安装值时，系统返回 `INSTALL_FAILED_VERSION_DOWNGRADE`。`REQUEST_INSTALL_PACKAGES` 只允许应用拉起安装器，不等于获得降级权限。`adb install -d`、系统商店回滚和特权安装器是另外的路径，普通肥喵应用不能调用它们。

肥喵之前的失败是两件事叠加：发布版本号一直递增，而历史 APK 保留了旧的 `versionCode`；同时更新检查只看 Flutter 编译时的版本号。于是即使旧包签名正确，系统也会拒绝，或者回退包安装后又被错误地提示升级。

## 兼容包规则

历史代码必须重新签名为肥喵固定 release 证书，并把 Android 安装序号改成新的、全局递增的 `installVersionCode`。这个序号必须同时高于历史包的 `sourceVersionCode` 和当前线上/设备安装序号；否则目录看似可选，系统仍会拒绝安装。用户看到的历史版本仍使用 `versionName` 和 `sourceVersionCode`，两者不要混淆。每次生成兼容包后，后续正常版本也必须从更高的安装序号继续递增。

`android-app/ci/publish_rollback_catalog.sh` 发布的是 `rollback.json` 元数据，不上传 APK 本体。每个条目必须有：

- `versionName`、`sourceVersionCode`：历史版本信息；
- `installVersionCode`：安装器使用的递增序号；
- `url`：不可变的 HTTPS 地址（可放 R2、GitHub Release 或 Worker 分片）；
- `releaseId`：与发布包对应的标识；
- 可选 `sha256`、`databaseVersion`。

这样 Cloudflare KV 可以只保留当前发布包和上一个热回退包，完整历史包放在大文件归档中，不会再次把 KV 填满。若条目的 URL 指向本 KV 的分片，`publish_update.sh` 会从 `rollback.json` 读取其 `releaseId`，在清理时保留对应分片；指向外部 HTTPS 归档的条目不占用 KV。`publish_rollback_apk.sh` 会在上传前检查安装序号高于线上版本，且不能与现有目录重复，并只把这一个热回退包写入目录；要提供更早版本，应先放到外部不可变 HTTPS 归档，再用 `publish_rollback_catalog.sh` 发布目录元数据。

## 应用内行为

设置中的“历史版本”读取 `rollback.json`。只有 `installVersionCode` 高于系统当前实际安装序号的条目可点击，避免把必定失败的低序号 APK 交给安装器。下载仍复用 SHA-256 校验和 FileProvider 安装流程，安装前提示先导出账本备份。

更新检查通过原生 `PackageManager` 读取真实安装序号，而不是只读取旧代码内嵌的 Flutter `AppVersion.buildNumber`。因此兼容包安装后，普通更新不会把新包误判为可安装的低版本。

## 数据安全边界

安装覆盖本身不删除应用数据，但旧代码能否读取新数据库是独立问题。发布历史版本前必须用真实数据库 fixture 验证 `databaseVersion` 和迁移兼容性；无法验证的版本不进入目录。任何大版本回退前都应先导出肥喵备份。原始旧 APK（未生成兼容安装序号）仍不能保证覆盖安装，这是 Android 系统的版本保护，不是签名问题。
