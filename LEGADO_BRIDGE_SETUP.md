# 📚 KOReader - Legado书源桥接插件

## 🎯 项目概述

这是一个KOReader插件，通过API与[Legado阅读](https://github.com/gedoor/legado)应用集成，为KOReader提供强大的在线书源功能。

### ✨ 主要功能

- 🔍 **智能搜索** - 支持跨多个书源搜索书籍
- 📖 **在线阅读** - 直接在KOReader中阅读在线小说  
- 📋 **章节管理** - 完整的章节列表和导航
- 💾 **智能缓存** - 减少网络请求，提升阅读体验
- ⚙️ **灵活配置** - 可自定义服务地址和参数

## 🛠️ 安装配置

### 前置要求

1. **KOReader** - 版本 2021.03+ 
2. **Legado阅读APP** - 安装在Android设备上
3. **网络连接** - KOReader与Legado在同一网络环境

### 第一步: 配置Legado Web服务

1. 打开Legado阅读APP
2. 进入 `设置` → `Web服务`
3. 启用 `Web服务` 开关
4. 设置端口为 `1122` (默认)
5. 记录显示的IP地址 (如: `192.168.1.100`)

![Legado Web服务设置](https://raw.githubusercontent.com/gedoor/legado/master/app/src/main/assets/web/legado.png)

### 第二步: 安装KOReader插件

1. 将插件文件复制到KOReader插件目录:
   ```bash
   # Android
   /sdcard/koreader/plugins/legado_bridge.koplugin/
   
   # Linux  
   ~/.config/koreader/plugins/legado_bridge.koplugin/
   
   # Windows
   %APPDATA%/KOReader/plugins/legado_bridge.koplugin/
   ```

2. 重启KOReader应用

### 第三步: 配置插件

1. 在KOReader主菜单中找到 `📚 在线书源`
2. 点击 `⚙️ 设置`
3. 配置Legado服务地址 (如: `192.168.1.100:1122`)
4. 点击 `📊 状态检查` 验证连接

## 🚀 使用方法

### 搜索书籍

1. 点击 `📚 在线书源` → `🔍 搜索书籍`
2. 输入书名或作者名
3. 从搜索结果中选择目标书籍
4. 查看书籍详情和章节列表

### 在线阅读

1. 在章节列表中点击任意章节
2. 插件会自动获取章节内容
3. 在KOReader中打开阅读界面
4. 享受完整的阅读体验

### 缓存管理

- 搜索结果缓存30分钟
- 章节内容缓存1小时  
- 可手动清理缓存释放空间

## 🧪 测试验证

运行测试脚本验证功能:

```bash
lua test_legado_bridge.lua
```

### 测试输出示例:
```
🚀 开始Legado桥接插件测试
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧪 测试1: 检查Legado服务连接
✅ Legado服务连接正常

🧪 测试2: 搜索书籍功能  
✅ 搜索成功，找到 15 本书
   📖 1. 斗破苍穹 - 天蚕土豆 (起点中文网)
   📖 2. 斗破苍穹 - 天蚕土豆 (笔趣阁)
   📖 3. 斗破苍穹 - 天蚕土豆 (顶点小说)

🧪 测试3: 获取章节列表
✅ 获取章节列表成功，共 1648 章
   📄 1. 第一章 陨落的天才
   📄 2. 第二章 萧薰儿
   📄 3. 第三章 斗之气，三段！

🧪 测试4: 获取章节内容
✅ 获取章节内容成功
   📝 内容预览: "斗气大陆，没有魔法，没有斗气，有的，仅仅是繁衍到巅峰的斗气！..."

🎉 所有测试通过！Legado桥接功能正常工作
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 🔧 故障排除

### 常见问题

#### 1. 连接失败
```
❌ Legado服务连接失败
错误信息: 网络请求失败: Connection refused
```

**解决方案:**
- 确保Legado APP的Web服务已启用
- 检查IP地址和端口是否正确
- 确保设备在同一网络环境
- 检查防火墙设置

#### 2. 搜索无结果
```
❌ 没有找到相关书籍
```

**解决方案:**
- 确保Legado中已导入书源
- 尝试更换搜索关键词
- 检查书源是否正常可用
- 查看Legado日志确认书源状态

#### 3. 章节获取失败
```
❌ 获取章节内容失败: HTTP错误: 500
```

**解决方案:**
- 检查网络连接稳定性
- 尝试其他书源的相同小说
- 等待一段时间后重试
- 清理缓存后重新尝试

### 调试模式

启用详细日志记录:

```lua
-- 在插件配置中启用调试模式
CONFIG.debug_mode = true
```

查看KOReader日志:
```bash
# Android
adb logcat | grep KOReader

# Linux
journalctl -f | grep koreader
```

## 📊 性能优化

### 网络配置

```lua
-- 调整请求参数
CONFIG.api.timeout = 60        -- 增加超时时间
CONFIG.request_delay = 500     -- 减少请求间隔
CONFIG.max_search_results = 50 -- 增加搜索结果数量
```

### 缓存策略

```lua
-- 自定义缓存时间
self.cache:set(cache_key, data, 7200) -- 2小时缓存
```

## 🛡️ 安全注意事项

1. **网络安全**: 确保在受信任的网络环境中使用
2. **数据隐私**: 搜索记录和阅读历史仅存储在本地
3. **版权合规**: 仅用于合法获取的内容，遵守相关法律法规
4. **服务稳定**: 避免频繁请求，防止对书源网站造成压力

## 🔄 更新升级

### 检查更新
定期检查插件更新，获取最新功能和Bug修复。

### 备份配置
升级前备份个人配置:
```bash
cp -r ~/.config/koreader/plugins/legado_bridge.koplugin/legado_cache ~/.backup/
```

## 🤝 贡献指南

欢迎提交Issue和Pull Request:

1. **Bug报告**: 详细描述复现步骤
2. **功能建议**: 说明使用场景和预期效果  
3. **代码贡献**: 遵循项目代码风格
4. **文档改进**: 帮助完善使用说明

## 📄 许可证

本项目采用 GPL-3.0 许可证，与KOReader和Legado保持一致。

## 🙏 致谢

感谢以下开源项目:

- [KOReader](https://github.com/koreader/koreader) - 优秀的跨平台阅读器
- [Legado](https://github.com/gedoor/legado) - 强大的自定义书源阅读器
- Lua生态系统的所有贡献者

---

📧 如有问题，请通过GitHub Issues联系我们。

💖 如果这个插件对你有帮助，请给项目点个Star支持！ 