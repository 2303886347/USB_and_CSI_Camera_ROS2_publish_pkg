from glob import glob
import os

from setuptools import find_packages, setup


package_name = "camera_usb_and_csi"


setup(
    name=package_name,
    version="1.0.0",
    packages=find_packages(exclude=("test",)),
    data_files=[
        (
            "share/ament_index/resource_index/packages",
            ["resource/" + package_name],
        ),
        ("share/" + package_name, ["package.xml", "README.md"]),
        (
            os.path.join("share", package_name, "launch"),
            glob("launch/*.launch.py"),
        ),
        (
            os.path.join("share", package_name, "udev"),
            glob("udev/*.rules"),
        ),
        (
            os.path.join("share", package_name, "scripts"),
            glob("scripts/*.sh"),
        ),
        (
            os.path.join("share", package_name, "docs"),
            glob("docs/*.md"),
        ),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="ubuntu",
    maintainer_email="ubuntu@example.com",
    description="ROS 2 publishers for Jetson CSI and USB cameras.",
    license="Apache-2.0",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "csi_camera_node = camera_usb_and_csi.csi_camera_node:main",
            "usb_camera_node = camera_usb_and_csi.usb_camera_node:main",
        ],
    },
)
