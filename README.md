# bluetooth-sendto-workaround
为 Windows“右键 → 发送到 → 蓝牙设备”失效提供替代入口，通过操作内置 fsquirt 向导，自动填入选中的文件。

适用于：**手动打开蓝牙文件传送向导、选择文件可以正常发送，但右键“发送到”没有反应。

**不适用于：**无法配对、找不到设备、手动发送也失败等蓝牙连接问题。

本工具不修复蓝牙驱动或原生 COM 注册，只添加一个替代的“发送到”入口。

## 使用方式

**安装（推荐直接双击 .bat）**

```text
Install-BtSend.bat              # 默认安装
Install-BtSend.bat -AutoNext    # 安装并开启自动点"下一步"
```

**卸载**

```text
Uninstall-BtSend.bat
```

**PowerShell 内联调用**

```powershell
# 若执行策略禁止，用 -ExecutionPolicy Bypass 启动一次
powershell -ExecutionPolicy Bypass -File .\Install-BtSend.ps1

# 之后可随时用 -Uninstall 清理
.\Install-BtSend.ps1 -Uninstall
```
