"""Select Ubuntu's GStreamer-enabled OpenCV instead of a user pip build."""

import os
import site
import sys


def prefer_system_packages():
    os.environ["PYTHONNOUSERSITE"] = "1"
    user_sites = site.getusersitepackages()
    if isinstance(user_sites, str):
        user_sites = [user_sites]

    normalized_user_sites = {
        os.path.realpath(path) for path in user_sites if path
    }
    sys.path[:] = [
        path
        for path in sys.path
        if not path
        or os.path.realpath(path) not in normalized_user_sites
    ]


def opencv_has_gstreamer(cv2_module):
    return any(
        "GStreamer:" in line and "YES" in line
        for line in cv2_module.getBuildInformation().splitlines()
    )
