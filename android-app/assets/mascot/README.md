# 吉祥物 PNG 放这里（蓝白英短猫）

把 7 张猫 PNG（**透明底**）按下面**文件名**放进本文件夹 `android-app/assets/mascot/`。
App 下次构建会自动用真猫替换 emoji 占位（文件没到位时回退 emoji，不影响编译）。

| 文件名 | 对应表情 | 用在 |
|---|---|---|
| `success.png`   | 举钱袋坐        | App 图标 / 记账成功 |
| `idle.png`      | 招手探头        | 首页待机 / 默认 |
| `overspend.png` | 捂脸流泪        | 超支预警 |
| `celebrate.png` | 跳起 + 爱心     | 存钱达成 |
| `empty.png`     | 趴睡            | 空状态 |
| `thinking.png`  | 托腮思考（灯泡）| 喵助手思考 |
| `report.png`    | 举板指点        | 统计锐评 / 喵助手 |

要求：透明底 PNG、正方形最佳、建议 ≥ 512×512。

## 怎么传（小白版）
1. 浏览器打开仓库，切到分支 `claude/hopeful-wozniak-pr2ne3`；
2. 进到 `android-app/assets/mascot/` 目录；
3. 点「Add file → Upload files」，把改好名的 7 张 PNG 拖进来；
4. Commit 到该分支即可。传完告诉我，我触发一次构建，真猫就上身了。
