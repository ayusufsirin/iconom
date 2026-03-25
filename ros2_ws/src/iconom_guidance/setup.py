from setuptools import setup

package_name = "iconom_guidance"

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
    description="Deterministic pursuit-guidance building blocks for phase 6.",
    license="MIT",
    entry_points={
        "console_scripts": [
            "target_selector = iconom_guidance.target_selector:main",
            "intercept_planner = iconom_guidance.intercept_planner:main",
            "pursuit_state_machine = iconom_guidance.pursuit_state_machine:main",
            "scripted_rival_publisher = iconom_guidance.scripted_rival_publisher:main",
            "camera_cueing_bridge = iconom_guidance.camera_cueing_bridge:main",
        ],
    },
)
