-- =============================================================================
-- FILE: ani_ords_handler_simple.sql
-- PURPOSE: ORDS handler source - paste into APEX REST Services handler.
--          All logic is in ani_api package. Handler just converts params
--          and calls the right function.
-- =============================================================================

DECLARE
    l_result CLOB;
    l_limit  NUMBER;
    l_method VARCHAR2(10);
BEGIN
    l_limit  := TO_NUMBER(NVL(:lim, '100'));
    l_method := NVL(:method, 'sql');

    IF l_method = 'loop' THEN
        l_result := ani_api.get_anime_loop(l_limit);
    ELSE
        l_result := ani_api.get_anime_sql(l_limit);
    END IF;

    :status_code  := 200;
    :content_type := 'application/json';
    HTP.P(l_result);

EXCEPTION
    WHEN OTHERS THEN
        :status_code := 500;
        HTP.P('{"error":"' || REPLACE(SQLERRM, '"', '''') || '"}');
END;
