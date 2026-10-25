-- ═══════════════════════════════════════════════════════════════
--  cp_app_medical.db  —  SQLite Schema (v1.0.5)
--  مولَّد من الداتابيز الفعلية (مش تصميم نظري) عشان يطابق اللي بيشتغل عليه الكود.
--
--  • المطابقة كلها بالاسم النصي للمادة الفعالة (drugs.normalized_generics مفصولة بـ "|")
--    وrxcui متخزن TEXT في كل الجداول — مفيش مقارنات رقمية.
--  • diagnosis_drug_indications.source:
--        'rxclass'         = من RxClass (مؤشرات مرخّصة — آلي)
--        'manual'          = مؤشر موثّق يدوياً (label/guideline)
--        'manual_offlabel' = استخدام شائع/غير رسمي → التطبيق يطلع تنبيه info
--    الأعمدة note و verified (v1.0.5): verified=0 = مضاف بمساعدة AI ولسه
--    محتاج مراجعة صيدلي إكلينيكي.
--  • v1.0.5: جداول حدود الجرعات (generic_dose_limits / _alt / _aliases) — بتتبني بـ
--        python patch_db_v1_0_5.py cp_app_medical.db dose_limits_ALL.sql
--        الأعمدة ped_min_age_years / ped_note / flag_severity مشتقة من notes (راجعها صيدلي).
--  • مفيش sample data هنا — البيانات الحقيقية في الـ DB نفسها.
--    (بيانات الـ sample القديمة كان فيها rxcui مكرر لـ Ciprofloxacin/Ibuprofen.)
--  • لتطبيق تعديلات 1.0.4 على DB قديمة: python patch_db_v1_0_4.py cp_app_medical.db
-- ═══════════════════════════════════════════════════════════════

PRAGMA journal_mode = WAL;

CREATE TABLE beers_criteria (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_name   TEXT NOT NULL,
    drug_lower  TEXT NOT NULL,
    category    TEXT NOT NULL,   -- Avoid / Use with caution / Avoid in specific conditions
    rationale   TEXT,
    alternative TEXT,
    min_age     INTEGER DEFAULT 65
);

CREATE TABLE diagnoses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, icd10 TEXT,
        specialty TEXT NOT NULL, name_lower TEXT NOT NULL,
        is_base INTEGER DEFAULT 1, source_id TEXT, source TEXT DEFAULT 'rxclass', rxclass_id TEXT, UNIQUE(name)
    );

CREATE TABLE diagnosis_alias_maps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alias_id INTEGER NOT NULL, diagnosis_id INTEGER NOT NULL,
        UNIQUE(alias_id, diagnosis_id)
    );

CREATE TABLE diagnosis_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alias TEXT NOT NULL, alias_lower TEXT NOT NULL,
        created_by TEXT DEFAULT 'system', UNIQUE(alias)
    );

CREATE TABLE diagnosis_drug_indications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        diagnosis_id INTEGER NOT NULL, rxcui TEXT NOT NULL, drug_name TEXT NOT NULL,
        adult_dose_min REAL, adult_dose_max REAL, adult_unit TEXT,
        adult_freq_per_day REAL, adult_max_daily REAL,
        elderly_dose_min REAL, elderly_dose_max REAL, elderly_unit TEXT,
        ped_dose_per_kg_min REAL, ped_dose_per_kg_max REAL, ped_unit TEXT, ped_max_daily REAL,
        neo_dose_per_kg REAL, neo_unit TEXT,
        renal_adjustment TEXT, hepatic_adjustment TEXT,
        max_daily_dose REAL, max_dose_unit TEXT, source TEXT DEFAULT 'manual', note TEXT, verified INTEGER DEFAULT 1,
        UNIQUE(diagnosis_id, rxcui)
    );

CREATE TABLE diagnosis_symptoms (
  diagnosis_id INTEGER NOT NULL,
  symptom_id   INTEGER NOT NULL,
  PRIMARY KEY (diagnosis_id, symptom_id)
);

CREATE TABLE drug_interactions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_a_rxcui  TEXT NOT NULL,
    drug_a_name   TEXT NOT NULL,
    drug_b_rxcui  TEXT NOT NULL,
    drug_b_name   TEXT NOT NULL,
    severity      TEXT,
    description   TEXT,
    source        TEXT
);

CREATE TABLE drug_labels (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            rxcui             TEXT UNIQUE NOT NULL,
            drug_name         TEXT NOT NULL,
            set_id            TEXT,
            interactions_text TEXT,
            warnings_text     TEXT,
            dosage_text       TEXT,
            contraindications TEXT,
            dose_thresholds   TEXT,
            fetched_at        TEXT
        );

CREATE TABLE drugs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_name          TEXT NOT NULL,        -- AUGMENTIN 625 MG 10 F.C.TABS.
    trade_name          TEXT NOT NULL,        -- AUGMENTIN
    strength            TEXT,                 -- 625 MG
    dosage_form         TEXT,                 -- F.C.TABS
    generic_name        TEXT NOT NULL,        -- AMOXICILLIN+CLAVULANIC ACID
    normalized_generics TEXT,                 -- AMOXICILLIN|CLAVULANATE
    company             TEXT,
    country             TEXT,
    brand_lower         TEXT NOT NULL,
    trade_lower         TEXT NOT NULL
);

CREATE TABLE fda_drug_mentions (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            source_rxcui  TEXT NOT NULL,   -- الدواء اللي جاب النص
            source_name   TEXT NOT NULL,
            mentioned_drug TEXT NOT NULL,  -- الدواء المذكور في نص التداخل
            mentioned_lower TEXT NOT NULL,
            context       TEXT,            -- النص اللي ذكر فيه
            severity_hint TEXT,            -- Major/Moderate/Minor لو ظهر
            UNIQUE(source_rxcui, mentioned_drug)
        );

CREATE TABLE generic_dose_limit_alt (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  ingredient            TEXT NOT NULL,
  source_name           TEXT NOT NULL,
  source_url            TEXT,
  adult_max_daily_mg    REAL,
  ped_max_mg_per_kg_day REAL,
  note                  TEXT,
  UNIQUE(ingredient, source_name)
);

CREATE TABLE generic_dose_limit_aliases (
                alias_lower TEXT PRIMARY KEY,
                ingredient  TEXT NOT NULL
            );

CREATE TABLE generic_dose_limits (
                id                    INTEGER PRIMARY KEY AUTOINCREMENT,
                ingredient            TEXT NOT NULL UNIQUE,
                adult_max_daily_mg    REAL,
                ped_max_mg_per_kg_day REAL,
                special_flag          TEXT,
                notes                 TEXT,
                source                TEXT,
                verified              INTEGER DEFAULT 0
            , verified_by TEXT, verified_at TEXT, ped_min_age_years REAL, ped_note TEXT, flag_severity TEXT);

CREATE TABLE generics (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    rxcui       TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    name_lower  TEXT NOT NULL
);

CREATE TABLE herb_aliases (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    herb_id     INTEGER NOT NULL,
    alias       TEXT NOT NULL,
    alias_lower TEXT NOT NULL,
    FOREIGN KEY (herb_id) REFERENCES herbs(id)
);

CREATE TABLE herb_interactions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    herb_id     INTEGER NOT NULL,
    drug_name   TEXT NOT NULL,
    drug_lower  TEXT NOT NULL,
    severity    TEXT NOT NULL,
    effect      TEXT NOT NULL,
    mechanism   TEXT,
    FOREIGN KEY (herb_id) REFERENCES herbs(id)
);

CREATE TABLE herbs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    canonical_name  TEXT UNIQUE NOT NULL,
    canonical_lower TEXT NOT NULL
);

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE symptoms (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL UNIQUE,
  name_lower TEXT NOT NULL,
  is_top     INTEGER DEFAULT 0,
  top_order  INTEGER
);

CREATE TABLE synonyms (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    egypt_name   TEXT NOT NULL,
    rxnav_name   TEXT NOT NULL,
    rxcui        TEXT,
    source       TEXT DEFAULT 'manual'
);

CREATE INDEX idx_beers_drug ON beers_criteria(drug_lower);

CREATE INDEX idx_dla_ing ON generic_dose_limit_alt(ingredient);

CREATE INDEX idx_drugs_brand  ON drugs(brand_lower);

CREATE INDEX idx_drugs_generic ON drugs(generic_name);

CREATE INDEX idx_drugs_trade  ON drugs(trade_lower);

CREATE INDEX idx_dsym_diag ON diagnosis_symptoms(diagnosis_id);

CREATE INDEX idx_fda_mentioned ON fda_drug_mentions(mentioned_lower);

CREATE INDEX idx_fda_source ON fda_drug_mentions(source_rxcui);

CREATE INDEX idx_generics_name ON generics(name_lower);

CREATE INDEX idx_herb_alias ON herb_aliases(alias_lower);

CREATE INDEX idx_herb_inter_drug ON herb_interactions(drug_lower);

CREATE INDEX idx_herb_inter_herb ON herb_interactions(herb_id);

CREATE INDEX idx_inter_a ON drug_interactions(drug_a_rxcui);

CREATE INDEX idx_inter_b ON drug_interactions(drug_b_rxcui);

CREATE INDEX idx_labels_rxcui ON drug_labels(rxcui);

CREATE INDEX idx_sym_name ON symptoms(name_lower);

CREATE INDEX idx_syn_egypt ON synonyms(egypt_name);
