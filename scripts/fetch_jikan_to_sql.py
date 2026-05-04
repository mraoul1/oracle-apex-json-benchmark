#!/usr/bin/env python3
"""
fetch_jikan_to_sql.py
=====================
Fetches anime data from the Jikan API (MyAnimeList) and generates a ready-to-run
Oracle INSERT script for the ANI_ schema.

USAGE:
    python3 fetch_jikan_to_sql.py

OUTPUT:
    02_ani_data_inserts.sql   (INSERT statements for all ANI_ tables)

REQUIREMENTS:
    pip install requests

CONFIGURATION:
    Change MAX_PAGES below. Each page = 25 anime.
    20 pages = 500 anime (top 500 on MAL by score).
    Jikan rate limit: 3 req/sec, 60/min. Script waits 1 sec between pages.
"""

import requests
import time
import re
import sys
from datetime import datetime

# ── Configuration ─────────────────────────────────────────────────────────────
MAX_PAGES   = 20          # 20 pages × 25 = 500 anime
OUTPUT_FILE = '02_ani_data_inserts.sql'
BASE_URL    = 'https://api.jikan.moe/v4/top/anime'
# ──────────────────────────────────────────────────────────────────────────────


def esc(value):
    """Escape a string value for Oracle SQL: wrap in quotes, escape single quotes."""
    if value is None:
        return 'NULL'
    value = str(value).replace("'", "''")
    return f"'{value}'"


def num(value):
    """Return a numeric value or NULL."""
    if value is None:
        return 'NULL'
    try:
        return str(float(value)) if '.' in str(value) else str(int(value))
    except (ValueError, TypeError):
        return 'NULL'


def fetch_page(page):
    """Fetch one page from Jikan, retry once on rate limit."""
    url = f"{BASE_URL}?page={page}"
    for attempt in range(3):
        try:
            r = requests.get(url, headers={'Accept': 'application/json'}, timeout=20)
            if r.status_code == 200:
                return r.json().get('data', [])
            elif r.status_code == 429:
                print(f"  Rate limited on page {page}, waiting 5s...")
                time.sleep(5)
            else:
                print(f"  HTTP {r.status_code} on page {page}, skipping.")
                return []
        except requests.RequestException as e:
            print(f"  Error on page {page}: {e}")
            time.sleep(2)
    return []


def main():
    print(f"Fetching {MAX_PAGES} pages from Jikan API...")

    all_anime   = []
    all_genres  = {}   # name -> genre_id (1-based)
    all_studios = {}   # name -> studio_id (1-based)
    all_seasons = {}   # (year, season) -> season_id (1-based)

    for page in range(1, MAX_PAGES + 1):
        print(f"  Page {page}/{MAX_PAGES}...", end=' ')
        data = fetch_page(page)
        print(f"{len(data)} anime")
        all_anime.extend(data)
        time.sleep(1)   # respect rate limit

    print(f"\nTotal anime fetched: {len(all_anime)}")

    # ── Collect lookup values ──────────────────────────────────────────────────
    for a in all_anime:
        for g in a.get('genres', []):
            name = g.get('name')
            if name and name not in all_genres:
                all_genres[name] = len(all_genres) + 1

        for s in a.get('studios', []):
            name = s.get('name')
            if name and name not in all_studios:
                all_studios[name] = len(all_studios) + 1

        year   = a.get('year')
        season = a.get('season')
        if year and season:
            key = (int(year), season.upper())
            if key not in all_seasons:
                all_seasons[key] = len(all_seasons) + 1

    print(f"Genres:  {len(all_genres)}")
    print(f"Studios: {len(all_studios)}")
    print(f"Seasons: {len(all_seasons)}")

    # ── Write SQL file ─────────────────────────────────────────────────────────
    print(f"\nWriting {OUTPUT_FILE}...")

    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:

        f.write(f"""-- =============================================================================
-- FILE: {OUTPUT_FILE}
-- GENERATED: {datetime.now().strftime('%Y-%m-%d %H:%M')}
-- SOURCE: Jikan API v4 (MyAnimeList) - top anime, {MAX_PAGES} pages
-- ANIME: {len(all_anime)} rows
-- RUN AFTER: 01_ani_schema_ddl.sql
-- =============================================================================

SET DEFINE OFF
SET FEEDBACK OFF

-- Clean slate
TRUNCATE TABLE ani_anime_genre;
TRUNCATE TABLE ani_character;
TRUNCATE TABLE ani_review;
TRUNCATE TABLE ani_anime;
TRUNCATE TABLE ani_season;
TRUNCATE TABLE ani_studio;
TRUNCATE TABLE ani_genre;

""")

        # GENRES
        f.write('-- GENRES\n')
        for name, gid in sorted(all_genres.items(), key=lambda x: x[1]):
            f.write(f"INSERT INTO ani_genre (genre_id, genre_name) "
                    f"VALUES ({gid}, {esc(name)});\n")
        f.write('COMMIT;\n\n')

        # STUDIOS
        f.write('-- STUDIOS\n')
        for name, sid in sorted(all_studios.items(), key=lambda x: x[1]):
            f.write(f"INSERT INTO ani_studio (studio_id, studio_name, country) "
                    f"VALUES ({sid}, {esc(name)}, 'Japan');\n")
        f.write('COMMIT;\n\n')

        # SEASONS
        f.write('-- SEASONS\n')
        for (year, season), sid in sorted(all_seasons.items(), key=lambda x: x[1]):
            f.write(f"INSERT INTO ani_season (season_id, season_year, season_name) "
                    f"VALUES ({sid}, {year}, {esc(season)});\n")
        f.write('COMMIT;\n\n')

        # ANIME
        f.write('-- ANIME\n')
        inserted_mal_ids = set()
        anime_id_map = {}   # mal_id -> anime_id (1-based)

        for a in all_anime:
            mal_id = a.get('mal_id')
            if not mal_id or mal_id in inserted_mal_ids:
                continue
            inserted_mal_ids.add(mal_id)

            anime_id = len(anime_id_map) + 1
            anime_id_map[mal_id] = anime_id

            title    = a.get('title', '')
            title_jp = a.get('title_japanese', '')
            mtype    = a.get('type') or 'UNKNOWN'
            mtype    = mtype if mtype in ('TV','MOVIE','OVA','ONA','SPECIAL','MUSIC') else 'UNKNOWN'
            episodes = num(a.get('episodes'))
            status_raw = a.get('status', '')
            if 'Finished'  in status_raw: status = 'FINISHED'
            elif 'Currently' in status_raw: status = 'AIRING'
            elif 'Not yet'   in status_raw: status = 'NOT_YET_AIRED'
            else: status = 'UNKNOWN'
            score      = num(a.get('score'))
            scored_by  = num(a.get('scored_by'))
            rank       = num(a.get('rank'))
            popularity = num(a.get('popularity'))
            synopsis   = (a.get('synopsis') or '')[:4000]
            image_url  = a.get('images', {}).get('jpg', {}).get('image_url', '')

            # Resolve season_id
            year   = a.get('year')
            season = a.get('season')
            season_id = 'NULL'
            if year and season:
                key = (int(year), season.upper())
                if key in all_seasons:
                    season_id = str(all_seasons[key])

            # Resolve studio_id (first studio only)
            studios   = a.get('studios', [])
            studio_id = 'NULL'
            if studios:
                sname = studios[0].get('name')
                if sname and sname in all_studios:
                    studio_id = str(all_studios[sname])

            f.write(
                f"INSERT INTO ani_anime ("
                f"anime_id, mal_id, title, title_japanese, media_type, episodes, "
                f"status, score, scored_by, rank, popularity, synopsis, "
                f"season_id, studio_id, image_url) VALUES ("
                f"{anime_id}, {mal_id}, {esc(title)}, {esc(title_jp)}, "
                f"{esc(mtype)}, {episodes}, {esc(status)}, {score}, {scored_by}, "
                f"{rank}, {popularity}, {esc(synopsis)}, "
                f"{season_id}, {studio_id}, {esc(image_url)});\n"
            )

        f.write('COMMIT;\n\n')

        # ANIME_GENRE bridge
        f.write('-- ANIME_GENRE\n')
        for a in all_anime:
            mal_id = a.get('mal_id')
            if mal_id not in anime_id_map:
                continue
            anime_id = anime_id_map[mal_id]
            seen = set()
            for g in a.get('genres', []):
                gname = g.get('name')
                if gname and gname in all_genres:
                    gid = all_genres[gname]
                    if gid not in seen:
                        seen.add(gid)
                        f.write(
                            f"INSERT INTO ani_anime_genre (anime_id, genre_id) "
                            f"VALUES ({anime_id}, {gid});\n"
                        )
        f.write('COMMIT;\n\n')

        f.write('SET FEEDBACK ON\n')
        f.write(f"-- Load complete: {len(anime_id_map)} anime inserted\n")

    print(f"Done. Run {OUTPUT_FILE} in your Oracle schema.")


if __name__ == '__main__':
    main()
