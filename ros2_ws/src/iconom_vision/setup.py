from setuptools import setup

package_name = "iconom_vision"

_ = setup(
    name=package_name,
    version="0.1.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="iconom",
    maintainer_email="devnull@example.com",
    description="Minimal ROS 2 image subscriber for the iconom camera slice.",
    license="MIT",
    entry_points={
        "console_scripts": [
            "image_subscriber = iconom_vision.image_subscriber:main",
            "camera_symbology_overlay = iconom_vision.camera_symbology_overlay:main",
            "aircraft_detector = iconom_vision.aircraft_detector:main",
            "gazebo_pose_publisher = iconom_vision.gazebo_pose_publisher:main",
            "world_state_bridge = iconom_vision.world_state_bridge:main",
            "pose_array_extractor = iconom_vision.pose_array_extractor:main",
        ],
    },
)
