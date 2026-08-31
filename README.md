# PanPal

纯前端多网盘管理工具，无后端服务器。

## 功能特性

- 支持百度网盘、阿里云盘、123云盘、夸克网盘、天翼云盘、蓝奏云、和彩云等
- WebView 电脑 UA 登录，凭证加密本地存储
- 文件管理：浏览、搜索、排序、多选、删除、新建文件夹
- 文件上传：选择本地文件上传到网盘
- 内置 Gopeed 多连接下载器：默认 16 连接，最高 64 连接
- 官方分享链接生成，支持提取码和有效期
- 下载管理：进度、速度、暂停/继续/取消
- 主题切换：浅色/深色/跟随系统
- Material 3 设计

## 技术栈

- Flutter + Material 3
- 纯前端，无后端
- AES 加密凭证存储
- HTTP Range 多连接下载
- GitHub Actions 云端构建

## 构建

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## 架构

```
lib/
├── main.dart              # 入口
├── app.dart               # 应用根组件
├── theme/                 # 主题
├── models/                # 数据模型
├── providers/             # 网盘 API 封装
├── services/              # 服务层（凭证、下载、上传）
├── screens/               # 页面
└── widgets/               # 组件
```
