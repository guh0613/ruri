#!/usr/bin/env python3
"""Render an Icon Composer document as a flat .icns for builds without actool.

actool also compiles the layered Liquid Glass icon into Assets.car. This fallback
keeps the light fill, layer placement and shadows on the macOS icon grid, without
the glass material. Requires Pillow.
"""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
# The macOS app icon grid: an 824 pt rounded square centred on the canvas.
BODY, RADIUS = 824, 185


def color(value):
    space, channels = value.split(':', 1)
    if space != 'srgb':
        raise ValueError(f'Unsupported icon color space: {space}')
    return tuple(round(float(channel) * 255) for channel in channels.split(','))


def background(spec):
    fills = [item['value'] for item in spec.get('fill-specializations', []) if 'appearance' not in item]
    value = fills[0] if fills else spec.get('fill', {})
    if 'solid' in value:
        return Image.new('RGBA', (CANVAS, CANVAS), color(value['solid']))
    if 'automatic-gradient' not in value:
        raise ValueError(f'Unsupported icon fill: {value}')
    # Like actool's render: the color holds through the upper part, then darkens.
    top = color(value['automatic-gradient'])
    image = Image.new('RGBA', (CANVAS, CANVAS))
    draw = ImageDraw.Draw(image)
    for y in range(CANVAS):
        shade = 1 - 0.1 * max(0, (y - 0.4 * CANVAS) / (0.6 * CANVAS))
        draw.line([(0, y), (CANVAS, y)], fill=tuple(round(c * shade) for c in top[:3]) + top[3:])
    return image


def shadow(alpha, opacity, offset, blur):
    layer = Image.new('RGBA', alpha.size, (0, 0, 0, 0))
    layer.putalpha(alpha.point(lambda a: round(a * opacity)))
    moved = Image.new('RGBA', alpha.size, (0, 0, 0, 0))
    moved.paste(layer, (0, offset))
    return moved.filter(ImageFilter.GaussianBlur(blur))


def render(document):
    spec = json.loads((document / 'icon.json').read_text())
    body = Image.new('L', (CANVAS, CANVAS))
    inset = (CANVAS - BODY) // 2
    ImageDraw.Draw(body).rounded_rectangle([inset, inset, inset + BODY - 1, inset + BODY - 1], RADIUS, fill=255)
    artwork = background(spec)
    # The first group is frontmost; Icon Composer places images on the full canvas.
    for group in reversed(spec.get('groups', [])):
        content = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
        for layer in reversed(group.get('layers', [])):
            image = Image.open(document / 'Assets' / layer['image-name']).convert('RGBA')
            position = layer.get('position', {})
            size = round(CANVAS * position.get('scale', 1))
            image = image.resize((size, round(size * image.height / image.width)), Image.LANCZOS)
            x, y = position.get('translation-in-points', [0, 0])
            content.alpha_composite(image, (round((CANVAS - image.width) / 2 + x), round((CANVAS - image.height) / 2 + y)))
        if group.get('shadow', {}).get('kind', 'none') != 'none':
            artwork.alpha_composite(shadow(content.getchannel('A'), group['shadow'].get('opacity', 0.5), 16, 24))
        artwork.alpha_composite(content)
    artwork.putalpha(body)
    icon = shadow(body, 0.3, 10, 10)
    icon.alpha_composite(artwork)
    return icon


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('document', type=Path, help='Icon Composer .icon directory')
    parser.add_argument('output', type=Path, help='Destination .icns file')
    args = parser.parse_args()
    try:
        render(args.document).save(args.output, format='ICNS')
    except (ValueError, KeyError, OSError) as error:
        sys.exit(f'Unable to render {args.document}: {error}')
