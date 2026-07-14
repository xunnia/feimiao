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

只加代码/测试/文档/版本文件 + **当前这一个** release APK：

```bash
cd /c/src/xunni-codex
git add android-app/lib android-app/test android-app/docs \
        android-app/CHANGELOG_CODEX.md android-app/pubspec.yaml
# 如果动了原生层再加：git add android-app/android
# 当前 release APK（只加最终那一个，不加中间迭代包）：
git add ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk \
        ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk.sha256.txt
```

**必须排除、绝不能进提交的东西**（`git add .` 会把它们扫进来，所以别用）：
- codex 工作垃圾：`.codex/`、`.playwright-cli/`、`AGENTS.md`、`android-app/outputs/`
- 中间迭代 APK（只留最终发布那一版）
- 旧 release APK 的**删除**状态（`D ci-artifacts/releases/...`）——这是清理旧包，**单独提一笔**，别混进功能提交

### A.3 核对暂存区没混入垃圾

```bash
git diff --cached --name-only | grep -iE "\.codex|outputs/|AGENTS|playwright" && echo "⚠️有垃圾误入,撤销:git restore --staged <文件>" || echo "✓干净"
git diff --cached --name-only | grep "\.apk$"   # 应只有 1 个 APK
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
AAPT=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools/"*/aapt.exe | tail -1)
"$AAPT" dump badging build/app/outputs/flutter-apk/app-release.apk | head -1   # 核对 versionCode/versionName/包名
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
SIGNER=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools/"*/apksigner.bat | tail -1)
"$SIGNER" verify --print-certs build/app/outputs/flutter-apk/app-release.apk 2>&1 | grep "certificate DN"
# 归档到 releases 并记录哈希
cd /c/src/xunni-codex
cp android-app/build/app/outputs/flutter-apk/app-release.apk ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk
SHA=$(sha256sum < ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk | awk '{print $1}')
echo "${SHA^^}" > ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk.sha256.txt
echo "$SHA"
```
必须核对：包名 `com.qingji.qingji.codex`、versionCode 对、签名 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。签名不对=覆盖安装失败/数据丢，**停止**。

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
脚本干的事（**原子设计**，理解这点就不怕中途失败）：
1. 把 APK 切成 24MB 分片，逐个传 `apk:<releaseId>:<i>`（releaseId = `v<versionCode>-<sha256前12位>`）
2. 传 manifest `apk:<releaseId>:manifest`
3. **最后**才切换 `version.json`

所以**任何一步在切 version.json 之前失败，线上都还是旧版本，生产环境零风险**，直接重跑即可。

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
`sha256`/`releaseId` 里若出现 `\` 前缀 = 污染（历史事故），发布脚本已改 stdin 计算，不该再出现；万一出现，直接改写 KV 的 `version.json` 和 manifest 的 sha256 字段为干净 64 位 hex 即可（chunk 键名保持原样）。

### C.3 网络抖动兜底（脚本反复 `fetch failed` 时用）

Cloudflare 连接从本机偶尔抽风，脚本不断点续、每次从 chunk 0 重传很浪费。改**逐分片带重试手动传**（version.json 仍最后传，保原子）：

```bash
SP=/tmp/pub; rm -rf $SP; mkdir $SP
APK=/c/src/xunni-codex/ci-artifacts/releases/feimiao-codex-v<versionName>-<versionCode>.apk
split -b 24m -d -a 2 "$APK" "$SP/chunk-"          # 切片
cd /c/src/xunni-codex/android-app/ci/update-worker
NSID=34c07e0793ea4fb8a526dd28eb1aa1b0
RID=v<versionCode>-<sha前12>
KV="npx --yes wrangler kv key put --namespace-id=$NSID --remote"
# 逐片重试
i=0; for f in "$SP"/chunk-*; do
  for t in 1 2 3 4 5 6; do $KV "apk:$RID:$i" --path "$f" && break; sleep 3; done; i=$((i+1)); done
# 写 manifest.json = {releaseId,chunks:N,size:<字节>,sha256:<64位>} 后:
$KV "apk:$RID:manifest" --path /tmp/manifest.json
# 最后原子切换 version.json = {versionName,versionCode,url,notes,sizeBytes,sha256,releaseId}
$KV "version.json" --path /tmp/version.json
# url 固定为: https://updates.xunni9481.dpdns.org/feimiao-latest.apk?release=<releaseId>
```
写 manifest/version.json 的字段照 C.1 脚本里的 node 段一模一样，或参考已发布版本的 version.json。

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
| 签名 keystore 不对 | 覆盖安装失败/数据丢 | `codex-upload-keystore.jks` alias `codexupload`;apksigner 核对 DN |
| 版本号只改 1-2 处 | 装包/更新异常 | 四处同步(pubspec/app_version/build_info/local.properties) |

## F. 快速检查清单

**提交前**：□ 工作树停手 □ 精确 stage □ 无垃圾/中间包/删除混入 □ 消息含验证数字
**出包前**：□ 四处版本同步 □ analyze 0 □ test exit0+All passed □ aapt 版本对 □ 签名 DN 对 □ sha 记录
**发布后**：□ version.json 版本对+sha 干净 □ 逐分片拼接哈希==源 □ 文档三处更新
