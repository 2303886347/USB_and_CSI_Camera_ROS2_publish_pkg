"""Select and launch either the CSI or USB camera publisher."""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def _value(context, name):
    return LaunchConfiguration(name).perform(context)


def _launch_camera(context):
    camera_type = _value(context, "camera_type").strip().upper()
    common_parameters = {
        "image_topic": _value(context, "image_topic"),
        "frame_id": _value(context, "frame_id"),
        "frame_limit": int(_value(context, "frame_limit")),
    }

    if camera_type == "CSI":
        executable = "csi_camera_node"
        node_name = "csi_camera_publisher"
        parameters = {
            **common_parameters,
            "sensor_id": int(_value(context, "csi_sensor_id")),
            "capture_width": int(_value(context, "csi_capture_width")),
            "capture_height": int(_value(context, "csi_capture_height")),
            "output_width": int(_value(context, "csi_output_width")),
            "output_height": int(_value(context, "csi_output_height")),
            "framerate": int(_value(context, "csi_framerate")),
            "flip_method": int(_value(context, "csi_flip_method")),
        }
    elif camera_type == "USB":
        executable = "usb_camera_node"
        node_name = "usb_camera_publisher"
        parameters = {
            **common_parameters,
            "device": _value(context, "usb_device"),
            "width": int(_value(context, "usb_width")),
            "height": int(_value(context, "usb_height")),
            "framerate": int(_value(context, "usb_framerate")),
            "pixel_format": _value(context, "usb_pixel_format").upper(),
        }
    else:
        raise RuntimeError(
            f"Unsupported camera_type={camera_type!r}; use CSI or USB"
        )

    return [
        Node(
            package="camera_usb_and_csi",
            executable=executable,
            name=node_name,
            output="screen",
            emulate_tty=True,
            parameters=[parameters],
            additional_env={"PYTHONNOUSERSITE": "1"},
        )
    ]


def generate_launch_description():
    arguments = [
        DeclareLaunchArgument(
            "camera_type",
            default_value="CSI",
            description="Camera backend: CSI or USB",
        ),
        DeclareLaunchArgument("image_topic", default_value="/image_raw"),
        DeclareLaunchArgument("frame_id", default_value="camera_optical_frame"),
        DeclareLaunchArgument(
            "frame_limit",
            default_value="0",
            description="Stop after N published frames; zero runs continuously",
        ),
        DeclareLaunchArgument("csi_sensor_id", default_value="0"),
        DeclareLaunchArgument("csi_capture_width", default_value="1280"),
        DeclareLaunchArgument("csi_capture_height", default_value="720"),
        DeclareLaunchArgument("csi_output_width", default_value="640"),
        DeclareLaunchArgument("csi_output_height", default_value="480"),
        DeclareLaunchArgument("csi_framerate", default_value="60"),
        DeclareLaunchArgument("csi_flip_method", default_value="0"),
        DeclareLaunchArgument("usb_device", default_value="/dev/usb_cam"),
        DeclareLaunchArgument("usb_width", default_value="640"),
        DeclareLaunchArgument("usb_height", default_value="480"),
        DeclareLaunchArgument("usb_framerate", default_value="30"),
        DeclareLaunchArgument(
            "usb_pixel_format",
            default_value="MJPEG",
            description="USB source format: MJPEG or YUY2",
        ),
    ]
    return LaunchDescription([*arguments, OpaqueFunction(function=_launch_camera)])
