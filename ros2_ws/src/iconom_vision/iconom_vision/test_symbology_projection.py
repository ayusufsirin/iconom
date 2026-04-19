#!/usr/bin/env python3
"""Unit tests for camera symbology projection math."""
import pytest


def project_3d_to_2d(dx, dy, dz, fx, fy, cx, cy):
    if dz <= 0.1:
        return None
    u = fx * dx / dz + cx
    v = fy * dy / dz + cy
    return (u, v)


class TestProjectionCenter:
    def test_projection_center(self):
        result = project_3d_to_2d(dx=10, dy=0, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result == (1320, 240)


class TestProjectionOffset:
    def test_projection_offset_right(self):
        result = project_3d_to_2d(dx=10, dy=10, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result == (1320, 1240)

    def test_projection_offset_left(self):
        result = project_3d_to_2d(dx=10, dy=-10, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result == (1320, -760)


class TestProjectionBehind:
    def test_projection_behind(self):
        result = project_3d_to_2d(dx=-5, dy=0, dz=-5, fx=500, fy=500, cx=320, cy=240)
        assert result is None

    def test_projection_exactly_behind(self):
        result = project_3d_to_2d(dx=0, dy=0, dz=0, fx=500, fy=500, cx=320, cy=240)
        assert result is None


class TestProjectionTooClose:
    def test_projection_too_close(self):
        result = project_3d_to_2d(dx=1, dy=0, dz=0.05, fx=500, fy=500, cx=320, cy=240)
        assert result is None

    def test_projection_at_threshold(self):
        result = project_3d_to_2d(dx=1, dy=0, dz=0.1, fx=500, fy=500, cx=320, cy=240)
        assert result is None

    def test_projection_just_above_threshold(self):
        result = project_3d_to_2d(dx=1, dy=0, dz=0.11, fx=500, fy=500, cx=320, cy=240)
        assert result is not None


class TestProjectionOutsideFrame:
    def test_projection_outside_right(self):
        result = project_3d_to_2d(dx=1000, dy=0, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result[0] == 100320

    def test_projection_outside_left(self):
        result = project_3d_to_2d(dx=-1000, dy=0, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result[0] == -99680


class TestDifferentCameraParams:
    def test_1280x720_camera(self):
        result = project_3d_to_2d(dx=10, dy=0, dz=5, fx=640, fy=640, cx=640, cy=360)
        assert result == (1920, 360)

    def test_square_pixels(self):
        result = project_3d_to_2d(dx=5, dy=5, dz=5, fx=400, fy=400, cx=320, cy=240)
        assert result == (720, 640)


class TestEdgeCases:
    def test_projection_zero_dx(self):
        result = project_3d_to_2d(dx=0, dy=10, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result == (320, 1240)

    def test_projection_zero_dy(self):
        result = project_3d_to_2d(dx=10, dy=0, dz=5, fx=500, fy=500, cx=320, cy=240)
        assert result == (1320, 240)

    def test_projection_negative_dz_small(self):
        result = project_3d_to_2d(dx=10, dy=0, dz=-0.01, fx=500, fy=500, cx=320, cy=240)
        assert result is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])