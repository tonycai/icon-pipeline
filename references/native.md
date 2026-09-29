# iOS / Android 原生图标接入参考

## 生成物

### iOS（`IOS_ICONSET_DIR`，未设置时写入 `icons/native/ios/AppIcon.appiconset/`）

| 文件 | 说明 |
|---|---|
| `AppIcon.png` | 1024，不透明 RGB（无 alpha 通道，否则 App Store 校验会拒绝），图形按 `APPLE_SCALE` 放在 `BG_COLOR` 上 |
| `AppIcon-Dark.png` | 深色外观：`source-dark.svg`（缺省用 source.svg）放在 `IOS_DARK_BG` 上 |
| `AppIcon-Tinted.png` | 染色外观：黑底白色剪影，来自 `source-mono.svg` 或 source.svg 的轮廓；系统按亮度染色 |
| `Contents.json` | 单尺寸（Single Size）格式；`IOS_APPEARANCES=0` 时只保留 Any |

要求与注意：

- 单尺寸加 Dark/Tinted 需要 Xcode 16+。更早的 Xcode 请设 `IOS_APPEARANCES=0`。
- 如果旧图标集是多尺寸布局，首次构建时整套旧文件会被移到 `.icon-build/backup/<时间>/`，避免 Xcode 报 "unassigned children"。
- iOS 26 会给资源目录里的图标自动加 Liquid Glass 效果，本流水线的输出可直接使用。
- 想用 Icon Composer 制作分层的 `.icon` 需要在 macOS 上手工完成，不在本流水线范围内；两者可以共存，由 Xcode target 的 App Icon 设置决定用哪个。
- 确认 target → General → App Icon 设为 `AppIcon`，并且 Info.plist 里没有手写的图标条目。

### Android（`ANDROID_RES_DIR`，未设置时写入 `icons/native/android/res/`）

```
mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/
  ic_launcher.png               48dp 传统方形（API < 26）
  ic_launcher_round.png         48dp 传统圆形
  ic_launcher_foreground.png    108dp 自适应前景
  ic_launcher_monochrome.png    108dp 主题图标层（Android 13+）
drawable-{…}/ic_stat_notification.png   24dp 白色剪影通知图标
mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_round.xml
values/ic_launcher_background.xml       背景色 = BG_COLOR
```

另有暂存输出，始终写入 `icons/native/android/`：

| 文件 | 用途 |
|---|---|
| `play-store-512.png` | 512，32 位 PNG，上传 Play Console（Google 会自动加圆角和阴影） |
| `adaptive-foreground-1024.png` / `adaptive-monochrome-1024.png` | 给 Expo 使用的 1024 图层 |

要求与注意：

- 构建会检查 `values*/` 下是否有重复的 `ic_launcher_background` 定义（例如 flutter_launcher_icons 生成的 colors.xml），发现就警告。必须删掉重复项，否则 Gradle 构建失败。
- `<monochrome>` 需要 compileSdk ≥ 33。更低的版本请设 `ANDROID_MONOCHROME=0`。
- 前景大小由 `ANDROID_FG_SCALE` 控制（108dp 画布上的比例），安全区直径为 66dp（约 0.61）。在预览图里确认圆形遮罩下图形没被裁切。
- 工程里原有的 `drawable/ic_launcher_foreground.xml`（矢量前景）不会被删除，但我们的 XML 引用的是 `@mipmap/…`，它从此不再使用，可以告诉用户清理掉。

## 各框架检查清单

### Capacitor

- iOS：`ios/App/App/Assets.xcassets/AppIcon.appiconset`
- Android：`android/app/src/main/res`
- 不要再运行 `@capacitor/assets`，它会覆盖本流水线的输出。
- 修改后运行 `npx cap sync`。

### React Native（bare）

- iOS：`ios/<AppName>/Images.xcassets/AppIcon.appiconset`
- Android：`android/app/src/main/res`
- 检查 `AndroidManifest.xml` 中有 `android:icon="@mipmap/ic_launcher"` 和 `android:roundIcon="@mipmap/ic_launcher_round"`。

### Flutter

- iOS：`ios/Runner/Assets.xcassets/AppIcon.appiconset`
- Android：`android/app/src/main/res`
- Web：`OUT=web`、`MANIFEST=manifest.json`（init 会自动识别）。
- 如果项目用过 flutter_launcher_icons，把它从 `pubspec.yaml` 中移除，避免两套工具互相覆盖；同时留意重复颜色资源的警告。

### Tauri v2

- iOS：`src-tauri/gen/apple/Assets.xcassets/AppIcon.appiconset`
- Android：`src-tauri/gen/android/app/src/main/res`
- 之后再运行 `tauri icon` 会覆盖移动端图标。需要桌面图标时，只对桌面部分使用 `tauri icon`，或在本流水线扩展桌面 target 后统一管理。

### Expo（managed，无原生目录）

输出都在暂存区 `icons/native/`，在 `app.json` 中引用：

```json
{
  "expo": {
    "icon": "./icons/native/ios/AppIcon.appiconset/AppIcon.png",
    "android": {
      "adaptiveIcon": {
        "foregroundImage": "./icons/native/android/adaptive-foreground-1024.png",
        "monochromeImage": "./icons/native/android/adaptive-monochrome-1024.png",
        "backgroundColor": "<BG_COLOR>"
      }
    },
    "plugins": [
      ["expo-notifications", { "icon": "./icons/native/android/res/drawable-xxxhdpi/ic_stat_notification.png" }]
    ]
  }
}
```

较新的 Expo SDK 中，`ios.icon` 也可以写成 `{ "light", "dark", "tinted" }` 对象，分别指向三张 AppIcon 图。具体写法以项目所用 SDK 版本的文档为准。之后运行 `npx expo prebuild --clean` 或重新构建 dev client。

### 原生 Xcode / Android Studio 工程

- 手动设置 `IOS_ICONSET_DIR` 和 `ANDROID_RES_DIR` 即可，其余同上。

## 通知图标接线（Android）

- **FCM**：在 `AndroidManifest.xml` 的 `<application>` 中加入

  ```xml
  <meta-data android:name="com.google.firebase.messaging.default_notification_icon"
             android:resource="@drawable/ic_stat_notification" />
  ```

- **自己发本地通知**：`setSmallIcon(R.drawable.ic_stat_notification)`。
- 通知图标只使用 alpha 通道，彩色部分会变成纯白。所以剪影必须只靠形状就能辨认。
