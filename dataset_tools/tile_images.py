#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
馬纓丹枯萎資料集 — 切 tile 工具
================================

把人工分類好的整張圖切成「與 Mac 端推論一致」的重疊小塊（tile），擺成可直接餵
Create ML / coremltools 的資料夾結構。

輸入（人工分類後，見 README_dataset.md）：
    dataset_tools/lantana_raw/sorted/healthy/*.jpg
    dataset_tools/lantana_raw/sorted/withered/*.jpg

輸出：
    dataset_tools/lantana_tiles/train/{healthy,withered}/*.png
    dataset_tools/lantana_tiles/test/{healthy,withered}/*.png

關鍵：
  * tile 幾何**完全對齊** MacFrameRelayCore 的 `PlantImageClassifier.tileRects`
    （全幅中央正方形＋半幅滑動窗，步幅為邊長一半）。Swift 端用
    `tileRectsMatchesPinnedGeometryFor6x4` 釘住，這裡用 `--selftest` 對同一組案例驗證，
    兩邊一旦走樣會立刻被抓到。
  * train/test 切分**以來源圖為單位分組**：同一張原圖的所有 tile 只會落在 train 或 test，
    不會同時出現在兩邊（避免資料洩漏）。

用法：
    python3 tile_images.py --selftest          # 只驗證幾何，不需 Pillow 或資料
    python3 tile_images.py                      # 用預設路徑切 tile（需要 Pillow）
    python3 tile_images.py --input <夾> --output <夾> --test-frac 0.2 --seed 42
"""

import argparse
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = ("healthy", "withered")


def tile_rects(width, height):
    """回傳 [(x, y, w, h), ...]，與 Swift 的 PlantImageClassifier.tileRects 逐項一致。

    全幅中央正方形 + 邊長為一半、步幅為邊長一半的滑動窗（相鄰區塊重疊），
    右/下緣會被夾住，使區塊不超出畫面。整數除法用 // （floor），對齊 Swift 的整數除法。
    """
    full_side = min(width, height)
    rects = [((width - full_side) // 2, (height - full_side) // 2, full_side, full_side)]

    side = full_side // 2
    if side <= 0:
        return rects
    stride = max(1, side // 2)

    y = 0
    while True:
        x = 0
        while True:
            rects.append((x, y, side, side))
            if x + side >= width:
                break
            x = min(x + stride, width - side)
        if y + side >= height:
            break
        y = min(y + stride, height - side)
    return rects


def _selftest():
    """對齊 Swift 端釘住的幾何案例。"""
    # 6×4：對應 MacFrameRelayCoreTests 的 tileRectsMatchesPinnedGeometryFor6x4
    expected = [(1, 0, 4, 4)]
    for yy in (0, 1, 2):
        for xx in (0, 1, 2, 3, 4):
            expected.append((xx, yy, 2, 2))
    got = tile_rects(6, 4)
    assert got == expected, f"6x4 幾何不符\n期望 {expected}\n實得 {got}"

    # 一般尺寸：第一塊是置中全幅方塊，且所有區塊都在畫面內
    w, h = 2560, 1664
    rects = tile_rects(w, h)
    full = min(w, h)
    assert rects[0] == ((w - full) // 2, (h - full) // 2, full, full), "中央全幅方塊不符"
    for (x, y, rw, rh) in rects:
        assert x >= 0 and y >= 0 and x + rw <= w and y + rh <= h, f"區塊超出畫面：{(x, y, rw, rh)}"
    assert len(rects) > 1, "應有中央方塊以外的滑動窗區塊"

    # 正方形邊界案例
    assert tile_rects(4, 4)[0] == (0, 0, 4, 4)

    print("selftest 通過：tile 幾何與 Swift PlantImageClassifier.tileRects 對齊。")


def _load_pillow():
    try:
        from PIL import Image  # noqa: F401
        return Image
    except ImportError:
        sys.exit(
            "需要 Pillow 才能切圖：請先安裝\n"
            "    python3 -m pip install Pillow\n"
            "（只驗證幾何可改用 --selftest，不需 Pillow）"
        )


def tile_one_image(Image, src_path, out_dir, stem):
    """把單張圖依 tile_rects 切塊，存成 PNG。回傳產生的 tile 數。"""
    with Image.open(src_path) as img:
        img = img.convert("RGB")
        width, height = img.size
        count = 0
        for index, (x, y, w, h) in enumerate(tile_rects(width, height)):
            tile = img.crop((x, y, x + w, y + h))
            tile.save(os.path.join(out_dir, f"{stem}_tile{index}.png"))
            count += 1
    return count


def list_source_images(class_dir):
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}
    names = [
        n for n in os.listdir(class_dir)
        if os.path.splitext(n)[1].lower() in exts and not n.startswith(".")
    ]
    return sorted(names)


def main():
    parser = argparse.ArgumentParser(description="把分類好的馬纓丹圖切成對齊推論的 tile")
    parser.add_argument("--selftest", action="store_true", help="只驗證 tile 幾何，不需資料或 Pillow")
    parser.add_argument("--input", default=os.path.join(HERE, "lantana_raw", "sorted"),
                        help="輸入資料夾，內含 healthy/ 與 withered/")
    parser.add_argument("--output", default=os.path.join(HERE, "lantana_tiles"),
                        help="輸出資料夾，會建立 train/ 與 test/")
    parser.add_argument("--test-frac", type=float, default=0.2, help="測試集比例（以來源圖為單位，預設 0.2）")
    parser.add_argument("--seed", type=int, default=42, help="train/test 切分亂數種子（預設 42，可重現）")
    args = parser.parse_args()

    if args.selftest:
        _selftest()
        return

    Image = _load_pillow()

    if not os.path.isdir(args.input):
        sys.exit(
            f"找不到輸入資料夾：{args.input}\n"
            "請先依 README_dataset.md 下載並人工分類，把整張圖放到\n"
            "    lantana_raw/sorted/healthy/ 與 lantana_raw/sorted/withered/"
        )

    rng = random.Random(args.seed)
    totals = {"train": 0, "test": 0}

    for class_name in CLASSES:
        class_dir = os.path.join(args.input, class_name)
        if not os.path.isdir(class_dir):
            print(f"略過：找不到 {class_dir}")
            continue

        images = list_source_images(class_dir)
        if not images:
            print(f"略過：{class_dir} 沒有圖片")
            continue

        # 以「來源圖」為單位洗牌後切分，確保同一張圖的 tile 不會跨 train/test（避免洩漏）。
        shuffled = images[:]
        rng.shuffle(shuffled)
        test_count = int(round(len(shuffled) * args.test_frac))
        # 圖夠多時，至少保留 1 張做測試
        if len(shuffled) >= 2:
            test_count = max(1, min(test_count, len(shuffled) - 1))
        split = {"test": shuffled[:test_count], "train": shuffled[test_count:]}

        for subset, names in split.items():
            out_dir = os.path.join(args.output, subset, class_name)
            os.makedirs(out_dir, exist_ok=True)
            for name in names:
                stem = os.path.splitext(name)[0]
                tiles = tile_one_image(Image, os.path.join(class_dir, name), out_dir, stem)
                totals[subset] += tiles
            print(f"{class_name}/{subset}：{len(names)} 張來源圖 → {out_dir}")

    print(f"\n完成。train tile 共 {totals['train']}、test tile 共 {totals['test']}，輸出於 {args.output}")
    print("下一步：用 dataset_tools/train_wither_classifier.swift 訓練 WitherClassifier（見 Stage B）。")


if __name__ == "__main__":
    main()
