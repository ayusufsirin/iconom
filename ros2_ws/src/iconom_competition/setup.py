from setuptools import setup

package_name = "iconom_competition"

setup(
    name=package_name,
    version="0.1.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
    ],
    install_requires=["setuptools", "requests"],
    zip_safe=True,
    maintainer="iconom",
    maintainer_email="devnull@example.com",
    description="ROS 2 competition client for connecting to the mock referee server.",
    license="MIT",
    entry_points={
        "console_scripts": [
            "competition_client = iconom_competition.competition_client:main",
            "ownship_telemetry_adapter = iconom_competition.ownship_telemetry_adapter:main",
            "rival_buffer = iconom_competition.rival_buffer:main",
            "predictor = iconom_competition.predictor:main",
            "live_rival_state_adapter = iconom_competition.live_rival_state_adapter:main",
        ],
    },
)
