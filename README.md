# SplitJump

拦截「跨 App 跳转」，先让你选应用，选完再继续原来的打开流程 —— 因此可以和分屏 / 浮窗类插件共存，让选中的应用按它们的规则以浮窗打开。

> 本项目是**从零实现的原创插件**，与 `com.iosdump.jumpselect`（JumpSelect）无任何关系，不包含也不依赖它的代码或二进制。

---

## 它解决什么问题

很多场景下「打开某个 App」并不唯一，例如：

- 微信支付 / 授权跳转，而你装了多个微信分身；
- 淘宝、支付宝、抖音等 App 的多开容器；
- `shortcuts://`、`webclip`、通知点击等触发的跨应用跳转。

系统只会打开「默认」那一个。SplitJump 在跳转发生的那一刻拦下请求，弹出候选列表，你选完再把这次打开**交回原调用链**继续执行。

把请求交回原链是刻意设计：分屏 / 浮窗类插件（例如 [Stheno](https://github.com/Crassna/Stheno)，闭源）本身就挂在同一条链路上，交回给它，它就会按自己的「浮窗激活」规则把目标 App 以浮窗/分屏打开。

## 功能

| 功能 | 说明 |
|---|---|
| 应用选择面板 | 玻璃卡片式列表，显示图标、名称、包名、容器标识 |
| 自定义拦截规则 | 「被拦截的目标包名 = 候选1, 候选2, …」，多行编辑 |
| 来源放行名单 | 名单内的 App 发起跳转时直接放行，不弹窗（默认放行 `com.apple.springboard`，所以桌面点图标不会被拦） |
| 触发方式 | 「弹窗选择」或「直接打开首个候选」 |
| 仅拦截带 URL 的跳转 | 打开后可避免拦掉不带 URL 的普通打开 |
| Crane 多开支持 | 自动检测 `CraneManager`，把该应用的所有容器展开进列表并可切换 |
| 双拦截点 + 提早拦截 | 见下方「实现说明」，用于和分屏类插件共存 |
| 无需注销 | 改设置后通过 Darwin 通知即时重载 |
| 调试日志 | 可选，写入 `/var/mobile/Library/Logs/SplitJump.log` |

## 环境要求

- 越狱类型：**rootless**（Dopamine 2.x / palera1n rootless / **RootHide 隐根** 等），安装到 `/var/jb`
- 系统：iOS 15.0 及以上
- 依赖：`mobilesubstrate`、`preferenceloader`（ElleKit / libhooker / substrate 都以 `mobilesubstrate` 虚拟包形式提供）
- 架构：`arm64` / `arm64e`

> **v1.0.1 依赖变更**：v1.0.0 把依赖写成 `org.coolstar.ellekit`，在隐根（RootHide）这类不以该 ID
> 提供 ElleKit 的环境会报 `Depends org.coolstar.ellekit` 而装不上。v1.0.1 改为 `mobilesubstrate`，
> 与 JumpSelect 的写法一致 —— 本插件 dylib 实际链接的也只有
> `@rpath/CydiaSubstrate.framework/CydiaSubstrate`，和 JumpSelect 完全相同，因此凡是能装
> JumpSelect / Stheno 的环境都能装本插件。

## 安装

```bash
# 1. 从 Releases 下载 deb
# 2. 用 Sileo / Zebra / Filza 安装
# 3. 注销（Respring）后生效
```

设置入口：**设置 → SplitJump**

## 配置

### 1. 写规则

设置 → SplitJump → **编辑拦截规则**，每行一条：

```
# 以 # 开头是注释
com.tencent.xin = com.tencent.xin, com.tencent.xin.clone1, com.tencent.xin.clone2
com.taobao.taobao = com.taobao.taobao
```

- 等号左边：**被拦截的目标包名**（别人想打开的那个 App）
- 等号右边：**候选列表**，会显示在面板里。通常就是目标 App 本身 + 它的各个多开分身
- 未安装的候选会被自动过滤掉
- 分隔符 `=` 和 `->` 都支持

### 2. 放行名单

「放行的发起方」默认是 `com.apple.springboard`。**保留它**，否则从桌面点图标也会弹面板。

### 3. 和分屏 / 浮窗插件共存

以 Stheno 为例：

1. 在 SplitJump 里把触发方式设为**弹窗选择**；
2. 在 Stheno 里，给目标 App 打开「**浮窗激活**」组里的 **`系统服务`**、**`SpringBoard 请求`**、**`URL`**；
3. 关闭 Stheno 的「**缩小范围**」（否则只有它「已添加」的 App 才允许浮窗激活），把目标 App 加入它的已添加列表；
4. 开启 SplitJump 设置 → 高级 → **提早拦截**；
5. 注销一次。

然后触发一次跳转：**先弹面板 → 选完 → Stheno 把该次打开转成浮窗**。

如果面板不出现，打开「写入调试日志」，用 Filza 看 `/var/mobile/Library/Logs/SplitJump.log`：

- 有 `UPSTREAM hit` / `DOWNSTREAM hit` → 拦截成功，问题在候选列表或过滤；
- 一条都没有 → 请求被上游插件吃掉了，确认「提早拦截」已开启并已注销。

## 实现说明

### 两个拦截点

```
源 App 发起跳转
   │
   ▼ SpringBoard 进程内
① -[SBMainWorkspace _activateBundleID:requestID:isTrusted:options:source:originalSource:withResult:]
        ↑ 上游：bundleID 是显式参数，换参重投即可，最可靠
② -[SBMainWorkspace systemService:handleOpenApplicationRequest:withCompletion:]
        ↑ 下游：拿到的是封装过的 request 对象，改写需要 KVC 写 bundle 标识
   │
   ▼ 场景创建 → 前台 / 浮窗显示
```

- 拦截点 ② 用 Logos `%hook` 在**加载期**安装，作为始终可用的通路；
- 拦截点 ① 用 `MSHookMessageEx` **延迟 8 秒**安装，并且只安装一次。

延迟安装的原因：substrate 系按目录枚举顺序加载 dylib，后安装者位于调用链**最外层**。只有位于最外层，才能既拦得住请求、又能在重投时把请求交回给链上的其它插件（分屏/浮窗）处理。只安装一次是为了避免「自己 → 自己」形成无限递归。

### 版本自适应

拦截点 ① 是私有 API，不同 iOS 上可能不存在或签名不同。因此：

- 安装前用 `class_getInstanceMethod` 检查，不存在就完全跳过；
- 参数按 7 个显式形参转发；
- 所有取值（request 的 `bundleIdentifier` / `_bundleIdentifier` / `dictionary` / `options` 等）都用 `NSInvocation` + `respondsToSelector` 做容错探测，取不到就安全返回，不崩溃。

### 取消跳转

取消按钮不会去调用未知签名的 completion block，而是把目标包名改成哨兵值 `com.lvxl524.splitjump.void`（系统中不存在），让这次打开以「找不到应用」自然结束 —— 不挂起调用方，也不会误开其它 App。

## 已知限制与未验证项

- 拦截点 ① 的 7 个参数顺序是依据 iOS 16/17 上实测到的类型编码 `v68@0:8@16@24B32@36@44@52@?60` 推断的。若某系统版本参数顺序不同，重投可能失败 —— 关闭「提早拦截」即可退回只用拦截点 ②。
- 「延迟 8 秒安装」假定其它插件的 hook 都在 dylib 加载期完成。若某个插件延后很久才 hook，本插件可能不在最外层。
- 未在真机上做过全量回归。请先在小范围验证常见跳转（支付、授权、快捷指令、通知点击）后再日常使用。
- Crane 的几个方法名（`containerIdentifiersOfApplicationWithIdentifier:` 等）来自对现有插件的逆向观察，不同 Crane 版本可能不一致；取不到时面板会自动退回只列应用本体，不会报错。

## 自行构建

```bash
export THEOS=/opt/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

推送到 `main` 后 GitHub Actions 会自动在 macOS runner 上构建并产出 deb 制品。CI 里额外做了一步**强制 gzip 重打包**：macOS 上 `dpkg` 默认生成 `data.tar.lzma`，而 Sileo / Zebra 不支持 lzma，会导致安装时报「无法解压」。

生成设置面板图标：

```bash
python3 gen_icons.py
```

## 目录结构

```
SplitJump/
├── Tweak.xm                     # 两个拦截点 + 决策 + 重投
├── SplitJump.plist              # 注入进程：com.apple.springboard
├── Sources/
│   ├── SJCompat.[hm]            # NSInvocation 运行时桥接 + 日志
│   ├── SJRules.[hm]             # 偏好与规则解析
│   ├── SJAppList.[hm]           # 应用枚举 + Crane 容器
│   └── SJPicker.[hm]            # 选择面板 UI
├── SplitJumpPrefs/              # 设置面板子工程（PreferenceLoader）
├── layout/DEBIAN/               # control / postinst / prerm
├── gen_icons.py
└── .github/workflows/build.yml  # macOS CI
```

## 许可

MIT，见 [LICENSE](LICENSE)。
