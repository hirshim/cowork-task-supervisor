#!/usr/bin/env python3
"""Cowork Task Supervisor アプリアイコン生成スクリプト
- Claudeのスパークシンボル + タスク要素
- Liquid Glass 風の質感
- ライトモード / ダークモード 両対応
"""

import math
import random
import os
import json
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CENTER = SIZE // 2


def polar_to_xy(cx, cy, r, theta):
  """極座標→直交座標"""
  return (cx + r * math.cos(theta), cy + r * math.sin(theta))


def draw_claude_spark(draw, cx, cy, radius, color, num_points=5, tip_ratio=0.38):
  """Claudeのスパーク（星型）シンボルを描画
  rounded petal/prong を放射状に配置
  """
  points = []
  steps = 360
  for i in range(steps):
    theta = 2 * math.pi * i / steps
    # 花びら型: cos の絶対値のべき乗でプロング形状を作る
    lobe = abs(math.cos(num_points * theta / 2))
    # べき乗で先端を丸くする
    lobe = lobe ** 1.8
    r = radius * (tip_ratio + (1 - tip_ratio) * lobe)
    x, y = polar_to_xy(cx, cy, r, theta)
    points.append((x, y))
  draw.polygon(points, fill=color)


def create_glass_spark(size, spark_color, highlight_alpha=80, shadow_alpha=30):
  """Liquid Glass 風のスパークレイヤーを生成"""
  layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  draw = ImageDraw.Draw(layer)

  cx, cy = size // 2, int(size * 0.48)
  radius = int(size * 0.30)

  # 影（下に少しオフセット）
  shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  s_draw = ImageDraw.Draw(shadow)
  draw_claude_spark(s_draw, cx + 2, cy + 6, int(radius * 1.02),
                    (0, 0, 0, shadow_alpha))
  shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))
  layer = Image.alpha_composite(layer, shadow)

  # 本体: ガラスの基本色
  body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  b_draw = ImageDraw.Draw(body)
  draw_claude_spark(b_draw, cx, cy, radius, spark_color)
  layer = Image.alpha_composite(layer, body)

  # ハイライト（上部に白いグラデーション）: ガラスの光沢
  highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  h_draw = ImageDraw.Draw(highlight)
  # 少し小さめ・上にオフセットしたスパークで白ハイライト
  draw_claude_spark(h_draw, cx, cy - int(radius * 0.08),
                    int(radius * 0.88),
                    (255, 255, 255, highlight_alpha))
  # 下半分をマスクして上部だけハイライト
  mask = Image.new("L", (size, size), 255)
  m_draw = ImageDraw.Draw(mask)
  m_draw.rectangle([0, cy + int(radius * 0.1), size, size], fill=0)
  # グラデーションマスク
  for y in range(cy - int(radius * 0.3), cy + int(radius * 0.1)):
    t = (y - (cy - int(radius * 0.3))) / (int(radius * 0.4))
    alpha = int(255 * (1 - t))
    m_draw.line([(0, y), (size, y)], fill=alpha)
  highlight.putalpha(Image.composite(
    highlight.getchannel("A"), Image.new("L", (size, size), 0), mask
  ))
  layer = Image.alpha_composite(layer, highlight)

  # エッジハイライト（細いリムライト）
  edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  e_draw = ImageDraw.Draw(edge)
  draw_claude_spark(e_draw, cx, cy, int(radius * 1.01),
                    (255, 255, 255, 25))
  # 本体マスクで内部を消す→エッジだけ残す
  inner_mask = Image.new("L", (size, size), 255)
  im_draw = ImageDraw.Draw(inner_mask)
  draw_claude_spark(im_draw, cx, cy, int(radius * 0.97), 0)
  edge_alpha = edge.getchannel("A")
  masked_alpha = Image.composite(
    edge_alpha, Image.new("L", (size, size), 0), inner_mask
  )
  edge.putalpha(masked_alpha)
  layer = Image.alpha_composite(layer, edge)

  return layer


def draw_task_elements(size, color, dim_color):
  """タスクリスト要素（チェック + ライン）を描画"""
  layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  draw = ImageDraw.Draw(layer)

  cx = size // 2
  cy_base = int(size * 0.48)
  radius = int(size * 0.30)

  # スパークの下部にタスクライン
  list_top = cy_base + int(radius * 0.85)
  list_spacing = int(size * 0.055)
  list_cx = cx - int(size * 0.10)
  bar_start = cx - int(size * 0.04)
  bar_end = cx + int(size * 0.12)
  bar_w = max(3, int(size * 0.007))
  chk_w = max(3, int(size * 0.009))
  chk_s = int(size * 0.018)

  for i in range(3):
    y = list_top + i * list_spacing
    c = color if i < 2 else dim_color

    if i < 2:
      # 小さなチェックマーク
      draw.line([
        (list_cx - chk_s, y),
        (list_cx - chk_s * 0.15, y + chk_s * 0.7),
        (list_cx + chk_s, y - chk_s * 0.55),
      ], fill=c, width=chk_w, joint="curve")
    else:
      cr = int(chk_s * 0.5)
      draw.ellipse(
        [list_cx - cr, y - cr, list_cx + cr, y + cr],
        outline=c, width=max(2, int(size * 0.004))
      )

    draw.line([(bar_start, y), (bar_end, y)], fill=c, width=bar_w)

  return layer


def create_icon(mode="dark"):
  """アイコン生成 (mode: 'dark' or 'light')"""
  img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

  # === 背景 ===
  if mode == "dark":
    # ダーク: 深い黒〜ダークグレー
    for y in range(SIZE):
      t = y / SIZE
      v = int(15 + (30 - 15) * t)
      img.putpixel((0, y), (v, v, int(v * 1.05), 255))
    for y in range(SIZE):
      t = y / SIZE
      v = int(15 + (30 - 15) * t)
      for x in range(SIZE):
        img.putpixel((x, y), (v, v, min(255, int(v * 1.08)), 255))
  else:
    # ライト: 明るいグレー〜白
    for y in range(SIZE):
      t = y / SIZE
      v = int(245 - (245 - 225) * t)
      for x in range(SIZE):
        img.putpixel((x, y), (v, v, v, 255))

  # === Liquid Glass: 微妙な光の反射 ===
  if mode == "dark":
    # 上部に微妙な明るいグラデーション
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow)
    gcx, gcy = int(SIZE * 0.48), int(SIZE * 0.25)
    max_r = int(SIZE * 0.5)
    for r in range(max_r, 0, -3):
      t = 1 - (r / max_r)
      alpha = int(12 * t * t)
      g_draw.ellipse(
        [gcx - r, gcy - r, gcx + r, gcy + r],
        fill=(100, 120, 180, alpha)
      )
    img = Image.alpha_composite(img, glow)
  else:
    # ライト: 微妙なウォームシャドウ
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow)
    gcx, gcy = int(SIZE * 0.50), int(SIZE * 0.65)
    max_r = int(SIZE * 0.4)
    for r in range(max_r, 0, -3):
      t = 1 - (r / max_r)
      alpha = int(8 * t * t)
      g_draw.ellipse(
        [gcx - r, gcy - r, gcx + r, gcy + r],
        fill=(0, 0, 30, alpha)
      )
    img = Image.alpha_composite(img, glow)

  # === Claude スパーク（Liquid Glass） ===
  if mode == "dark":
    # ダーク: 半透明の白〜淡いブルー
    spark_color = (200, 210, 240, 55)
    highlight_alpha = 70
    shadow_alpha = 50
  else:
    # ライト: 半透明のダークグレー〜淡いインディゴ
    spark_color = (60, 55, 90, 50)
    highlight_alpha = 90
    shadow_alpha = 20

  spark_layer = create_glass_spark(SIZE, spark_color, highlight_alpha, shadow_alpha)
  img = Image.alpha_composite(img, spark_layer)

  # === 内側にもう一層、少し濃いスパーク（ガラスの厚み表現） ===
  inner = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
  i_draw = ImageDraw.Draw(inner)
  cx, cy = SIZE // 2, int(SIZE * 0.48)
  inner_r = int(SIZE * 0.22)
  if mode == "dark":
    draw_claude_spark(i_draw, cx, cy, inner_r, (180, 195, 230, 25))
  else:
    draw_claude_spark(i_draw, cx, cy, inner_r, (40, 35, 70, 20))
  inner = inner.filter(ImageFilter.GaussianBlur(radius=4))
  img = Image.alpha_composite(img, inner)

  # === タスク要素 ===
  if mode == "dark":
    task_color = (255, 255, 255, 180)
    task_dim = (255, 255, 255, 70)
  else:
    task_color = (40, 40, 60, 180)
    task_dim = (40, 40, 60, 70)

  tasks = draw_task_elements(SIZE, task_color, task_dim)
  img = Image.alpha_composite(img, tasks)

  # === ガラスの反射ライン（上部） ===
  reflection = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
  r_draw = ImageDraw.Draw(reflection)
  ref_y = int(SIZE * 0.28)
  ref_alpha = 18 if mode == "dark" else 30
  for dy in range(int(SIZE * 0.04)):
    t = 1 - dy / (SIZE * 0.04)
    a = int(ref_alpha * t * t)
    c = (255, 255, 255, a) if mode == "dark" else (255, 255, 255, a)
    r_draw.line([(int(SIZE * 0.32), ref_y + dy), (int(SIZE * 0.68), ref_y + dy)], fill=c)
  # 反射をスパーク形状でマスク
  ref_mask = Image.new("L", (SIZE, SIZE), 0)
  rm_draw = ImageDraw.Draw(ref_mask)
  draw_claude_spark(rm_draw, cx, cy, int(SIZE * 0.29), 255)
  reflection.putalpha(Image.composite(
    reflection.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), ref_mask
  ))
  img = Image.alpha_composite(img, reflection)

  # === 微細ノイズ（Liquid Glassのテクスチャ感） ===
  random.seed(42)
  noise = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
  noise_amp = 4 if mode == "dark" else 3
  for y in range(0, SIZE, 2):
    for x in range(0, SIZE, 2):
      v = random.randint(-noise_amp, noise_amp)
      a = max(0, min(255, abs(v)))
      c = 255 if v > 0 else 0
      noise.putpixel((x, y), (c, c, c, a))
  img = Image.alpha_composite(img, noise)

  return img


def create_icon_set(light_img, dark_img, output_dir):
  """macOS AppIcon.appiconset（ライト/ダークモード対応）を生成"""
  os.makedirs(output_dir, exist_ok=True)

  sizes = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
  ]

  images = []

  for size, scale in sizes:
    pixel_size = size * scale

    # Any (デフォルト = ダーク寄り)
    fn_any = f"icon_{size}x{size}@{scale}x.png"
    dark_img.resize((pixel_size, pixel_size), Image.LANCZOS).save(
      os.path.join(output_dir, fn_any), "PNG"
    )
    images.append({
      "filename": fn_any,
      "idiom": "mac",
      "scale": f"{scale}x",
      "size": f"{size}x{size}"
    })

    # Dark
    fn_dark = f"icon_dark_{size}x{size}@{scale}x.png"
    dark_img.resize((pixel_size, pixel_size), Image.LANCZOS).save(
      os.path.join(output_dir, fn_dark), "PNG"
    )
    images.append({
      "appearances": [{"appearance": "luminosity", "value": "dark"}],
      "filename": fn_dark,
      "idiom": "mac",
      "scale": f"{scale}x",
      "size": f"{size}x{size}"
    })

    # Light
    fn_light = f"icon_light_{size}x{size}@{scale}x.png"
    light_img.resize((pixel_size, pixel_size), Image.LANCZOS).save(
      os.path.join(output_dir, fn_light), "PNG"
    )
    images.append({
      "appearances": [{"appearance": "luminosity", "value": "light"}],
      "filename": fn_light,
      "idiom": "mac",
      "scale": f"{scale}x",
      "size": f"{size}x{size}"
    })

  print(f"  Generated {len(sizes) * 3} icon files")

  contents = {
    "images": images,
    "info": {
      "author": "xcode",
      "version": 1
    }
  }

  with open(os.path.join(output_dir, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)
    f.write("\n")

  print(f"  Generated Contents.json")


if __name__ == "__main__":
  output_dir = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "CoworkTaskSupervisor", "Resources", "Assets.xcassets", "AppIcon.appiconset"
  )

  # 古いファイルを削除
  if os.path.exists(output_dir):
    for f in os.listdir(output_dir):
      os.remove(os.path.join(output_dir, f))

  print("Generating Cowork Task Supervisor icon (Light + Dark)...")
  print("  Creating dark variant...")
  dark = create_icon("dark")
  print("  Creating light variant...")
  light = create_icon("light")
  create_icon_set(light, dark, output_dir)
  print(f"Done! Output: {output_dir}")
