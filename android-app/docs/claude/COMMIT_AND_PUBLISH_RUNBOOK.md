# 提交与发布操作手册（commit + 线上发布）

> 面向：Claude / Codex(GPT) / 人工。这是机械流程 SOP，照抄命令即可。
> 出处：2026-07-14 由 Claude 从多轮实操中固化，所有坑都是真踩过的。
> 关联：`CLAUDE_START_HERE.md`（当前状态）、`肥喵记账App开发笔记.md`（长期规则）。

---

## 0. 环境前提（先判断你能做哪几步）

| 步骤 | 需要什么 | Codex(GPT) 环境 | Claude 环境 |
|---|---|---|---|
| A 提交 commit | git | ✅ 能 | ✅ 能 |
| B 出包 build APK | Flutter 工具链 | ✅ 能 | ✅ 能 |
| C 发布上线 | wrangler **已 OAuth 登录** Cloudflare | ⚠️ 通常没有 → 做不了 | ✅ 能（本机已登录 178517877qq@gmail.com）|

**判断发布能力**：`cd android-app/ci/update-worker && npx wrangler whoami`。
出现 `You are logged in` = 能发；`not authenticated` = 只能做到 A/B，发布交给有登录态的环境。

**铁律：所有 bash 脚本必须在 Git Bash 里跑，不能用 PowerShell 里的 `bash`（那是 WSL，处理不了 Windows 路径，`stat`/`sha256sum` 第一步就挂）。**

GitHub Android CI 的门禁：Pull Request 以及 `codex/**`、`claude/**`、`main` 的 push 都执行 release 脚本语法/单测、analyze、Flutter 全量测试和 release 编译；只有权威发布分支 `codex/feimiao-p0-fixes` 的 push 能签名、上传 artifact 和覆盖 `android-latest`。该分支必须配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS` 四个 Secret，任意一个缺失都会失败，绝不发布临时 debug 签名包。验包后 CI 还会读取线上 `version.json`：只允许更高 versionCode，或与线上完全相同的幂等身份；同 versionCode 但 versionName/SHA/releaseId 不同会失败，读取线上状态失败也会关闭发布。只有门禁通过才上传 artifact。同一分支的新 push 会取消旧的在途构建，避免旧包晚完成后反向覆盖新版。

---

## A. 提交 commit

### A.1 先确认工作树稳定（别在别人写一半时提交）

```bash
cd /c/src/xunni-codex
git status --short | head -40
# 判断有没有人还在写（2分钟内被改的源文件；空=停手了）
find android-app/lib android-app/test -name "*.dart" -mmin -2
```

### A.2 精确 stage（**绝不用 `git add .`**）

只加源代码、测试、脚本、文档和版本文件。**APK 和其本地 SHA 文件不进 Git**，它们只保存在本机忽略目录、GitHub Release 或 Cloudflare：

```bash
cd /c/src/xunni-codex
git add android-app/lib android-app/test android-app/docs \
        android-app/ci android-app/CHANGELOG_CODEX.md android-app/pubspec.yaml
# 如果动了原生层再加：git add android-app/android
# 如果动了 CI/忽略规则再加：git add .github/workflows/android-ci.yml .gitignore
# AGENTS.md 是正式交接文件，只有确实更新了交接内容时才单独 git add AGENTS.md。
```

**必须排除、绝不能进提交的东西**：`.codex/`、`.playwright-cli/`、`android-app/outputs/`、Wrangler 本机账号缓存、所有 APK 和本地 SHA 产物。根 `.gitignore` 已拦截新产物；历史里已有 APK 的删除应作为仓库清理单独提交，别混进功能提交。

### A.3 核对暂存区没混入垃圾

```bash
git diff --cached --name-only | grep -iE "\.codex|outputs/|playwright" && echo "⚠️有垃圾误入,撤销:git restore --staged <文件>" || echo "✓干净"
git diff --cached --name-only | grep -iE "\.apk($|\.)" && echo "⚠️APK/哈希不应进入 Git" || echo "✓无 APK 产物"
```

### A.4 提交（消息格式固定）

```bash
git commit -m "<一句话标题> <versionName>+<versionCode> b<buildTag>

<正文:做了什么;若验收他人代码,写清逐项核实结论analyze/test数字>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
- `warning: LF will be replaced by CRLF` 是正常的 Windows 换行提示，**不是错误**，忽略。
- 若是 GPT 提交，Co-Authored-By 换成对应署名或去掉。

---

## B. 出包 build APK

### B.1 四处版本号同步（缺一处装包会出错）

```bash
cd /c/src/xunni-codex/android-app
sed -i 's/^version: <旧>/version: <新versionName>+<新versionCode>/' pubspec.yaml
sed -i "s/version = '<旧>'/version = '<新versionName>'/; s/buildNumber = <旧>/buildNumber = <新versionCode>/" lib/core/app_version.dart
sed -i "s/kBuildTag = 'b<旧>'/kBuildTag = 'b<新tag>'/" lib/build_info.dart
sed -i 's/flutter.versionName=<旧>/flutter.versionName=<新versionName>/; s/flutter.versionCode=<旧>/flutter.versionCode=<新versionCode>/' android/local.properties
```
规则：versionName minor +1、versionCode **只增不减**、buildTag=`b<日期>-<versionCode>`（如 `b0714-195`）。

### B.2 验证 + 构建（**测试退出码必须落文件查，别接管道**）

```bash
cd /c/src/xunni-codex/android-app
flutter analyze --no-pub > /tmp/an.log 2>&1; echo "ANALYZE=$?"; tail -1 /tmp/an.log
flutter test --no-pub > /tmp/test.log 2>&1; echo "TEST=$?"; tail -1 /tmp/test.log   # 必须 exit 0 + All tests passed
flutter build apk --release --no-pub
```
> **坑**：`flutter test | tail -1 && build` 这种管道会**吞掉测试退出码**（tail 恒 0），测试挂了 build 照跑。一定落文件查 `$?`。

### B.3 验包 + 归档

```bash
cd /c/src/xunni-codex/android-app
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
bash ci/verify_release_apk.sh build/app/outputs/flutter-apk/app-release.apk
# 本机归档目录已被根 .gitignore 忽略，只用于交付和复验
cd /c/src/xunni-codex
cp android-app/build/app/outputs/flutter-apk/app-release.apk ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk
SHA=$(sha256sum < ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk | awk '{print $1}')
echo "${SHA^^}" > ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk.sha256.txt
echo "$SHA"
```
验证脚本会同时核对包名、内部 versionName/versionCode、16 KiB ZIP 对齐、APK Signature Scheme v2、严格 DN，以及固定证书 SHA-256 `4E99C399D4D246BD9C6B08B1D641248BD0846E7AE650C3A766E30FA67483D507`。任一不符都会停止。

---

## C. 发布上线（publish）

> 前提：`wrangler whoami` 显示已登录。**在 Git Bash 里跑，不是 PowerShell/WSL。**

### C.1 常规发布（网络好时一条命令）

```bash
cd /c/src/xunni-codex/android-app
bash ci/publish_update.sh \
  "C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v<versionName>-<versionCode>.apk" \
  "<versionName>" "<versionCode>" "<给用户看的更新说明>"
```
脚本干的事（**先门禁、后原子上传**）：
1. 用 `aapt`、`zipalign` 和 `apksigner` 核对包名、APK 内部版本、16 KiB 对齐、v2 签名、严格 DN 与固定证书指纹；工具缺失直接失败。
2. 生成候选发布身份并读取线上 `version.json`，交给 `release_gate.mjs` 统一判断：versionCode 更高才继续上传；完整身份与线上一致则按幂等成功直接结束；降级、同 versionCode 不同身份、网络或 JSON 异常都直接失败。分片上传完成后、切换指针前会再次读取线上身份，阻止并发发布把新版本覆盖回旧版本。
3. 把 APK 切成 24MB 分片并逐个上传，每个 KV 写入最多重试 5 次。
4. 传 manifest `apk:<releaseId>:manifest`，**最后**才切换 `version.json`。
5. 指针切换成功后自动执行保留策略：按 `versionCode` 保留当前版本和上一份完整版本，删除更旧分片；未知键、当前 release 不完整或指针变化会安全中止清理。

所以**任何一步在切 version.json 之前失败，线上都还是旧版本，生产环境零风险**，直接重跑即可；若上一次其实已经切换成功，重跑会识别为同一身份并幂等结束，不会重复上传。若只在清理阶段遇到网络抖动，重跑同一命令会走幂等分支并修复“两版本保留”状态。

### C.2 线上验证（发完必做，三重）

```bash
# ① version.json 是否更新、sha256 是否干净
curl -s --max-time 20 "https://updates.xunni9481.dpdns.org/version.json" \
 | python -c "import json,sys;d=json.load(sys.stdin);print(d['versionCode'],d['versionName'],d['sha256'][:16],d['releaseId'])"
# ② 逐分片拉回拼接,哈希必须==源APK(比整包下载更严格,且能绕过本机大文件长连接抖动)
#    releaseId 和分片数 N、末片大小 last 见 manifest;下面以 N=5 为例
cd android-app/ci/update-worker; NSID=34c07e0793ea4fb8a526dd28eb1aa1b0; RID=v<versionCode>-<sha前12>
for i in $(seq 0 $((N-1))); do
  for t in 1 2 3 4 5; do npx --yes wrangler kv key get --namespace-id=$NSID --remote "apk:$RID:$i" > /tmp/dl$i.bin 2>/dev/null && break; done
done
cat /tmp/dl*.bin | sha256sum   # 必须 == 归档 APK 的 sha256
```
`sha256`/`releaseId` 里若出现 `\` 前缀 = 污染（历史事故），发布脚本已改 stdin 计算，不该再出现；万一出现，先停止发布并修复元数据。发布完成后 KV 预期只剩当前版本、上一版本和 `version.json`。

### C.3 网络抖动兜底

发布脚本已经对每个 KV 写入做 5 次重试。仍失败时直接重跑同一条 `publish_update.sh` 命令；在 `version.json` 成功切换前，客户端始终看到旧版，已经切换成功则会幂等结束。**不要手工上传或改写 `version.json` 绕过验包和发布身份门禁。**

### C.4 Worker 源码改动后要重新部署

只在改了 `ci/update-worker/src/index.js` 时需要（普通发版不用）：
```bash
cd /c/src/xunni-codex/android-app/ci/update-worker && npx wrangler deploy
```
**这是生产部署，必须用户明确授权后再执行。**

---

## D. 发完必做的收尾

1. 交接文档三处状态改成"已提交+已上线"：`CLAUDE_START_HERE.md` §1/§4、`CLAUDE_HANDOFF_CURRENT.md`、`CHANGELOG_CODEX.md` 顶部、Obsidian 笔记。
2. 把这次的 commit hash、releaseId、验证结果写进 changelog。
3. 提醒用户：**带 DB 迁移的大版本，升级前会自动 `pre-v<旧版本>.bak` 备份；用户装完要核对账单/资产/预算/净资产数字与升级前一致。**

---

## E. 关键坑清单（都真踩过）

| 坑 | 后果 | 对策 |
|---|---|---|
| PowerShell 里 `bash` = WSL | `stat`/路径第一步就挂 | 只在 **Git Bash** 跑脚本 |
| `flutter test │ tail && build` | 吞测试退出码,挂了照发 | 测试落文件查 `$?` |
| `sha256sum <Windows路径>` | coreutils 加 `\` 前缀污染 releaseId/sha | 脚本已改 stdin；发后 curl 复验 sha 干净 |
| `git add .` | 扫进 codex 垃圾/中间包/删除 | 精确 add 指定路径 |
| 别人写一半时提交 | 半成品被固化、编译挂 | 先 `git status`+`find -mmin -2` 确认停手 |
| Cloudflare 连接抖动 | 脚本 `fetch failed` | 逐分片带重试(C.3);原子设计保证线上不坏 |
| 签名 keystore 不对 | 覆盖安装失败/数据丢 | `verify_release_apk.sh` 同时核对完整签名、严格 DN 和固定 SHA-256 指纹 |
| 版本号只改 1-2 处 | 装包/更新异常 | 四处同步(pubspec/app_version/build_info/local.properties) |

## F. 快速检查清单

**提交前**：□ 工作树停手 □ 精确 stage □ 无垃圾/中间包/删除混入 □ 消息含验证数字
**出包前**：□ 四处版本同步 □ analyze 0 □ test exit0+All passed □ 验包脚本通过（包名/内部版本/16 KiB/v2/签名指纹） □ sha 记录
**发布后**：□ version.json 版本对+sha 干净 □ 逐分片拼接哈希==源 □ 文档三处更新
