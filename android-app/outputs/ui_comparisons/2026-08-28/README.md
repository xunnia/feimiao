# 2026-08-28 全局 UI 前后对比

每张 PNG 都是同一场景的真实截图并排拼接：左侧“改动前”，右侧“改动后”。橙色编号框对应图片底部的改动说明；原始截图没有被覆盖。

| 文件 | 场景 |
| --- | --- |
| `01_global_settings_before_after.png` | 全局设置页 |
| `02_global_gallery_before_after.png` | 全局设置控件画廊 |
| `03_ai_account_before_after.png` | AI 账号设置 |
| `04_home_input_before_after.png` | 主页/喵助手输入框 |
| `05_assistant_fullscreen_before_after.png` | 喵助手全屏会话 |
| `06_claude_add_sheet_before_after.png` | Claude 风格加号菜单 |
| `07_recent_photos_before_after.png` | 加号菜单·最近照片 |
| `08_four_images_before_after.png` | 多图草稿输入（回归基线） |
| `09_chats_before_after.png` | Chats 会话列表 |
| `00_all_ui_comparisons_contact.png` | 本批总览联系图 |

生成命令（不改动源码和原图）：

```powershell
& 'C:\Users\寻逆啊\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'android-app\tooling\make_ui_comparisons.py'
```
