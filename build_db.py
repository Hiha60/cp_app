#!/usr/bin/env python3
"""
build_db.py — يبني cp_app_medical.db من db_schema.sql
الاستخدام:
    python build_db.py
الناتج:
    assets/databases/cp_app_medical.db
"""

import sqlite3
import os
import shutil
from pathlib import Path

SCHEMA_FILE = "db_schema.sql"
OUTPUT_DIR  = Path("assets/databases")
OUTPUT_FILE = OUTPUT_DIR / "cp_app_medical.db"

def build():
    # تأكد من وجود المجلد
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # احذف القديم لو موجود
    if OUTPUT_FILE.exists():
        OUTPUT_FILE.unlink()
        print(f"✓ حذف القديم: {OUTPUT_FILE}")

    # قرأ السكيما
    with open(SCHEMA_FILE, "r", encoding="utf-8") as f:
        schema = f.read()

    # بنى الـ DB
    conn = sqlite3.connect(str(OUTPUT_FILE))
    conn.executescript(schema)
    conn.commit()

    # إحصائيات
    cursor = conn.cursor()
    stats = {}
    for table in ["generics", "drugs", "drug_interactions",
                  "herb_interactions", "diagnoses",
                  "diagnosis_drug_indications", "beers_criteria"]:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            stats[table] = cursor.fetchone()[0]
        except Exception:
            stats[table] = "—"

    conn.close()

    size_kb = OUTPUT_FILE.stat().st_size / 1024
    print(f"\n✅ تم بناء قاعدة البيانات: {OUTPUT_FILE}")
    print(f"   الحجم: {size_kb:.1f} KB\n")
    print("   الجداول:")
    for t, c in stats.items():
        print(f"     {t:40s} {c} سجل")
    print()

if __name__ == "__main__":
    build()
