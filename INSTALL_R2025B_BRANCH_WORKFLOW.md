# MATLAB R2025b + Git 分支安装流程

推荐基线分支：`feature/voice-conversion-core`
推荐升级分支：`feature/am-dashboard-realtime`

## 1. 在现有仓库根目录检查状态

```bash
git status
```

应先确认当前没有未提交的重要修改。

## 2. 回到已推送的声线转换基线并同步

```bash
git switch feature/voice-conversion-core
git pull --ff-only
```

## 3. 从该基线创建升级分支

```bash
git switch -c feature/am-dashboard-realtime
```

## 4. 应用补丁

把 `VoiceFX_AM_Dashboard_Realtime_PATCH_R2025b.zip` 解压后的**内容**复制到仓库根目录。允许 Windows 对同名文件执行“替换/覆盖”。

这一步只改变当前升级分支的工作区内容。已经提交并推送的 `feature/voice-conversion-core` 历史不会丢失。

## 5. 检查 Git 变化

```bash
git status
git diff --stat
```

## 6. 在 MATLAB R2025b 中测试

从项目根目录启动：

```matlab
fig = launchVoiceFXDashboard();
```

运行聚焦回归测试：

```matlab
addpath(genpath(pwd));
run('tests/run_am_dashboard_upgrade_suite.m');
```

## 7. 测试通过后提交并推送

```bash
git add .
git commit -m "feat: integrate AM lab dashboard and realtime engine"
git push -u origin feature/am-dashboard-realtime
```

## 回退

需要回到旧版本时：

```bash
git switch feature/voice-conversion-core
```

Git 会恢复该分支已经跟踪文件的版本。
