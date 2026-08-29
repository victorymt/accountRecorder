# 账号本子

一个面向 Android 的本地密码与动态验证码管理器。账号数据保存在应用自己的私有目录中，应用之外的普通软件无法直接读取。

## 功能

- 主密码解锁，并支持后台自动锁定
- 指纹解锁（使用设备系统生物识别能力）
- 账号增删改查、收藏和标签筛选
- 密码强度评估与安全审计
- 安全密码生成器，支持长度、字符集和易混淆字符设置
- TOTP 动态验证码：手动录入或扫描二维码，支持常见算法、位数和周期配置
- 敏感内容复制后自动清理剪贴板
- 从“账号盒子”格式导入账号
- 加密备份与恢复
- 加密回收站：删除后可恢复、永久删除或清空，删除超过 30 天自动清理

## 数据安全

- 密码、用户名、备注、标签、TOTP 配置和回收站状态都写入加密 payload。
- 密钥由主密码派生；密码库使用 AES-256-GCM 加密并带完整性校验。
- 生物识别只用于保护设备上的 Vault Key，不会替代主密码，也不会把主密码写入本地。
- 备份文件使用独立密码、随机盐和 AES-256-GCM 加密。忘记备份密码时无法恢复备份内容。
- 应用关闭或后台锁定时会关闭数据库连接并清理内存中的敏感密钥。

## 回收站规则

普通删除会将账号标记为已删除并移入回收站，因此不会出现在账号列表、搜索、动态密码或安全审计中。回收站入口位于首页工具菜单。

回收站中的账号可以恢复，也可以永久删除。永久删除操作只对已在回收站中的账号开放；进入回收站超过 30 天的账号会在数据库打开时自动清理。加密备份会同时保存活动账号和回收站账号，恢复时保留其删除状态。

## 开发环境

- Flutter SDK（项目当前 Dart SDK 约束为 `^3.12.2`）
- Android SDK 与可用的 Android 设备或模拟器

安装依赖并运行开发版本：

```bash
flutter pub get
flutter run
```

构建 Android Release APK（需要先配置正式签名，见下方“自动发布”）：

```bash
flutter build apk --release
```

APK 输出路径为 `build/app/outputs/flutter-apk/app-release.apk`。

## 自动发布 Android Release

项目使用 GitHub Actions 自动构建并发布 APK。发布流程会固定使用 Flutter 3.44.8、Java 17，先执行 `flutter analyze` 和 `flutter test`，再构建正式签名的 APK。

### 首次配置签名

在安全位置生成 keystore（只需生成一次）：

```bash
keytool -genkeypair -v \
  -keystore release-key.jks \
  -alias account-book \
  -keyalg RSA -keysize 2048 -validity 10000
```

将 `release-key.jks` 转成单行 base64，并在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 中创建以下 Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `release-key.jks` 的 base64 内容 |
| `ANDROID_KEY_ALIAS` | keystore 的 alias |
| `ANDROID_KEY_PASSWORD` | alias 对应的 key 密码 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |

Linux/macOS 可使用以下命令生成 base64 内容：

```bash
base64 < release-key.jks | tr -d '\n'
```

不要把 keystore、`android/key.properties` 或密码提交到仓库。需要在本地构建 release 时，可在 `android/key.properties` 写入：

```properties
storeFile=release-key.jks
storePassword=...
keyAlias=account-book
keyPassword=...
```

并将 keystore 放在 `android/release-key.jks`。缺少这些配置时，release 构建会直接失败，不会回退到 debug 签名。

### 创建 Release

版本号来自 `vMAJOR.MINOR.PATCH` 格式的 tag。推送 tag 后会自动创建 GitHub Release 并上传 APK：

```bash
git tag v1.0.1
git push origin v1.0.1
```

也可以在 **Actions → Android Release → Run workflow** 中输入一个已经存在的版本 tag 手动发布。APK 会以 `account-book-1.0.1.apk` 的形式出现在对应 Release 的附件中。

## 测试与检查

```bash
flutter analyze
flutter test
```

测试覆盖密码库迁移、主密码与 Vault Key 解锁、加密备份、账号导入、TOTP、密码安全审计及回收站生命周期。

## 权限说明

- `USE_BIOMETRIC` / `USE_FINGERPRINT`：启用指纹解锁。
- `CAMERA`：扫描 TOTP 二维码；不扫描时不会使用摄像头。

本项目默认不配置云同步服务，备份文件由用户自行保管。
