### 开启CSI接口并使用GStreamer预览

重新接通电源并启动系统后，执行以下命令打开 Jetson-IO 配置工具：(如果无法正常打开则跳转到最后)

```bash
sudo /opt/nvidia/jetson-io/jetson-io.py
```

进入配置工具后，依次选择以下选项：

1. `Configure Jetson 24pin CSI Connector`
2. `Configure for compatible hardware`
3. `Camera IMX219-A`
4. `Save pin changes`
5. `Save and reboot to reconfigure pins`

系统重启后，查看视频设备：

```bash
ls -l /dev/video*
```

安装 Jetson 的 GStreamer NVIDIA 插件：

```bash
sudo apt update
sudo apt install -y nvidia-l4t-gstreamer
```

安装完成后，检查 `nvargus` 摄像头插件：

```bash
find /usr/lib -name "*nvargus*"
```

正常情况下，输出中应包含以下文件：

```text
/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstnvarguscamera.so
```

执行以下命令预览 CSI 摄像头画面：

```bash
gst-launch-1.0 \
  nvarguscamerasrc sensor-id=0 \
  ! "video/x-raw(memory:NVMM),width=1280,height=720,framerate=60/1" \
  ! queue \
  ! nvvidconv \
  ! queue \
  ! xvimagesink
```

画面能够正常显示时，按 `Ctrl+C` 退出预览。此处只用于确认 CSI 硬件、接口配置和 GStreamer 插件可用；



Jetson-IO 配置工具无法打开时，根据不同的主控利用ai agent去获取主控信息并且修改jetson_io_dtb_fix.sh的内容来修复DTB（）：

1. 在 Lite 主控终端中确认当前用户主目录，然后执行脚本。
2. 在 Lite 主控终端中执行：

```bash
cd ~
chmod +x jetson_io_dtb_fix.sh
sudo bash ./jetson_io_dtb_fix.sh fix-jetson-io
```

4. 修复完成后执行验证命令：

```bash
sudo bash ./jetson_io_dtb_fix.sh verify-jetson-io
```

出现以下提示，并且能够正常列出 Jetson-IO 支持的引脚功能，表示 Lite 载板 DTB 适配完成：

```text
[INFO] Exactly one Jetson-IO DTB match was found.
```

5. 执行以下命令打开 Jetson-IO：

```bash
cd /opt/nvidia/jetson-io
sudo -E env TERM="$TERM" python3 jetson-io.py
```

在 Jetson-IO 中完成引脚功能配置并保存。工具提示需要重启时，执行：

```bash
sudo reboot
```

### 
