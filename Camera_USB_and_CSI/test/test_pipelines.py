import pytest

from camera_usb_and_csi.pipelines import build_csi_pipeline, build_usb_pipeline


def test_csi_pipeline_contains_requested_mode():
    pipeline = build_csi_pipeline(0, 1280, 720, 640, 480, 60, 2)
    assert "nvarguscamerasrc sensor-id=0" in pipeline
    assert "width=(int)1280" in pipeline
    assert "height=(int)720" in pipeline
    assert "framerate=(fraction)60/1" in pipeline
    assert "flip-method=2" in pipeline


def test_usb_mjpeg_pipeline_uses_jpeg_decoder():
    pipeline = build_usb_pipeline("/dev/usb_cam", 1280, 720, 30, "MJPEG")
    assert 'v4l2src device="/dev/usb_cam"' in pipeline
    assert "image/jpeg" in pipeline
    assert "jpegdec" in pipeline


def test_usb_yuy2_pipeline_is_raw():
    pipeline = build_usb_pipeline("/dev/video1", 640, 480, 30, "YUY2")
    assert "format=(string)YUY2" in pipeline
    assert "jpegdec" not in pipeline


def test_usb_pipeline_rejects_unknown_format():
    with pytest.raises(ValueError, match="MJPEG or YUY2"):
        build_usb_pipeline("/dev/video1", 640, 480, 30, "H264")
