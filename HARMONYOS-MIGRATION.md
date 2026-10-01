# 诗客 iOS → HarmonyOS 重构对照清单

> 本文档基于对当前代码库的全面分析（约 1.75 万行 Swift），作为在 Windows + DevEco Studio 上重构的参考。
>
> - iOS 工程：XcodeGen（`project.yml`），bundle id `com.raowenjie.Poetry`，iOS 17+，SwiftUI
> - 目标：HarmonyOS NEXT，ArkTS + ArkUI（声明式 UI，与 SwiftUI 概念高度相似）
> - 应用名：诗客；URL scheme：`shike://`；语言：中（简/繁）/英

---

## 一、迁移什么：资产清单

**4.3GB 仓库中真正需要迁移的只有 ~200MB**，其余是 `.asc/` 下的 IPA/xcarchive 构建产物（已被 .gitignore 排除，不要带上）。

| 内容 | 大小 | 迁移方式 | 鸿蒙 destination |
|---|---|---|---|
| 图片 `Poetry/Assets.xcassets`（水墨背景、诗人头像、AppIcon） | 91MB | 原样复制 | `AppScope/resources/base/media` + `entry/src/main/resources/base/media`（注意 xcassets 的 imageset 目录取出纯 PNG） |
| 字体 `Poetry/Fonts/`（6 个 ttf/otf） | 73MB | 原样复制 | `entry/src/main/resources/rawfile/fonts/` |
| 音频 `Poetry/Audio/`（9 首 m4a 配乐） | 28MB | 原样复制 | `entry/src/main/resources/rawfile/audio/` |
| 诗词 JSON（唐诗 319 / 宋词 280 / 今译 / 赏析 / 英文题名，id 全部对齐） | ~1.5MB | 原样复制 | `resources/rawfile/` |
| 引导视频 `WidgetGuide.mp4` | 0.9MB | 原样复制 | rawfile |
| Swift 代码 ~1.75 万行 | — | **重写为 ArkTS** | `entry/src/main/ets/` |

> xcassets → 普通图片的转换：每个 `.imageset` 里有实际 PNG，写个脚本展开平铺即可，文件名保持语义化（如 `bg_peaks_landscape.png`）。

---

## 二、模块级对照表

### App 骨架

| iOS | HarmonyOS | 说明 |
|---|---|---|
| `@main PoetryApp` + `RootContentView` | `EntryAbility` + `pages/Index` | `hasSeenOnboarding` 决定引导页/主页，对应存 Preferences |
| `TabView` 四 Tab（赏诗/诗人/成诗/我的） | `Tabs` 组件 | 朱砂红 tint → tabBar 配色 |
| `NavigationStack(path: [PoetRoute])` | `Navigation` + `NavPathStack` | `PoetRoute` 枚举 → 一个路由表 + `pushPath` |
| `@AppStorage`（字体/简繁/背景/印章等偏好，十几个 key） | `AppStorage`（键值同名迁移） | 语义几乎一致 |
| `@Observable` / `@ObservedObject` / `@EnvironmentObject` | `@ObservedV2` / `@Local` / `AppStorage` + 模块级单例 | ArkTS V2 状态管理 |
| `.onOpenURL`（`shike://poem?id=`、`shike://autumn`） | `EntryAbility.onCreate` 里 `want` 的 URI 解析 | 卡片/外部跳转都走 want |

### 页面（Swift → ArkTS 重写）

| 文件 | 行数 | 页面 | 重写要点 |
|---|---|---|---|
| `PoemComposerView.swift` | 4709 | 成诗（四步：心境→意境→择句→Reveal） | 最大的文件。stage 枚举 → 状态机驱动 `if/else` 切换；打字机逐字效果用 `setInterval` 或动画帧；`ImageRenderer` 分享图 → `componentSnapshot` 或离屏 Canvas |
| `PoetryDesignSystem.swift` | 4159 | 设计系统全集 | 颜色/字号/组件拆成独立文件；分享图排版引擎（纵/横排双布局）需重点重写 |
| `ClassicPoetryView.swift` | 1661 | 赏诗（每日一首/搜索/列表/阅读详情） | 120ms 防抖搜索；`ScrollViewReader` → `Scroller`；收藏存 Preferences |
| `OnboardingView.swift` | 888 | 3 页引导 | `TabView(.page)` → `Swiper`；UIKit 键盘预热可删（ArkUI 无此问题） |
| `PoetGalleryView.swift` | 628 | 诗人画廊 | `LazyVGrid` → `Grid`；会员拦截逻辑（见下文 IAP 说明） |
| `DappledShadowView.swift` | 716 | 纸面光影特效 | 见「难点 4」 |
| `SpotlightGuide.swift` | 343 | 新手聚光灯引导 | `PreferenceKey` 上报 frame → ArkUI `onAreaChange` + 全局状态 |
| `AutumnGathering.swift` | 199 | 秋日诗会活动 | 纯静态内容，简单 |
| `PoetryApp.swift` | 341 | 入口/导航/生命周期 | `scenePhase` → `Ability` 生命周期回调 |

### 数据与服务（大部分可逐行移植逻辑）

| 文件 | 职责 | 鸿蒙替代 |
|---|---|---|
| `ClassicPoem.swift` / `ClassicPoet.swift` | 模型 + 诗库索引 + 收藏 | 模型转 interface + `JSON.parse`；UserDefaults → `@ohos.data.preferences`（对象存 JSON 字符串，与现方案一致） |
| `TangShi/SongCiThreeHundredLibrary.swift` | 启动时读 JSON 建库 | `resourceManager.getRawFileContent` + 全局单例缓存 |
| `NameTransliterator.swift` | 英文名→印章汉字音译（纯算法，~400 词表 + 音节回退） | **零依赖，可直接移植** |
| `DailyPoemPicker.swift` | 每日一首（FNV-1a + xorshift64* 种子洗牌，纯算法） | **可直接移植**；`RelatedPoems` 延伸阅读索引同理 |
| `PoemMusicPlayer.swift` | 本地配乐循环播放（AVAudioPlayer，2.5s 淡入，按诗推荐曲目） | `@ohos.multimedia.media` 的 `AVPlayer`（setLooping；淡入用定时器调 setVolume） |
| `PoemLocationProvider.swift` | 定位取城市名写进落款（3km 粗精度 + 逆地理） | **Location Kit**：`getCurrentLocation` + `geoLocationManager.getAddressesFromLocation`；权限 `ohos.permission.LOCATION`；module.json5 声明 |
| `StoreManager.swift` | RevenueCat + StoreKit 2 双通道内购 | **IAP Kit**（@kit.IapKit）：AGC 配置商品， entitlement 缓存到 Preferences |
| `AppFeedback.swift` | 邮件反馈（MFMailCompose）+ App Store 评价 + 引导视频 | 邮件 → 隐式 want(mailto:) 或系统分享；评价 → 华为应用市场详情页 want；视频 → `Video` 组件循环播放 |
| `DailyPoemWidgetSync.swift` + Widget 三件套 | 桌面小组件（App Group 共享数据 + Timeline） | **FormExtension 服务卡片**：app 写 JSON/图片到沙箱共享路径，`formProvider.updateForm` 刷新；点击 → URI want 跳诗 |
| `BailianPoetryClient.swift` | ~~AI 组诗客户端~~ | **已删除**（本地工作区改动），鸿蒙版不需要 |

### 资源清单的 Info.plist 对应

- `UIAppFonts` 6 个字体 → 鸿蒙 `font.registerFont`（见难点 1）
- `NSLocationWhenInUseUsageDescription` / `NSPhotoLibraryAddUsageDescription` → module.json5 `requestPermissions` + 字符串资源
- 相册保存分享图 → `@ohos.file.photoAccessHelper` 的 `PhotoAccessHelper.showAssetsCreationDialog`
- 支持四种方向旋转 → DevEco 默认支持，按需配置

---

## 三、七大技术难点与方案

### 难点 1：自定义字体（优先级最高，全局影响）

iOS 用 Info.plist 注册 6 个字体后 `Font.custom()` 随处使用；`PoemTypeface` 枚举还带运行时探测回退（`UIFont(name:size:)` 失败退回系统字体）。

**鸿蒙方案**：
```typescript
// 应用入口（EntryAbility onCreate 或页面 aboutToAppear）统一注册
import { font } from '@kit.ArkUI';
font.registerFont({ familyName: 'kaiti', familySrc: $rawfile('fonts/HuiwenMincho.otf') });
```
- ArkTS 无法运行时探测字体是否加载成功 → 注册一次、全局保证文件名正确即可，不需要回退逻辑
- 6 个字体：汇文明朝体（kai）、文悦古体仿宋（song）、霞鹜文楷、思源宋体、马善政体（印章体）、方正小篆
- 注意：**23MB 的汇文明朝体和 16MB 文悦古体偏大**，鸿蒙对包体积敏感，建议做子集化（fonttools pyftsubset 裁到常用 3500 字，可缩到 2-4MB）

### 难点 2：竖排文字

`VerticalText`（逐字 VStack 竖排）和 `VerticalPoemComposition`（自定义 Layout 协议）。

**鸿蒙方案**：ArkUI 无竖排 Layout 协议，用 **Column 逐字堆叠**（与 iOS 同思路），列高用 `aspectRatio` 或 `ConstraintLayout` 控制；英文回退横排。分享图的竖排排版在离屏 Canvas 里用 `fillText` 逐字绘制（textAlign/textBaseline 控制）。

### 难点 3：分享图生成

iOS 用 `ImageRenderer` 离屏渲染 1080×1620 图片 + `UIActivityViewController` 分享。

**鸿蒙方案**：
- 截屏路线：组件外套层 → `componentSnapshot`（ArkUI 提供）拿到 PixelMap → 保存相册
- 绘制路线：OffscreenCanvas 手动排布（底图 drawImage + 逐字 fillText + 印章）→ PixelMap
- 保存相册：`PhotoAccessHelper`
- 系统分享：`@ohos.systemShare`

### 难点 4：纸面光影特效（DappledShadowView）

4 种纯代码绘制特效：晨光（10 条 sin/cos 摆动光带）、竹影（19 条斜纹）、斑驳（40 片漂移叶影）、宣纸（纸纤维+墨晕）。iOS 用 `TimelineView(.animation)` 逐帧驱动 + Canvas 高斯模糊。

**鸿蒙方案**：ArkUI `Canvas` 组件 + `onFrame`（每帧回调）重绘，思路完全一致。差异点：
- `context.drawLayer + addFilter(.blur)` 的高斯模糊 → 用 `OffscreenCanvas` 预渲染模糊层，或干脆把模糊光带导出成 PNG 素材叠加（性能更好、代码更少）
- 24 节气算法（Meeus/NOAA 太阳黄经 + 牛顿迭代）是**纯数学，可无损移植**

### 难点 5：简繁转换与拼音搜索

- 简繁：iOS 用 `CFStringTransform` 一行搞定 → **鸿蒙无系统 API**，需引入 OpenCC 的 ArkTS 移植或预生成对照表（诗词是固定 600 首，**建议直接预生成简繁双份数据**，运行时零成本）
- 拼音搜索索引：iOS 用 ICU `applyingTransform` 做罗马化 → 用 pinyin 库（如 js-pinyin 的 ArkTS 版）或预生成索引 JSON

### 难点 6：内购（RevenueCat → IAP Kit）

RevenueCat 无鸿蒙 SDK，需重写：
- AGC（AppGallery Connect）后台配置商品：月/年订阅 + 终身版（对应现有 entitlement "pro"）
- `@kit.IapKit`：`queryProducts` → `createPurchase` → `on('purchaseUpdated')`
- 权益本地缓存到 Preferences 作兜底；用户换机场景可考虑 AGC 云侧校验
- **如果鸿蒙版继续走完全免费策略（commit f19af14 的方向），整块可删掉**，这是最大的简化机会

### 难点 7：桌面小组件（WidgetKit → FormExtension）

- 新增 `entry/src/main/ets/widget/pages/` 卡片 UI（ArkTS 受限子集）
- 主 app 把每日诗 JSON + 降采样背景图写入沙箱 `files/`，卡片经 dataShare/共享路径读取
- 刷新：`formProvider.updateForm(formId)`
- 点击跳转：`postCardAction` 发 URI want（`shike://poem?id=xxx` → EntryAbility 解析）
- 字体：卡片资源包独立放字体子集

---

## 四、建议的重写顺序

1. **基建**（1-2 天）：DevEco 工程骨架、字体注册、颜色/字号 token、JSON 资源接入、Preferences 封装（对照 `@AppStorage` key 建常量表）
2. **赏诗 Tab**（核心阅读体验）：诗库模型 + 列表 + 阅读详情 + 配乐 → 这是 app 的根基
3. **诗人 Tab**：画廊 + 详情，复用基建
4. **成诗 Tab**（工作量最大）：四步流程 + 印章 + 分享图，分 stage 逐个攻破
5. **我的 + 引导 + 聚光灯教程**
6. **服务**：定位落款 → 小组件 → 内购（如保留）→ 反馈
7. **特效打磨**：光影 Canvas、节气弹窗

## 五、风险清单

| 风险 | 缓解 |
|---|---|
| 大包字体导致鸿蒙包体积超标（鸿蒙对 2GB 包有要求但单 hap 建议 <200MB） | 字体子集化（fonttools） |
| 逐字竖排性能（长诗 56 字 × 多列） | 分享图走 Canvas 一次性绘制，不做逐字组件 |
| 简繁/拼音无系统 API | 预生成数据，避开运行时转换 |
| 卡片与 app 的数据共享限制 | 早期验证 FormExtension 读沙箱文件链路 |
| RevenueCat 订阅迁移（iOS 付费用户跨平台权益） | 商业化决策：鸿蒙版免费 / 或自建账号体系 |
| AVPlayer 循环 + 淡入的时序差异 | 首次集成真机验证 |

---

*生成于 2026-10-01，基于 main 分支工作区代码分析。*
