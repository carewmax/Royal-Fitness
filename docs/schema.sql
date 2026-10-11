-- =====================================================================
-- ROYAL FITNESS — production database schema (MySQL 8)
-- Matches the web prototype's demo backend. The rules that MUST live on
-- the server are noted next to the tables that enforce them.
-- =====================================================================

-- ---------- configuration (prices, durations, reminder days, scoring) ----------
CREATE TABLE plans (
  id            VARCHAR(20) PRIMARY KEY,            -- daily, monthly, m3, m6, m12
  name          VARCHAR(40)  NOT NULL,
  price_minor   INT          NOT NULL,              -- store in minor units of the settlement currency
  currency      CHAR(3)      NOT NULL,              -- confirm with provider (USD vs SLE) before launch
  duration_days INT          NOT NULL,
  per_month_minor INT        NULL,
  active        BOOLEAN      NOT NULL DEFAULT TRUE
);
CREATE TABLE settings (
  k VARCHAR(60) PRIMARY KEY,
  v JSON NOT NULL                                   -- notify_days_before [7,3,1,0], renewal_rule 'stack', score weights ...
);

-- ---------- guest checkout (no account exists yet) ----------
CREATE TABLE orders (
  id              CHAR(12)     PRIMARY KEY,         -- ORD-XXXXXXXX
  idempotency_key VARCHAR(120) NOT NULL,            -- purpose|phone-or-user|plan ; blocks duplicate checkouts
  purpose         ENUM('new','renew') NOT NULL,
  plan_id         VARCHAR(20)  NOT NULL REFERENCES plans(id),
  amount_minor    INT          NOT NULL,            -- copied from plans at order time
  currency        CHAR(3)      NOT NULL,
  buyer_name      VARCHAR(120) NOT NULL,
  buyer_phone     VARCHAR(20)  NOT NULL,            -- E.164
  buyer_email     VARCHAR(160) NULL,
  user_id         BIGINT       NULL,                -- set for renewals
  status          ENUM('pending','awaiting','paid','failed','cancelled','refunded') NOT NULL DEFAULT 'pending',
  provider        VARCHAR(30)  NOT NULL DEFAULT 'monime',
  provider_ref    VARCHAR(80)  NULL,
  receipt_no      VARCHAR(20)  NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at         DATETIME     NULL,
  UNIQUE KEY uq_open_order (idempotency_key, status),
  KEY ix_phone (buyer_phone)
);
-- RULE: status becomes 'paid' ONLY inside the provider webhook handler, after
-- (1) verifying the webhook signature and (2) re-fetching the payment from the
-- provider API and matching amount, currency and order id. Never from the browser.
CREATE TABLE payment_events (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id    CHAR(12)    NOT NULL REFERENCES orders(id),
  provider_event_id VARCHAR(80) NOT NULL UNIQUE,    -- makes webhook retries harmless
  payload     JSON        NOT NULL,
  verified    BOOLEAN     NOT NULL,
  received_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------- activation (paid order -> account) ----------
CREATE TABLE activation_tokens (
  token_hash  CHAR(64)  PRIMARY KEY,                -- SHA-256 of the random token; never store the token itself
  order_id    CHAR(12)  NOT NULL REFERENCES orders(id),
  expires_at  DATETIME  NOT NULL,                   -- created_at + 48h
  used_at     DATETIME  NULL,
  revoked_at  DATETIME  NULL,                       -- a re-send revokes older tokens
  KEY ix_order (order_id)
);
-- RULE: account creation requires a token that exists, is unused, unrevoked, unexpired,
-- and whose order is 'paid' and purpose='new'. Mark used_at in the same transaction.
-- Re-send requires order number + matching phone, and is rate limited.

-- ---------- accounts and identity ----------
CREATE TABLE users (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  member_id     CHAR(9)      NOT NULL UNIQUE,       -- RF-123456 (shown on card)
  qr_ref        CHAR(26)     NOT NULL UNIQUE,       -- random; the only thing in the member QR code
  display_name  VARCHAR(80)  NOT NULL,
  phone         VARCHAR(20)  NOT NULL UNIQUE,       -- one identity per phone; renewals attach here
  email         VARCHAR(160) NULL,
  password_hash VARCHAR(255) NOT NULL,              -- argon2id / bcrypt
  phone_verified_at DATETIME NULL,
  onboarded_at  DATETIME     NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE sessions (
  id CHAR(64) PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  expires_at DATETIME NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE login_attempts (phone VARCHAR(20), at DATETIME, ok BOOLEAN, KEY (phone, at));   -- rate limiting

CREATE TABLE memberships (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id    BIGINT      NOT NULL REFERENCES users(id),
  order_id   CHAR(12)    NOT NULL UNIQUE REFERENCES orders(id),
  plan_id    VARCHAR(20) NOT NULL REFERENCES plans(id),
  start_date DATE        NOT NULL,
  end_date   DATE        NOT NULL,                  -- inclusive
  status_override ENUM('suspended','cancelled') NULL,
  KEY ix_user_dates (user_id, end_date)
);
-- RULE: status is computed from dates on the server clock:
--   none / active / expiring (<= 7 days) / expired / renewal pending (open renew order).
-- Every member-only API checks it. Expired users keep read access to history if settings allow.
-- Renewal ('stack'): start = max(today, current end + 1 day).

CREATE TABLE notifications (
  id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id   BIGINT       NOT NULL REFERENCES users(id),
  dedupe_key VARCHAR(80) NOT NULL,                  -- e.g. exp:2026-10-14:3  (never sent twice)
  title     VARCHAR(120) NOT NULL,
  body      VARCHAR(400) NOT NULL,
  action    VARCHAR(20)  NULL,
  channels  SET('inapp','push','sms','email') NOT NULL DEFAULT 'inapp',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at   DATETIME     NULL,
  UNIQUE KEY uq_dedupe (user_id, dedupe_key)
);
CREATE TABLE notification_prefs (
  user_id BIGINT PRIMARY KEY REFERENCES users(id),
  membership BOOLEAN DEFAULT TRUE, workout BOOLEAN DEFAULT TRUE, diary BOOLEAN DEFAULT TRUE,
  sms_consent_at DATETIME NULL, email_consent_at DATETIME NULL, push_token VARCHAR(255) NULL
);

-- ---------- profile and goals ----------
CREATE TABLE profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id),
  birth_year SMALLINT NULL, sex ENUM('female','male') NULL, height_cm DECIMAL(5,1) NULL,
  units ENUM('metric','imperial') DEFAULT 'metric', experience ENUM('beginner','intermediate','advanced'),
  activity ENUM('sedentary','light','moderate','active'), training_days SET('Mon','Tue','Wed','Thu','Fri','Sat','Sun'),
  workout_minutes SMALLINT, train_where ENUM('royal','other','home'), diet JSON, avoid_foods VARCHAR(200)
);
CREATE TABLE goals (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  kind ENUM('lose','gain','muscle','strength','endurance','maintain','general') NOT NULL,
  is_primary BOOLEAN DEFAULT FALSE, target_weight_kg DECIMAL(5,1) NULL, timeframe VARCHAR(20) NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE body_measurements (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  measured_on DATE NOT NULL, weight_kg DECIMAL(5,1), body_fat_pct DECIMAL(4,1) NULL,
  UNIQUE KEY (user_id, measured_on)
);

-- ---------- equipment and exercises ----------
CREATE TABLE equipment (
  id VARCHAR(12) PRIMARY KEY,                       -- RF-EQ-001
  name VARCHAR(80) NOT NULL, category VARCHAR(60), manufacturer VARCHAR(60) DEFAULT 'Technogym',
  model VARCHAR(80) NULL,                           -- fill only once confirmed on the gym floor
  muscles JSON, setup JSON, technique JSON, safety JSON, photo_url VARCHAR(255), video_url VARCHAR(255),
  active BOOLEAN DEFAULT TRUE
);
CREATE TABLE equipment_qr (                         -- many QR formats can map to one machine
  qr_payload VARCHAR(255) PRIMARY KEY, equipment_id VARCHAR(12) NOT NULL REFERENCES equipment(id)
);
CREATE TABLE exercises (
  id VARCHAR(30) PRIMARY KEY, name VARCHAR(80) NOT NULL, equipment_id VARCHAR(12) NULL REFERENCES equipment(id),
  equipment_needed VARCHAR(80), muscles JSON, movement_pattern VARCHAR(20), is_cardio BOOLEAN DEFAULT FALSE, home_ok BOOLEAN DEFAULT FALSE
);

-- ---------- training records ----------
CREATE TABLE workouts (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  started_at DATETIME NOT NULL, minutes SMALLINT NOT NULL, kind ENUM('strength','cardio','hiit','other'),
  title VARCHAR(80) NULL, location VARCHAR(60), source VARCHAR(30) NOT NULL,     -- app | manual | apple_health | health_connect ...
  source_ext_id VARCHAR(120) NULL,                  -- for de-duplicating synced sessions
  est_kcal SMALLINT NULL, distance_km DECIMAL(6,2) NULL,
  duplicate_of BIGINT NULL, excluded BOOLEAN DEFAULT FALSE,
  UNIQUE KEY (user_id, source, source_ext_id)
);
CREATE TABLE workout_sets (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, workout_id BIGINT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_id VARCHAR(30) NOT NULL REFERENCES exercises(id), set_no TINYINT NOT NULL,
  load_kg DECIMAL(6,2) NULL, reps SMALLINT NULL, seconds SMALLINT NULL, distance_km DECIMAL(6,2) NULL, rest_s SMALLINT NULL
);
CREATE TABLE personal_records (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL, exercise_id VARCHAR(30) NOT NULL,
  kind ENUM('max_load','reps_at_load','volume'), value DECIMAL(8,2), workout_id BIGINT, achieved_on DATE
);
CREATE TABLE form_checks (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  exercise VARCHAR(40), video_object_key VARCHAR(255) NULL,   -- null when processed on-device only
  analysis JSON NULL, model_version VARCHAR(40) NULL, confidence DECIMAL(4,3) NULL,
  consent_upload_at DATETIME NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ---------- nutrition and diary ----------
CREATE TABLE foods (
  id VARCHAR(40) PRIMARY KEY, name VARCHAR(120) NOT NULL, serving_desc VARCHAR(80),
  kcal SMALLINT, protein_g DECIMAL(5,1), carbs_g DECIMAL(5,1), fat_g DECIMAL(5,1), fibre_g DECIMAL(5,1) NULL,
  tags JSON, source VARCHAR(60),                     -- which nutrition database the values came from
  royal_menu BOOLEAN DEFAULT FALSE, menu_price VARCHAR(20) NULL, menu_desc VARCHAR(200) NULL
);
CREATE TABLE diary_entries (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  entry_date DATE NOT NULL, entry_time TIME NOT NULL,
  kind ENUM('food','activity','water') NOT NULL,
  food_id VARCHAR(40) NULL REFERENCES foods(id), title VARCHAR(120), qty DECIMAL(4,2) DEFAULT 1,
  kcal SMALLINT NULL, protein_g DECIMAL(5,1) NULL, carbs_g DECIMAL(5,1) NULL, fat_g DECIMAL(5,1) NULL,
  steps INT NULL, distance_km DECIMAL(6,2) NULL, active_min SMALLINT NULL, water_ml SMALLINT NULL,
  source VARCHAR(30) NOT NULL,                      -- manual | photo | plan | health_connect ...
  photo_object_key VARCHAR(255) NULL,
  KEY ix_user_day (user_id, entry_date)
);
CREATE TABLE wearable_connections (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
  provider ENUM('apple_health','health_connect','garmin','fitbit','phone') NOT NULL,
  scopes JSON, token_encrypted VARBINARY(1024) NULL, connected_at DATETIME, last_sync_at DATETIME NULL, paused BOOLEAN DEFAULT FALSE,
  UNIQUE KEY (user_id, provider)
);

-- ---------- progress ----------
CREATE TABLE progress_scores (
  user_id BIGINT NOT NULL REFERENCES users(id), score_date DATE NOT NULL,
  score TINYINT NOT NULL, components JSON NOT NULL, algorithm_version VARCHAR(10) NOT NULL,
  PRIMARY KEY (user_id, score_date)
);
CREATE TABLE achievements (
  user_id BIGINT NOT NULL REFERENCES users(id), code VARCHAR(40) NOT NULL, earned_on DATE NOT NULL, detail VARCHAR(120),
  PRIMARY KEY (user_id, code)
);

-- ---------- public content ----------
CREATE TABLE class_schedule (
  id INT AUTO_INCREMENT PRIMARY KEY, weekday ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun'),
  start_time TIME, class_name VARCHAR(60), category VARCHAR(30), instructor VARCHAR(60) NULL, active BOOLEAN DEFAULT TRUE
);
