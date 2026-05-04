-- =============================================================================
-- FILE: ani_api_pkg.sql
-- PURPOSE: Package containing the JSON builder functions for the benchmark.
--          Test directly in SQL Workshop, then call from ORDS handler.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PACKAGE SPEC
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE ani_api AS

    -- Method 1: Pure SQL with JSON_OBJECT + JSON_ARRAYAGG
    FUNCTION get_anime_sql (p_limit IN NUMBER DEFAULT 100) RETURN CLOB;

    -- Method 2: PL/SQL loop with JSON_OBJECT_T
    FUNCTION get_anime_loop (p_limit IN NUMBER DEFAULT 100) RETURN CLOB;

END ani_api;
/


-- -----------------------------------------------------------------------------
-- PACKAGE BODY
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY ani_api AS

    -- =========================================================================
    -- METHOD 1: Pure SQL
    -- =========================================================================
    FUNCTION get_anime_sql (p_limit IN NUMBER DEFAULT 100) RETURN CLOB AS
        l_result CLOB;
    BEGIN
        SELECT JSON_OBJECT(
                   'status' VALUE 'Ok',
                   'count'  VALUE COUNT(*),
                   'anime'  VALUE JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'animeId'  VALUE a.anime_id,
                           'title'    VALUE a.title,
                           'titleJp'  VALUE a.title_japanese,
                           'type'     VALUE a.media_type,
                           'episodes' VALUE a.episodes,
                           'status'   VALUE a.status,
                           'score'    VALUE a.score,
                           'scoredBy' VALUE a.scored_by,
                           'synopsis' VALUE a.synopsis,
                           'studio'   VALUE JSON_OBJECT(
                                          'id'   VALUE s.studio_id,
                                          'name' VALUE s.studio_name
                                          ABSENT ON NULL
                                      ),
                           'season'   VALUE JSON_OBJECT(
                                          'year' VALUE se.season_year,
                                          'name' VALUE se.season_name
                                          ABSENT ON NULL
                                      ),
                           'genres'   VALUE g.genre_list
                           ABSENT ON NULL
                       )
                       ORDER BY a.score DESC
                       RETURNING CLOB
                   )
                   RETURNING CLOB
               )
        INTO l_result
        FROM (SELECT * FROM ani_anime WHERE ROWNUM <= p_limit) a
        LEFT JOIN ani_studio s  ON s.studio_id  = a.studio_id
        LEFT JOIN ani_season se ON se.season_id = a.season_id
        OUTER APPLY (
            SELECT JSON_ARRAYAGG(
                       g2.genre_name
                       ORDER BY g2.genre_name
                       RETURNING CLOB
                   ) AS genre_list
            FROM   ani_anime_genre ag
            JOIN   ani_genre       g2 ON g2.genre_id = ag.genre_id
            WHERE  ag.anime_id = a.anime_id
        ) g;

        RETURN l_result;
    END get_anime_sql;


    -- =========================================================================
    -- METHOD 2: PL/SQL JSON_OBJECT_T loop
    -- =========================================================================
    FUNCTION get_anime_loop (p_limit IN NUMBER DEFAULT 100) RETURN CLOB AS
        l_root       JSON_OBJECT_T := JSON_OBJECT_T();
        l_anime_arr  JSON_ARRAY_T  := JSON_ARRAY_T();
        l_anime_obj  JSON_OBJECT_T;
        l_studio_obj JSON_OBJECT_T;
        l_season_obj JSON_OBJECT_T;
        l_genre_arr  JSON_ARRAY_T;
        l_cnt        NUMBER := 0;

        CURSOR c_anime IS
            SELECT a.anime_id,
                   a.title,
                   a.title_japanese,
                   a.media_type,
                   a.episodes,
                   a.status,
                   a.score,
                   a.scored_by,
                   a.synopsis,
                   s.studio_id,
                   s.studio_name,
                   se.season_year,
                   se.season_name
            FROM   (SELECT * FROM ani_anime WHERE ROWNUM <= p_limit) a
            LEFT JOIN ani_studio s  ON s.studio_id  = a.studio_id
            LEFT JOIN ani_season se ON se.season_id = a.season_id
            ORDER  BY a.score DESC;

        CURSOR c_genres (p_anime_id NUMBER) IS
            SELECT g.genre_name
            FROM   ani_anime_genre ag
            JOIN   ani_genre       g ON g.genre_id = ag.genre_id
            WHERE  ag.anime_id = p_anime_id;
    BEGIN
        FOR r IN c_anime LOOP
            l_anime_obj := JSON_OBJECT_T();
            l_cnt       := l_cnt + 1;

            l_anime_obj.put('animeId',  r.anime_id);
            l_anime_obj.put('title',    r.title);
            l_anime_obj.put('titleJp',  r.title_japanese);
            l_anime_obj.put('type',     r.media_type);
            l_anime_obj.put('episodes', r.episodes);
            l_anime_obj.put('status',   r.status);
            l_anime_obj.put('score',    r.score);
            l_anime_obj.put('scoredBy', r.scored_by);
            l_anime_obj.put('synopsis', r.synopsis);

            l_studio_obj := JSON_OBJECT_T();
            l_studio_obj.put('id',   r.studio_id);
            l_studio_obj.put('name', r.studio_name);
            l_anime_obj.put('studio', l_studio_obj);

            l_season_obj := JSON_OBJECT_T();
            l_season_obj.put('year', r.season_year);
            l_season_obj.put('name', r.season_name);
            l_anime_obj.put('season', l_season_obj);

            l_genre_arr := JSON_ARRAY_T();
            FOR g IN c_genres(r.anime_id) LOOP
                l_genre_arr.append(g.genre_name);
            END LOOP;
            l_anime_obj.put('genres', l_genre_arr);

            l_anime_arr.append(l_anime_obj);
        END LOOP;

        l_root.put('status', 'Ok');
        l_root.put('count',  l_cnt);
        l_root.put('anime',  l_anime_arr);

        RETURN l_root.to_clob;
    END get_anime_loop;

END ani_api;
/


-- =============================================================================
-- TEST IN SQL WORKSHOP
-- Run these one at a time to verify both methods work before touching ORDS.
-- =============================================================================

-- Test method 1 (SQL) with 10 rows
SELECT ani_api.get_anime_sql(10) FROM dual;

-- Test method 2 (loop) with 10 rows
SELECT ani_api.get_anime_loop(10) FROM dual;

-- If both work, test with larger sets
SELECT ani_api.get_anime_sql(100)  FROM dual;
SELECT ani_api.get_anime_loop(100) FROM dual;
