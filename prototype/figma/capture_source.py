"""Build an isolated offline copy for authentic Flutter screen captures.
Never copies credentials or changes production lib/ files.
"""
from pathlib import Path
import shutil, tempfile, re, json

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(tempfile.gettempdir()) / 'eternal-rest-figma-capture'
WORK.mkdir(exist_ok=True)
shutil.copytree(ROOT / 'lib', WORK / 'lib', dirs_exist_ok=True)
# Production entry point is not needed and may contain deployment configuration.
(WORK / 'lib/main.dart').write_text('void main() {}\n', encoding='utf-8')
for name in ['pubspec.yaml', 'pubspec.lock']:
    shutil.copy2(ROOT / name, WORK / name)
(WORK / 'test').mkdir(exist_ok=True)
shutil.copy2(Path(__file__).with_name('capture_test.dart'), WORK / 'test/capture_test.dart')

import sys
dark = '--dark' in sys.argv
palette = {'FBF9F6':'141713','F6F8F7':'141713','F5F3F0':'1D211C','EFEEEB':'242922',
 'EAE8E5':'2A3028','E4E2DF':'30372E','FFFFFF':'1A1F19','1B1C1A':'E5E8DF',
 '424841':'BFC8B9','727971':'A2AE9B','C2C8BF':'85917D','335538':'ABD3A9',
 '4B6E4F':'37583B','C5EDC6':'29482D','C7EFC8':'D0F2CA','C7E4F3':'2D4754',
 '4B6673':'B6D8E9','47626F':'B0CEDC','746356':'56473C','F7E1D0':'F7E1D0',
 '5A4B3F':'E6C7AE','CAE7F6':'294652','F5DECE':'4C3D31','BA1A1A':'FFB4AB'}
for path in (WORK / 'lib').rglob('*.dart'):
    source = path.read_text(encoding='utf-8')
    # Disable background realtime connections only in the disposable capture copy.
    source = re.sub(r'^\s*_subscribe\w*\(\);', '\n    // Offline capture: realtime disabled.', source, flags=re.M)
    if 'TileLayer(' in source:
        source = "import 'package:cemetery_app/capture_tiles.dart';\n" + source
        source = source.replace('TileLayer(', 'TileLayer(tileProvider: CaptureTiles(),')
    if path.name == 'visitor_profile_screen.dart':
        source = source.replace("Text(\n                      'Saved Memorials',", "Expanded(child: Text(\n                      'Saved Memorials',")
        source = source.replace("const Icon(Icons.bookmark_rounded, color: Colors.white)", "const Icon(Icons.bookmark_rounded, color: Colors.white)")
        source = source.replace("                    ),\n                    const Icon(Icons.bookmark_rounded", "                    )),\n                    const Icon(Icons.bookmark_rounded")
    if path.name == 'qr_scanner_screen.dart':
        start = source.index('MobileScanner(')
        pos = start + len('MobileScanner(')
        depth = 1
        while depth:
            if source[pos] == '(': depth += 1
            elif source[pos] == ')': depth -= 1
            pos += 1
        source = source[:start] + "const ColoredBox(color: Colors.black, child: Center(child: Text('Camera preview unavailable in offline prototype', style: TextStyle(color: Colors.white))))" + source[pos:]
    source = source.replace('TextStyle(', "TextStyle(fontFamily: 'Roboto',")
    source = re.sub(r'\bThemeData\(', "ThemeData(fontFamily: 'Roboto',", source)
    if dark:
        source = source.replace('bgColor: _C.primary,', 'bgColor: _C.primaryContainer,')
        source = re.sub(r'(?<![A-Za-z])(color|foregroundColor): (_C\.primaryContainer|_primaryContainer)\b', lambda m:m[1]+': '+m[2].replace('primaryContainer','primary'), source)
        source = source.replace('Colors.grey.shade100','const Color(0xFF282E25)').replace('Colors.grey.shade200','const Color(0xFF30372E)')
        source = re.sub(r'0xFF([0-9A-Fa-f]{6})', lambda m:'0xFF'+palette.get(m[1].upper(),m[1]), source)
        source = re.sub(r'(backgroundColor|fillColor): Colors.white\b', r'\1: const Color(0xFF1A1F19)', source)
        source = source.replace('Colors.black87', 'const Color(0xFFE5E8DF)').replace('Colors.black54','const Color(0xFFBFC8B9)')
        # White container fills (leave explicit white button/icon text untouched).
        source = re.sub(r'(BoxDecoration\(\s*color: )Colors.white',r'\1const Color(0xFF1A1F19)',source)
    path.write_text(source, encoding='utf-8')
(WORK / 'lib/capture_tiles.dart').write_text('''
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
class CaptureTiles extends TileProvider {
  @override ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII='));
}
''',encoding='utf-8')
(WORK / 'capture-config.json').write_text(json.dumps({'output':str(ROOT/'prototype/figma/screens'), 'dark':dark}),encoding='utf-8')
print(WORK)
