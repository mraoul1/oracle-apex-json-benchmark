-- =============================================================================
-- FILE: 01_ani_schema_ddl.sql
-- PURPOSE: Create the ANI_ schema objects for the ORDS JSON benchmark
-- COMPATIBILITY: Oracle 19c+
-- USAGE: Run as a privileged user or as the target schema owner
-- =============================================================================


-- -----------------------------------------------------------------------------
-- LOOKUP / REFERENCE TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE ani_genre (
    genre_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genre_name  VARCHAR2(50)   NOT NULL,
    CONSTRAINT ani_genre_uk UNIQUE (genre_name)
);

CREATE TABLE ani_studio (
    studio_id   NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    studio_name VARCHAR2(100)  NOT NULL,
    country     VARCHAR2(50),
    founded_year NUMBER(4),
    CONSTRAINT ani_studio_uk UNIQUE (studio_name)
);

CREATE TABLE ani_season (
    season_id   NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    season_year NUMBER(4)      NOT NULL,
    season_name VARCHAR2(10)   NOT NULL,  -- WINTER / SPRING / SUMMER / FALL
    CONSTRAINT ani_season_uk UNIQUE (season_year, season_name),
    CONSTRAINT ani_season_name_ck CHECK (season_name IN ('WINTER','SPRING','SUMMER','FALL'))
);


-- -----------------------------------------------------------------------------
-- MAIN ENTITY TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE ani_anime (
    anime_id        NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mal_id          NUMBER,                          -- MyAnimeList ID (optional, for reference)
    title           VARCHAR2(400)   NOT NULL,
    title_japanese  VARCHAR2(400),
    media_type      VARCHAR2(20),                    -- TV / MOVIE / OVA / ONA / SPECIAL
    episodes        NUMBER(4),
    status          VARCHAR2(30),                    -- FINISHED / AIRING / NOT_YET_AIRED
    score           NUMBER(4,2),                     -- 0.00 – 10.00
    scored_by       NUMBER,                          -- number of users who scored
    rank            NUMBER,
    popularity      NUMBER,
    synopsis        VARCHAR2(4000),
    season_id       NUMBER         REFERENCES ani_season(season_id),
    studio_id       NUMBER         REFERENCES ani_studio(studio_id),
    image_url       VARCHAR2(500),
    created_at      DATE           DEFAULT SYSDATE,
    CONSTRAINT ani_anime_type_ck  CHECK (media_type IN ('TV','MOVIE','OVA','ONA','SPECIAL','MUSIC','UNKNOWN')),
    CONSTRAINT ani_anime_status_ck CHECK (status IN ('FINISHED','AIRING','NOT_YET_AIRED','UNKNOWN'))
);

CREATE TABLE ani_anime_genre (
    anime_id  NUMBER  NOT NULL REFERENCES ani_anime(anime_id),
    genre_id  NUMBER  NOT NULL REFERENCES ani_genre(genre_id),
    CONSTRAINT ani_anime_genre_pk PRIMARY KEY (anime_id, genre_id)
);

CREATE TABLE ani_character (
    character_id    NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    anime_id        NUMBER          NOT NULL REFERENCES ani_anime(anime_id),
    char_name       VARCHAR2(200)   NOT NULL,
    role            VARCHAR2(20),                    -- MAIN / SUPPORTING
    favourites      NUMBER,
    image_url       VARCHAR2(500),
    CONSTRAINT ani_char_role_ck CHECK (role IN ('MAIN','SUPPORTING'))
);

CREATE TABLE ani_review (
    review_id       NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    anime_id        NUMBER          NOT NULL REFERENCES ani_anime(anime_id),
    reviewer_alias  VARCHAR2(100)   NOT NULL,
    score           NUMBER(2)       NOT NULL,        -- 1-10
    review_text     VARCHAR2(4000),
    helpful_count   NUMBER          DEFAULT 0,
    review_date     DATE            DEFAULT SYSDATE,
    CONSTRAINT ani_review_score_ck CHECK (score BETWEEN 1 AND 10)
);


-- -----------------------------------------------------------------------------
-- INDEXES  (support the typical query patterns used in the REST handlers)
-- -----------------------------------------------------------------------------

CREATE INDEX ani_anime_score_idx      ON ani_anime(score DESC);
CREATE INDEX ani_anime_season_idx     ON ani_anime(season_id);
CREATE INDEX ani_anime_studio_idx     ON ani_anime(studio_id);
CREATE INDEX ani_anime_status_idx     ON ani_anime(status);
CREATE INDEX ani_anime_genre_aid_idx  ON ani_anime_genre(anime_id);
CREATE INDEX ani_anime_genre_gid_idx  ON ani_anime_genre(genre_id);
CREATE INDEX ani_char_anime_idx       ON ani_character(anime_id);
CREATE INDEX ani_review_anime_idx     ON ani_review(anime_id);
CREATE INDEX ani_review_date_idx      ON ani_review(review_date DESC);


-- -----------------------------------------------------------------------------
-- COMMENTS
-- -----------------------------------------------------------------------------

COMMENT ON TABLE ani_anime        IS 'Core anime catalogue – one row per series/movie';
COMMENT ON TABLE ani_genre        IS 'Genre lookup (Action, Comedy, Drama, …)';
COMMENT ON TABLE ani_studio       IS 'Animation studio reference';
COMMENT ON TABLE ani_season       IS 'Broadcast season (year + quarter)';
COMMENT ON TABLE ani_anime_genre  IS 'Many-to-many: anime ↔ genres';
COMMENT ON TABLE ani_character    IS 'Notable characters per anime';
COMMENT ON TABLE ani_review       IS 'User reviews with score and free text';
