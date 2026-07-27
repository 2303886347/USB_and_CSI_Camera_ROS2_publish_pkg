# Jetson-IO DTB 适配

当前脚本适用环境：Jetson Orin Nano Super、JetPack 6.2、L4T R36.4.3。

## 1. 准备脚本

将 `jetson_io_dtb_fix.sh` 上传到 Jetson 的用户主目录，然后执行：

```bash
cd ~
chmod +x jetson_io_dtb_fix.sh
```

## 2. 检查 DTB 状态

```bash
sudo bash ./jetson_io_dtb_fix.sh status
```

修复前出现以下提示属于正常现象：

```text
No matching DTB found in /boot/dtb
```

## 3. 修复 Jetson-IO

```bash
sudo bash ./jetson_io_dtb_fix.sh fix-jetson-io
```

脚本会自动选择与当前设备匹配的 DTB，安装到 `/boot/dtb`，并运行 Jetson-IO 功能列表检查。

出现以下提示表示修复成功：

```text
[INFO] Exactly one Jetson-IO DTB match was found.
[INFO] Jetson-IO DTB discovery is working. No reboot was required for this repair.
```

## 4. 验证修复结果

```bash
sudo bash ./jetson_io_dtb_fix.sh verify-jetson-io
```

命令能够正常列出 Jetson-IO 支持的引脚功能，并且不再出现 `No DTB found`，说明 DTB 适配完成。

## 5. 打开 Jetson-IO

```bash
cd /opt/nvidia/jetson-io
sudo -E env TERM="$TERM" python3 jetson-io.py
```

在 Jetson-IO 中完成配置并保存。工具提示重启后，执行：

```bash
sudo reboot
```

## 6. 恢复修复前状态

需要撤销本次 DTB 修复时执行：

```bash
cd ~
sudo bash ./jetson_io_dtb_fix.sh restore-jetson-io
```
