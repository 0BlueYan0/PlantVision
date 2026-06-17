#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
馬纓丹 (Lantana camara) 影像資料集下載工具
================================================

從 iNaturalist 取得 CC 授權（cc0 / cc-by / cc-by-nc）的馬纓丹照片，
作為 PlantVision「枯萎程度 tile 分類器」的原始訓練素材。

特性：
  - 只下載 research-grade（已被社群驗證物種）的觀察紀錄。
  - 僅取 GBIF 也接受的開放授權，並把每張圖的授權與出處寫進 manifest.csv。
  - 可中斷續傳：已存在的檔案會自動跳過。
  - 只用 Python 標準函式庫，不需 pip 安裝任何套件。

用法：
    python3 download_lantana_dataset.py --count 300 --size medium

之後請參考同資料夾的 README_dataset.md 進行健康/枯萎的整理與標註。
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.parse
import urllib.request

API = "https://api.inaturalist.org/v1/observations"
TAXON = "Lantana camara"
# GBIF 接受的開放授權；若只要可商用可改成 "cc0,cc-by"
DEFAULT_LICENSES = "cc0,cc-by,cc-by-nc"
# iNaturalist 要求附上可辨識的 User-Agent
UA = "PlantVision-dataset-collector/1.0 (educational use; PlantVision project)"
VALID_SIZES = ("medium", "large", "small", "original")


def fetch_json(url, retries=3):
    """抓取 JSON，附帶重試。"""
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except Exception as err:  # noqa: BLE001 - 下載工具，盡量容錯
            last_err = err
            time.sleep(2 * (attempt + 1))
    raise last_err


def download_image(url, dest):
    """下載單張圖片到 dest，回傳是否成功。"""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        if len(data) < 1024:  # 太小通常是錯誤頁，不是真的圖
            return False
        with open(dest, "wb") as fh:
            fh.write(data)
        return True
    except Exception as err:  # noqa: BLE001
        print(f"    ! 下載失敗 {url}: {err}", file=sys.stderr)
        return False


def build_query(page, per_page, licenses):
    params = {
        "taxon_name": TAXON,
        "photos": "true",
        "photo_license": licenses,
        "quality_grade": "research",
        "iconic_taxa": "Plantae",
        "per_page": str(per_page),
        "page": str(page),
        "order": "desc",
        "order_by": "created_at",
    }
    return API + "?" + urllib.parse.urlencode(params)


def main():
    parser = argparse.ArgumentParser(description="下載馬纓丹 (Lantana camara) 影像資料集")
    parser.add_argument("--count", type=int, default=300,
                        help="目標圖片數量（預設 300，至少建議 120）")
    parser.add_argument("--size", choices=VALID_SIZES, default="medium",
                        help="圖片尺寸：medium=500px / large=1024px（預設 medium）")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "lantana_raw"),
                        help="輸出資料夾")
    parser.add_argument("--licenses", default=DEFAULT_LICENSES,
                        help="逗號分隔的授權白名單（預設 cc0,cc-by,cc-by-nc）")
    parser.add_argument("--max-per-observation", type=int, default=2,
                        help="同一筆觀察最多取幾張圖，避免同一株植物佔太多（預設 2）")
    parser.add_argument("--delay", type=float, default=1.0,
                        help="每次請求間隔秒數，禮貌對待 API（預設 1.0）")
    args = parser.parse_args()

    images_dir = os.path.join(args.out, "images")
    os.makedirs(images_dir, exist_ok=True)
    manifest_path = os.path.join(args.out, "manifest.csv")

    # 讀取既有 manifest，支援續傳
    existing = set()
    if os.path.exists(manifest_path):
        with open(manifest_path, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                existing.add(row["filename"])

    manifest_exists = os.path.exists(manifest_path)
    mf = open(manifest_path, "a", newline="", encoding="utf-8")
    writer = csv.DictWriter(mf, fieldnames=[
        "filename", "observation_id", "observation_url", "photo_id",
        "license", "attribution", "observed_on", "place_guess",
    ])
    if not manifest_exists:
        writer.writeheader()

    collected = len(existing)
    page = 1
    per_page = 200
    print(f"目標 {args.count} 張，尺寸 {args.size}，輸出到 {args.out}")
    print(f"已存在 {collected} 張，從第 {page} 頁開始抓取…\n")

    try:
        while collected < args.count:
            url = build_query(page, per_page, args.licenses)
            data = fetch_json(url)
            results = data.get("results", [])
            total = data.get("total_results", 0)
            if not results:
                print("已無更多觀察紀錄。")
                break
            print(f"[第 {page} 頁] 取得 {len(results)} 筆觀察（資料庫共 {total} 筆）")

            for obs in results:
                if collected >= args.count:
                    break
                photos = (obs.get("photos") or [])[: args.max_per_observation]
                for photo in photos:
                    if collected >= args.count:
                        break
                    square_url = photo.get("url")
                    if not square_url:
                        continue
                    img_url = square_url.replace("square", args.size)
                    fname = f"inat_{obs['id']}_{photo['id']}.jpg"
                    if fname in existing:
                        continue
                    dest = os.path.join(images_dir, fname)
                    if download_image(img_url, dest):
                        writer.writerow({
                            "filename": fname,
                            "observation_id": obs.get("id"),
                            "observation_url": obs.get("uri", ""),
                            "photo_id": photo.get("id"),
                            "license": photo.get("license_code", ""),
                            "attribution": (photo.get("attribution") or "").replace("\n", " "),
                            "observed_on": obs.get("observed_on", "") or "",
                            "place_guess": (obs.get("place_guess") or "").replace("\n", " "),
                        })
                        mf.flush()
                        existing.add(fname)
                        collected += 1
                        print(f"  ✓ {collected}/{args.count}  {fname}")
                        time.sleep(args.delay)
            page += 1
            time.sleep(args.delay)
    finally:
        mf.close()

    print(f"\n完成！共 {collected} 張圖片於 {images_dir}")
    print(f"授權與出處紀錄：{manifest_path}")
    print("下一步請參考 README_dataset.md 進行健康/枯萎整理與標註。")


if __name__ == "__main__":
    main()
