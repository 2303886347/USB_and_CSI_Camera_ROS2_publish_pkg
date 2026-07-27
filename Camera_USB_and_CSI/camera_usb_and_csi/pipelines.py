"""GStreamer pipeline builders for the supported camera backends."""


def _positive_int(name, value):
    value = int(value)
    if value <= 0:
        raise ValueError(f"{name} must be greater than zero")
    return value


def build_csi_pipeline(
    sensor_id,
    capture_width,
    capture_height,
    output_width,
    output_height,
    framerate,
    flip_method,
):
    sensor_id = int(sensor_id)
    capture_width = _positive_int("capture_width", capture_width)
    capture_height = _positive_int("capture_height", capture_height)
    output_width = _positive_int("output_width", output_width)
    output_height = _positive_int("output_height", output_height)
    framerate = _positive_int("framerate", framerate)
    flip_method = int(flip_method)
    if sensor_id < 0:
        raise ValueError("sensor_id must be zero or greater")
    if flip_method not in range(8):
        raise ValueError("flip_method must be between 0 and 7")

    return (
        f"nvarguscamerasrc sensor-id={sensor_id} ! "
        "video/x-raw(memory:NVMM),"
        f"width=(int){capture_width},"
        f"height=(int){capture_height},"
        "format=(string)NV12,"
        f"framerate=(fraction){framerate}/1 ! "
        "queue max-size-buffers=1 leaky=downstream ! "
        f"nvvidconv flip-method={flip_method} ! "
        "video/x-raw,"
        f"width=(int){output_width},"
        f"height=(int){output_height},"
        "format=(string)BGRx ! "
        "videoconvert ! "
        "video/x-raw,format=(string)BGR ! "
        "appsink drop=true max-buffers=1 sync=false"
    )


def build_usb_pipeline(device, width, height, framerate, pixel_format):
    if not isinstance(device, str) or not device.startswith("/dev/"):
        raise ValueError("device must be an absolute path below /dev")
    escaped_device = device.replace("\\", "\\\\").replace('"', '\\"')
    width = _positive_int("width", width)
    height = _positive_int("height", height)
    framerate = _positive_int("framerate", framerate)
    pixel_format = str(pixel_format).strip().upper()

    if pixel_format in ("MJPEG", "MJPG"):
        source_caps = (
            "image/jpeg,"
            f"width=(int){width},"
            f"height=(int){height},"
            f"framerate=(fraction){framerate}/1"
        )
        decoder = "jpegdec ! "
    elif pixel_format == "YUY2":
        source_caps = (
            "video/x-raw,format=(string)YUY2,"
            f"width=(int){width},"
            f"height=(int){height},"
            f"framerate=(fraction){framerate}/1"
        )
        decoder = ""
    else:
        raise ValueError("pixel_format must be MJPEG or YUY2")

    return (
        f'v4l2src device="{escaped_device}" io-mode=2 ! '
        f"{source_caps} ! "
        "queue max-size-buffers=1 leaky=downstream ! "
        f"{decoder}"
        "videoconvert ! "
        "video/x-raw,format=(string)BGR ! "
        "appsink drop=true max-buffers=1 sync=false"
    )
