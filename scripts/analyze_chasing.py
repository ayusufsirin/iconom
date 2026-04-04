#!/usr/bin/env python3
"""
Autonomous Chasing Analysis Report
Generates a comprehensive visual report for live rival geometry data.
"""

import pandas as pd
import numpy as np

FILE_PATH = '/home/joseph/Projects/iconom/ros2_ws/.tmp-phase6-live-rival-geometry.csv'
OUTPUT_FILE = '/home/joseph/Projects/iconom/ros2_ws/chasing_report.txt'

COLORS = {
    'HEADER': '\033[95m',
    'OKBLUE': '\033[94m',
    'OKCYAN': '\033[96m',
    'OKGREEN': '\033[92m',
    'WARNING': '\033[93m',
    'FAIL': '\033[91m',
    'BOLD': '\033[1m',
    'ENDC': '\033[0m',
}

def color(text, c):
    return f"{c}{text}{COLORS['ENDC']}"

def box_print(title, lines, width=60):
    print()
    print("┌" + "─" * (width - 2) + "┐")
    title_pad = (width - 2 - len(title)) // 2
    print("│" + " " * title_pad + title + " " * (width - 2 - title_pad - len(title)) + "│")
    print("├" + "─" * (width - 2) + "┤")
    for line in lines:
        print(f"│ {line:<{width-2}} │")
    print("└" + "─" * (width - 2) + "┘")

def stat_line(label, value, unit="", highlight=False):
    value_str = f"{value:.2f}{unit}"
    if highlight:
        return f"{label:<25} {color(value_str, COLORS['OKGREEN'])}"
    return f"{label:<25} {value_str}"

def phase_summary(df):
    phases = df.groupby('longitudinal_phase').agg(
        count=('t_sec', 'count'),
        start_time=('t_sec', 'min'),
        end_time=('t_sec', 'max'),
        min_range=('range_3d_m', 'min'),
        max_range=('range_3d_m', 'max'),
        avg_range=('range_3d_m', 'mean'),
    ).reset_index()
    
    phases['duration'] = phases['end_time'] - phases['start_time']
    return phases

def main():
    print(color("\n╔══════════════════════════════════════════════════════════════╗", COLORS['HEADER']))
    print(color("║       AUTONOMOUS CHASING ANALYSIS REPORT                     ║", COLORS['HEADER']))
    print(color("║       Live Rival Geometry - Phase 6                         ║", COLORS['HEADER']))
    print(color("╚══════════════════════════════════════════════════════════════╝\n", COLORS['HEADER']))
    
    df = pd.read_csv(FILE_PATH)
    
    lines = [
        f"Total data points:     {len(df)}",
        f"Recording duration:   {df['t_sec'].max():.2f} sec",
        f"Time range:           {df['t_sec'].min():.2f} - {df['t_sec'].max():.2f} sec",
    ]
    box_print("MISSION OVERVIEW", lines)
    
    phases = phase_summary(df)
    
    lines = []
    for _, p in phases.iterrows():
        phase = p['longitudinal_phase']
        if phase == 'unavailable':
            continue
        lines.append(f"Phase: {phase.upper()}")
        lines.append(f"  Duration:     {p['duration']:.2f} sec")
        lines.append(f"  Time:         {p['start_time']:.2f} - {p['end_time']:.2f} sec")
        lines.append(f"  Range (3D):   {p['min_range']:.1f} - {p['max_range']:.1f} m (avg: {p['avg_range']:.1f} m)")
        lines.append(f"  Entries:      {int(p['count'])}")
        lines.append("")
    box_print("PHASE BREAKDOWN", lines[:-1])
    
    follow_lock = df[df['longitudinal_phase'] == 'follow_lock']
    
    lines = [
        stat_line("Duration", follow_lock['t_sec'].max() - follow_lock['t_sec'].min(), " sec"),
        stat_line("Entries", len(follow_lock), ""),
        "",
        stat_line("Range 3D - Min", follow_lock['range_3d_m'].min(), " m", True),
        stat_line("Range 3D - Max", follow_lock['range_3d_m'].max(), " m"),
        stat_line("Range 3D - Avg", follow_lock['range_3d_m'].mean(), " m"),
        stat_line("Range 3D - Std", follow_lock['range_3d_m'].std(), " m"),
        "",
        stat_line("Range XY - Min", follow_lock['range_xy_m'].min(), " m", True),
        stat_line("Range XY - Max", follow_lock['range_xy_m'].max(), " m"),
        stat_line("Range XY - Avg", follow_lock['range_xy_m'].mean(), " m"),
        stat_line("Range XY - Std", follow_lock['range_xy_m'].std(), " m"),
    ]
    box_print("FOLLOW_LOCK PHASE - RANGE METRICS", lines)
    
    lines = [
        stat_line("Bearing Error - Min", follow_lock['bearing_error_deg'].min(), " deg", True),
        stat_line("Bearing Error - Max", follow_lock['bearing_error_deg'].max(), " deg"),
        stat_line("Bearing Error - Avg", follow_lock['bearing_error_deg'].mean(), " deg"),
        stat_line("Bearing Error - Std", follow_lock['bearing_error_deg'].std(), " deg"),
        "",
        stat_line("Camera Cue Err - Min", follow_lock['camera_cue_error_deg'].min(), " deg", True),
        stat_line("Camera Cue Err - Max", follow_lock['camera_cue_error_deg'].max(), " deg"),
        stat_line("Camera Cue Err - Avg", follow_lock['camera_cue_error_deg'].mean(), " deg"),
        stat_line("Camera Cue Err - Std", follow_lock['camera_cue_error_deg'].std(), " deg"),
    ]
    box_print("FOLLOW_LOCK PHASE - ERROR METRICS", lines)
    
    in_cone = follow_lock[follow_lock['in_forward_cone'] == 1]
    lines = [
        f"Entries in forward cone: {len(in_cone)} / {len(follow_lock)} ({100*len(in_cone)/len(follow_lock):.1f}%)",
        f"First cone entry at:      t = {in_cone['t_sec'].min():.2f} sec" if len(in_cone) > 0 else "Never entered cone",
    ]
    box_print("FORWARD CONE STATUS", lines)
    
    intercept = follow_lock[follow_lock['intercept_age_sec'].notna()]
    lines = [
        f"Intercept active entries: {len(intercept)}",
        f"Intercept age at entry:   {intercept['intercept_age_sec'].iloc[0]:.2f} sec" if len(intercept) > 0 else "N/A",
        f"Intercept position X:    {intercept['intercept_x'].iloc[0]:.1f} m" if len(intercept) > 0 else "N/A",
        f"Intercept position Y:    {intercept['intercept_y'].iloc[0]:.1f} m" if len(intercept) > 0 else "N/A",
    ]
    box_print("INTERCEPT TRACKING", lines)
    
    lock_start = follow_lock['t_sec'].min()
    lock_end = follow_lock['t_sec'].max()
    range_at_lock = follow_lock[follow_lock['t_sec'] == lock_start]['range_3d_m'].values[0]
    range_at_end = follow_lock[follow_lock['t_sec'] == lock_end]['range_3d_m'].values[0]
    
    lines = [
        f"Lock acquired at:        t = {lock_start:.2f} sec",
        f"Range at lock start:    {range_at_lock:.2f} m",
        f"Range at lock end:      {range_at_end:.2f} m",
        f"Range closed by:        {range_at_lock - range_at_end:.2f} m",
    ]
    box_print("LOCK ACQUISITION SUMMARY", lines)
    
    spacing_counts = follow_lock['spacing_mode'].value_counts()
    lines = [f"Spacing mode: {mode} - {count} entries" for mode, count in spacing_counts.items()]
    box_print("SPACING MODE DISTRIBUTION", lines)
    
    output_lines = []
    output_lines.append("AUTONOMOUS CHASING ANALYSIS REPORT")
    output_lines.append("=" * 60)
    output_lines.append(f"Generated from: {FILE_PATH}")
    output_lines.append(f"Total duration: {df['t_sec'].max():.2f} sec")
    output_lines.append("")
    
    for phase in ['capture', 'settle', 'follow_lock']:
        p = phases[phases['longitudinal_phase'] == phase]
        if len(p) == 0:
            continue
        p = p.iloc[0]
        output_lines.append(f"PHASE: {phase.upper()}")
        output_lines.append(f"  Duration: {p['duration']:.2f} sec ({p['start_time']:.2f} - {p['end_time']:.2f})")
        output_lines.append(f"  Range 3D: {p['min_range']:.2f} - {p['max_range']:.2f} m (avg: {p['avg_range']:.2f})")
        output_lines.append("")
    
    fl = follow_lock
    output_lines.append("FOLLOW_LOCK DETAILED STATS")
    output_lines.append(f"  Range 3D: min={fl['range_3d_m'].min():.2f}, max={fl['range_3d_m'].max():.2f}, avg={fl['range_3d_m'].mean():.2f}, std={fl['range_3d_m'].std():.2f}")
    output_lines.append(f"  Range XY: min={fl['range_xy_m'].min():.2f}, max={fl['range_xy_m'].max():.2f}, avg={fl['range_xy_m'].mean():.2f}, std={fl['range_xy_m'].std():.2f}")
    output_lines.append(f"  Bearing Error: min={fl['bearing_error_deg'].min():.2f}, max={fl['bearing_error_deg'].max():.2f}, avg={fl['bearing_error_deg'].mean():.2f}")
    output_lines.append(f"  Camera Cue Error: min={fl['camera_cue_error_deg'].min():.2f}, max={fl['camera_cue_error_deg'].max():.2f}, avg={fl['camera_cue_error_deg'].mean():.2f}")
    output_lines.append("")
    output_lines.append(f"Lock acquired at t={lock_start:.2f}, range={range_at_lock:.2f}m")
    output_lines.append(f"Lock ended at t={lock_end:.2f}, range={range_at_end:.2f}m")
    output_lines.append(f"Range closed: {range_at_lock - range_at_end:.2f}m")
    
    with open(OUTPUT_FILE, 'w') as f:
        f.write('\n'.join(output_lines))
    
    print(color(f"\n[Report also saved to: {OUTPUT_FILE}]", COLORS['OKCYAN']))

if __name__ == '__main__':
    main()
