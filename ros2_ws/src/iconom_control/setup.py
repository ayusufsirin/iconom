from setuptools import setup

package_name = "iconom_control"

setup(
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
    description="Minimal ROS 2 vehicle command publisher for the iconom control slice.",
    license="MIT",
    entry_points={
        "console_scripts": [
            "vehicle_command_client = iconom_control.vehicle_command_client:main",
            "vehicle_status_waiter = iconom_control.vehicle_status_waiter:main",
            "offboard_hold_publisher = iconom_control.offboard_hold_publisher:main",
        ],
    },
)
