#!/usr/bin/env python3
"""Mintbook Cinnamon Island: original-size compact notch for maximized windows.

Patches the user's *local* custom Cinnamon Island v0.1.0 (Mintbook status layout)
without overwriting tabs, custom icons, or weather/clock/battery code.

Usage:
  python3 cinnamon-island-auto-compact.py --check
  python3 cinnamon-island-auto-compact.py --install
  python3 cinnamon-island-auto-compact.py --restore

No sudo. Checks all exact anchors before writing either of two files.
"""
from __future__ import annotations
import argparse
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys

UUID = 'cinnamon-island@rovillela'
LOCAL = Path.home() / '.local/share/cinnamon/extensions' / UUID
BACKUP_ROOT = Path.home() / '.local/share/mint-rice-backups/cinnamon-island-auto-compact'
FILES = ('extension.js', 'collapsed.js')
MARK = 'Mintbook automatic compact on maximized window'


def replace_once(src: str, old: str, new: str, label: str) -> str:
    hits = src.count(old)
    if hits != 1:
        raise ValueError(f'{label}: expected exactly one match, got {hits}. No files changed.')
    return src.replace(old, new, 1)


def patch_extension(src: str) -> str:
    src = replace_once(src,
        'const { Clutter, Gio, GLib, St } = imports.gi;',
        'const { Clutter, Gio, GLib, Meta, St } = imports.gi;', 'Meta import')
    # Keep the user's existing 440x44 dimensions; 170x28 only while compact.
    old = 'const EXPANDED = {'
    src = replace_once(src, old,
        '// ' + MARK + '\nconst COMPACT_COLLAPSED = { along: 170, depth: 28, ear: 6, radius: 10 };\n' + old,
        'compact dimensions')
    src = replace_once(src,
        '        this._hiddenNow = false;',
        '        this._hiddenNow = false;\n        this._autoCompact = false;\n        this._compactPollId = 0;',
        'compact state')

    src = replace_once(src,
        '''        let to = side ? EXPANDED_SIDE : EXPANDED;
        let m = {
            along: Math.round(lerp(COLLAPSED.along + this._collapsedExtra, to.along, alongProgress)),
            ear: Math.round(lerp(COLLAPSED.ear, to.ear, alongProgress)),
            depth: Math.round(lerp(COLLAPSED.depth, to.depth + (side ? 0 : this._expandedExtra), depthProgress)),
            radius: Math.round(lerp(COLLAPSED.radius, to.radius, depthProgress)),''',
        '''        let to = side ? EXPANDED_SIDE : EXPANDED;
        let baseCollapsed = this._autoCompact ? COMPACT_COLLAPSED : COLLAPSED;
        let m = {
            along: Math.round(lerp(baseCollapsed.along + this._collapsedExtra, to.along, alongProgress)),
            ear: Math.round(lerp(baseCollapsed.ear, to.ear, alongProgress)),
            depth: Math.round(lerp(baseCollapsed.depth, to.depth + (side ? 0 : this._expandedExtra), depthProgress)),
            radius: Math.round(lerp(baseCollapsed.radius, to.radius, depthProgress)),''',
        'dynamic compact geometry')
    src = replace_once(src,
        '''        let miniWidth = COLLAPSED.along + Math.round(this._collapsedExtra);
        mini.set_position(bodyX + Math.round((bodyW - miniWidth) / 2),
            this.position === 'bottom' ? bodyH - COLLAPSED.depth : 0);
        mini.set_size(miniWidth, COLLAPSED.depth);''',
        '''        let baseCollapsed = this._autoCompact ? COMPACT_COLLAPSED : COLLAPSED;
        let miniWidth = baseCollapsed.along + Math.round(this._collapsedExtra);
        mini.set_position(bodyX + Math.round((bodyW - miniWidth) / 2),
            this.position === 'bottom' ? bodyH - baseCollapsed.depth : 0);
        mini.set_size(miniWidth, baseCollapsed.depth);''',
        'compact content geometry')

    # The original extension lays out on the primary monitor, so this check
    # uses that monitor rather than global focus or a hard-coded display name.
    method = '''    // Mintbook: only windows on the Island's own monitor and current workspace.
    _hasMaximizedWindowOnIslandMonitor() {
        let monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || monitor.index === undefined)
            return false;
        let manager = global.workspace_manager || global.screen;
        let workspace = manager.get_active_workspace();
        return global.get_window_actors().some(actor => {
            let win = actor.get_meta_window();
            if (!win || win.get_window_type() !== Meta.WindowType.NORMAL ||
                win.minimized || !win.showing_on_its_workspace() ||
                win.get_monitor() !== monitor.index)
                return false;
            if (win.get_workspace() !== workspace && !win.is_on_all_workspaces())
                return false;
            let flags = win.get_maximized();
            return (flags & Meta.MaximizeFlags.BOTH) === Meta.MaximizeFlags.BOTH;
        });
    }

'''
    src = replace_once(src, '    _isSide() {', method + '    _isSide() {', 'monitor-specific detection')

    src = replace_once(src,
        "        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._relayout());",
        """        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._relayout());

        // Check every 500 ms: handles maximization, minimization, workspace
        // switches, window closure and monitor reconnection without window
        // signal handlers that would need individual lifetime management.
        this._autoCompact = this._hasMaximizedWindowOnIslandMonitor();
        this._collapsed.setCompactMode(this._autoCompact);
        this._compactPollId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
            let compact = this._hasMaximizedWindowOnIslandMonitor();
            if (compact !== this._autoCompact) {
                this._autoCompact = compact;
                this._collapsed.setCompactMode(compact);
                this._relayout();
            }
            return GLib.SOURCE_CONTINUE;
        });""",
        'start compact monitor')
    src = replace_once(src,
        '    destroy() {\n        this._cancelClose();\n        this._stopTimeline();',
        '''    destroy() {
        if (this._compactPollId) {
            GLib.source_remove(this._compactPollId);
            this._compactPollId = 0;
        }
        this._cancelClose();
        this._stopTimeline();''',
        'disconnect compact monitor')
    return src


def patch_collapsed(src: str) -> str:
    if 'this._statusWeather' not in src or 'this._statusClock' not in src or 'this._statusBattery' not in src:
        raise ValueError('the Mintbook persistent weather/clock/battery layout is missing')
    method = '''    // Mintbook: preserve the native mini (music, timers, event notices)
    // while hiding only the custom *permanent* status in compact mode.
    setCompactMode(compact) {
        compact = !!compact;
        if (this._compactMode === compact)
            return;
        this._compactMode = compact;
        this._statusWeather.visible = !compact;
        this._statusClock.visible = !compact;
        this._statusBattery.visible = !compact && !!this._lastSystemHasBattery;
        this._sync();
    }

'''
    src = replace_once(src, '    setMusic(state) {', method + '    setMusic(state) {', 'compact display API')
    src = replace_once(src,
        '        this._statusBattery.visible = !!battery;',
        '        this._lastSystemHasBattery = !!battery;\n        this._statusBattery.visible = !!battery && !this._compactMode;',
        'battery while compact')
    src = replace_once(src,
        '        this._music.visible = !flashing && !noticing;',
        '''        this._music.visible = !flashing && !noticing &&
            (!this._compactMode || !!this._hasMusic || !!this._hasPomodoro || !!next || awake);''',
        'native collapsed behavior')
    return src


def validate_js(changes: dict[str, str]) -> None:
    node = shutil.which('node')
    if not node:
        print('Note: Node.js not installed; structural checks passed, JS syntax not checked.')
        return
    for name, code in changes.items():
        proc = subprocess.run([node, '--check', '--input-type=commonjs'], input=code,
                              capture_output=True, text=True)
        if proc.returncode:
            raise ValueError(f'{name} failed JS syntax check:\n{proc.stderr}')


def reload_island():
    cmd = ['dbus-send', '--session', '--dest=org.Cinnamon', '--type=method_call',
           '/org/Cinnamon', 'org.Cinnamon.ReloadXlet',
           f'string:{UUID}', 'string:EXTENSION']
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if proc.returncode:
            print('Reload returned:', proc.stderr.strip() or f'exit {proc.returncode}')
        else:
            print('Cinnamon Island reload requested.')
    except (OSError, subprocess.TimeoutExpired) as e:
        print('Could not reload automatically:', e)
    print('If nothing changes, disable/enable the extension or log out/in.')


def main():
    parser = argparse.ArgumentParser(description='Cinnamon Island: auto compact on maximized windows')
    commands = parser.add_mutually_exclusive_group(required=True)
    commands.add_argument('--check', action='store_true', help='test compatibility without writing')
    commands.add_argument('--install', action='store_true', help='back up and patch the local extension')
    commands.add_argument('--restore', action='store_true', help='restore latest backup')
    args = parser.parse_args()

    if not LOCAL.is_dir() or LOCAL.is_symlink():
        sys.exit(f'Local extension not found (or symlink): {LOCAL}\nNo files changed.')
    if args.restore:
        snapshots = sorted(x for x in BACKUP_ROOT.iterdir() if x.is_dir()) if BACKUP_ROOT.exists() else []
        if not snapshots:
            sys.exit('No auto-compact backup found.')
        snap = snapshots[-1]
        for filename in FILES:
            src = snap / filename
            if not src.is_file():
                sys.exit(f'Backup incomplete: {src}; no files changed.')
        for filename in FILES:
            shutil.copy2(snap / filename, LOCAL / filename)
        print(f'Restored from: {snap}')
        reload_island()
        return

    current = {f: (LOCAL / f).read_text(encoding='utf-8') for f in FILES}
    if MARK in current['extension.js']:
        print('Auto-compact is already installed. Nothing to do.')
        return
    try:
        changes = {
            'extension.js': patch_extension(current['extension.js']),
            'collapsed.js': patch_collapsed(current['collapsed.js']),
        }
        validate_js(changes)
    except ValueError as e:
        sys.exit('SAFETY STOP: ' + str(e) + '\nNo files changed.')
    if args.check:
        print('Compatibility check passed. Ready to install; no files changed.')
        return

    backup = BACKUP_ROOT / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True)
    for f in FILES:
        (backup / f).write_text(current[f], encoding='utf-8')
    for f in FILES:
        (LOCAL / f).write_text(changes[f], encoding='utf-8')
    print('Mintbook auto-compact installed. Backup:', backup)
    print('Maximized on island monitor: 170x28, native mini status; otherwise original 440x44.')
    reload_island()


if __name__ == '__main__':
    main()
