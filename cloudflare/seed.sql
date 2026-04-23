-- SuiSport demo seed. Every row is tagged is_demo=1 so
-- `DELETE FROM <t> WHERE is_demo = 1` resets the entire demo surface.
-- Mirrors the shape of the iOS SocialDataService seed so the app feels
-- identical when pointed at the Worker.

-- ---------- Athletes ----------

INSERT INTO athletes (id, handle, display_name, avatar_tone, banner_tone, verified, tier, total_workouts, followers_count, following_count, bio, location, is_demo) VALUES
('0xdemo_ajoy',   'ajoy',   'Ajoy Ramirez',  'ember',   'ember',   0, 'gold',    312,  4820, 402, 'Brooklyn · sub-3 hunter.',                 'Brooklyn, NY',    1),
('0xdemo_harper', 'harper', 'Harper Lin',    'ocean',   'ocean',   0, 'silver',  184,  1203, 512, 'Triathlete. Coffee evangelist.',           'Berkeley, CA',    1),
('0xdemo_kip_e',  'kip_e',  'Eliud K.',      'forest',  'forest',  1, 'legend', 2204, 540822,  18, 'Breaking 2. Always.',                      'Kaptagat, KE',    1),
('0xdemo_sam',    'sam',    'Sam Patel',     'grape',   'grape',   0, 'silver',  148,   884,  221, 'Weekend warrior. Long runs only.',         'Austin, TX',     1),
('0xdemo_nico',   'nico',   'Nico Ferrer',   'sunset',  'sunset',  0, 'bronze',   52,   244,  198, 'Lifting first, running second.',           'Mexico City',    1),
('0xdemo_teddy',  'teddy',  'Teddy Cho',     'slate',   'slate',   0, 'silver',  210,  1850,  301, 'Track nerd. Stopwatch believer.',          'Seoul',          1),
('0xdemo_ris',    'ris',    'Iris Novak',    'ember',   'ember',   0, 'gold',    402, 12014,  612, 'Trail, then trail, then sometimes road.',  'Ljubljana, SI',  1),
('0xdemo_maya',   'maya',   'Maya Ford',     'ocean',   'ocean',   0, 'bronze',   78,   544,  402, 'Swim-bike-run in that order.',             'Portland, OR',   1),
('0xdemo_jun',    'jun',    'Jun Takahashi', 'grape',   'grape',   1, 'legend',  928, 88224,  122, 'Two-time Olympian.',                       'Tokyo',          1),
('0xdemo_leo',    'leo',    'Leo Marchetti', 'sunset',  'sunset',  0, 'starter',  24,   188,  240, 'Just hit week 1.',                         'Milan',          1),
('0xdemo_zoe',    'zoe',    'Zoe Watkins',   'forest',  'forest',  0, 'silver',  166,  2114,  301, 'Ultrarunning. Mostly type-2 fun.',         'Boulder, CO',    1),
('0xdemo_dre',    'dre',    'Andre Johnson', 'slate',   'slate',   0, 'gold',    288,  4240,  442, 'Hills and heavy metal.',                   'Oakland, CA',    1);

-- A default "me" row so the app has a profile to show before auth.
INSERT INTO athletes (id, handle, display_name, avatar_tone, banner_tone, verified, tier, total_workouts, followers_count, following_count, bio, location, is_demo) VALUES
('0xdemo_me', 'you', 'You', 'sunset', 'sunset', 0, 'starter', 0, 0, 12, 'Running, riding, and earning Sweat.', NULL, 1);

-- ---------- Clubs ----------

INSERT INTO clubs (id, handle, name, tagline, description, hero_tone, member_count, sweat_treasury, weekly_km, is_verified_brand, tags, owner_athlete_id, is_demo) VALUES
('clb_demo_dawn',     'dawn_patrol', 'Brooklyn Dawn Patrol',         '6AM on the bridge. No excuses.',          'Dawn runs, cold coffee, warm hearts. Meet at the Brooklyn Bridge plaza, 6am sharp.', 'sunset', 1248,  14200,    842, 0, '["running","NYC"]',      '0xdemo_ajoy', 1),
('clb_demo_rcc',      'rcc',         'Rapha Cycling Club',           'Ride for the story.',                     'Global members-only cycling club. Sponsored rides, shop access, regional hubs.',     'ocean',  148512, 820000, 98224, 1, '["cycling","brand"]',    NULL,          1),
('clb_demo_founders', 'sui_core',    'SuiSport Founders Circle',     'The earliest athletes on chain.',         'Our OGs. Soulbound membership, founder-drop gear, monthly AMA with the team.',        'grape',  412,   55000,   4120, 1, '["community"]',          NULL,          1),
('clb_demo_marathon', '26point2',    'Marathon Maniacs',             'Because one is never enough.',            'Multi-marathoners unite. Prove your finishes, stake on race PRs.',                    'ember',  8442,  120500, 21440, 0, '["running","marathon"]', NULL,          1),
('clb_demo_trail',    'trailfreaks', 'Trail Freaks',                 'Dirt, elevation, mud. Repeat.',           'Weekend trail crew. Share routes, beta, ride share. Verified elevation only.',        'forest', 3128,  18200,   6880, 0, '["trail","ultra"]',      '0xdemo_ris',  1),
('clb_demo_lift',     'lift_chill',  'Lift & Chill',                 'Heavy lifts, heavier naps.',              'Strength-first club. Program swaps, PR celebrations, weekly check-ins.',              'slate',  2240,  12400,   0,    0, '["strength"]',           NULL,          1);

-- Membership: me in dawn_patrol + founders, Ajoy in dawn_patrol (owner), Iris in trail (owner)
INSERT INTO club_members (club_id, athlete_id, role, is_demo) VALUES
('clb_demo_dawn',     '0xdemo_me',   'member', 1),
('clb_demo_dawn',     '0xdemo_ajoy', 'owner',  1),
('clb_demo_dawn',     '0xdemo_harper','member',1),
('clb_demo_dawn',     '0xdemo_sam',  'member', 1),
('clb_demo_founders', '0xdemo_me',   'member', 1),
('clb_demo_founders', '0xdemo_jun',  'admin',  1),
('clb_demo_trail',    '0xdemo_ris',  'owner',  1),
('clb_demo_trail',    '0xdemo_zoe',  'member', 1);

-- ---------- Challenges ----------

INSERT INTO challenges (id, title, subtitle, sponsor, icon, tone, goal_type, goal_value, stake_sweat, prize_pool_sweat, participants, starts_at, ends_at, is_demo) VALUES
('chal_demo_april100',  'April 100k',        'Run 100 km this month',                                 NULL,                'medal.star.fill',               'ember',  'distance', 100,   0,   0,     28411, unixepoch()-23*86400, unixepoch()+7*86400,  1),
('chal_demo_sub3',      'Sub-3 May',          'Nike x SuiSport marathon prep block',                  '{"name":"Nike"}',    'figure.run.square.stack.fill', 'grape',  'workouts', 24,   50,  125000,  1402, unixepoch()+7*86400,  unixepoch()+38*86400, 1),
('chal_demo_streak',    'Streak Week',        'Log a workout every day this week',                   NULL,                 'flame.fill',                   'sunset', 'time',     7,   25,  18240,   3221, unixepoch()-5*86400,  unixepoch()+2*86400,  1),
('chal_demo_everest',   'Everest in April',   'Climb 8,848 m total',                                 NULL,                 'mountain.2.fill',              'forest', 'distance', 8848, 0,   0,      5120, unixepoch()-23*86400, unixepoch()+7*86400,  1),
('chal_demo_canal',     'Canal Loop TT',      'Beat your best time on the 5k canal segment',         '{"name":"On"}',      'stopwatch.fill',               'ocean',  'workouts', 1,   10,  4200,    288,  unixepoch()-1*86400,  unixepoch()+14*86400, 1);

-- I'm in April100 and Streak Week
INSERT INTO challenge_participants (challenge_id, athlete_id, progress, is_demo) VALUES
('chal_demo_april100', '0xdemo_me', 0.42, 1),
('chal_demo_streak',   '0xdemo_me', 0.71, 1),
('chal_demo_april100', '0xdemo_ajoy', 0.88, 1),
('chal_demo_april100', '0xdemo_harper', 0.55, 1),
('chal_demo_streak',   '0xdemo_teddy', 1.0,  1),
('chal_demo_everest',  '0xdemo_ris', 0.31, 1);

-- ---------- Segments ----------

INSERT INTO segments (id, name, location, distance_meters, elevation_gain_meters, surface, kom_athlete_id, kom_time_seconds, is_demo) VALUES
('seg_demo_bridge',  'Brooklyn Bridge Out-and-Back', 'Brooklyn, NY',   3200,   24, 'road',  '0xdemo_ajoy', 680,  1),
('seg_demo_canal',   'Canal Loop 5k',                'Amsterdam, NL',  5000,   4,  'road',  '0xdemo_jun',  922,  1),
('seg_demo_hawk',    'Hawk Hill Climb',              'Marin, CA',      2800,  260, 'road',  '0xdemo_dre',  728,  1),
('seg_demo_peak',    'Grouse Grind',                 'Vancouver, BC',  2900,  853, 'trail', '0xdemo_ris', 1980,  1),
('seg_demo_bay',     'Bay Bridge Return',            'Oakland, CA',    6100,   42, 'road',  '0xdemo_harper', 1344, 1);

-- A few recorded efforts
INSERT INTO segment_efforts (id, segment_id, athlete_id, time_seconds, achieved_at, is_demo) VALUES
('eff_demo_1', 'seg_demo_bridge', '0xdemo_ajoy',   680,  unixepoch()-2*86400,  1),
('eff_demo_2', 'seg_demo_bridge', '0xdemo_harper', 712,  unixepoch()-4*86400,  1),
('eff_demo_3', 'seg_demo_bridge', '0xdemo_me',     744,  unixepoch()-9*86400,  1),
('eff_demo_4', 'seg_demo_canal',  '0xdemo_jun',    922,  unixepoch()-16*86400, 1),
('eff_demo_5', 'seg_demo_canal',  '0xdemo_teddy',  948,  unixepoch()-3*86400,  1),
('eff_demo_6', 'seg_demo_hawk',   '0xdemo_dre',    728,  unixepoch()-1*86400,  1);

INSERT INTO segment_stars (segment_id, athlete_id) VALUES
('seg_demo_bridge', '0xdemo_me'),
('seg_demo_canal',  '0xdemo_me');

-- ---------- Trophies ----------

INSERT INTO trophies (id, title, subtitle, icon, category, rarity, gradient_tones, is_demo) VALUES
('tro_demo_first_mile',   'First Mile',           'Your very first verified workout.',        'figure.walk.motion',      'milestone', 'common',    '["sunset"]', 1),
('tro_demo_100k',         'Centurion',            '100 km logged on-chain.',                  'flag.checkered',          'milestone', 'rare',      '["ember","grape"]', 1),
('tro_demo_streak_7',     'Streak Week',          '7 days in a row. No excuses.',             'flame.fill',              'streak',    'common',    '["sunset","ember"]', 1),
('tro_demo_streak_30',    'Forged in Fire',       '30-day streak. Legend behavior.',          'flame.circle.fill',       'streak',    'epic',      '["ember"]', 1),
('tro_demo_kom_first',    'First KOM',            'Claimed your first segment crown.',        'crown.fill',              'segment',   'rare',      '["ocean"]', 1),
('tro_demo_mar_sub3',     'Sub-3 Marathon',       'Proved it on-chain. Forever.',             'timer',                   'challenge', 'legendary', '["grape","ocean"]', 1),
('tro_demo_half',         'Half Crusher',         'Completed a verified half marathon.',      'medal.star.fill',         'milestone', 'rare',      '["forest"]', 1),
('tro_demo_founders',     'Founders Edition',     'Minted in the first 1,000 athletes.',      'sparkles',                'badge',     'legendary', '["grape","sunset"]', 1);

-- My unlocked trophies (3 for showcase)
INSERT INTO trophy_unlocks (athlete_id, trophy_id, progress, earned_at, showcase_index, is_demo) VALUES
('0xdemo_me', 'tro_demo_first_mile', 1.0, unixepoch()-40*86400, 0, 1),
('0xdemo_me', 'tro_demo_streak_7',   1.0, unixepoch()-12*86400, 1, 1),
('0xdemo_me', 'tro_demo_founders',   1.0, unixepoch()-45*86400, 2, 1),
('0xdemo_me', 'tro_demo_100k',       0.42, NULL,               NULL, 1),
('0xdemo_me', 'tro_demo_streak_30',  0.33, NULL,               NULL, 1),
('0xdemo_me', 'tro_demo_kom_first',  0.0,  NULL,               NULL, 1),
('0xdemo_me', 'tro_demo_mar_sub3',   0.0,  NULL,               NULL, 1),
('0xdemo_me', 'tro_demo_half',       0.62, NULL,               NULL, 1);

-- ---------- Shoes ----------

INSERT INTO shoes (id, athlete_id, brand, model, nickname, tone, miles_used, miles_total, retired, started_at, is_demo) VALUES
('shoe_demo_vf3',   '0xdemo_me', 'Nike',   'Vaporfly 3',      'Race shoes',      'ember',  142, 400, 0, unixepoch()-90*86400, 1),
('shoe_demo_clif',  '0xdemo_me', 'Hoka',   'Clifton 9',       'Long run shoes',  'ocean',  612, 700, 0, unixepoch()-220*86400,1),
('shoe_demo_edge',  '0xdemo_me', 'Saucony','Endorphin Edge',  NULL,              'forest', 284, 600, 0, unixepoch()-120*86400,1);

-- ---------- Personal records ----------

INSERT INTO personal_records (athlete_id, label, distance_meters, best_time_seconds, achieved_at, is_demo) VALUES
('0xdemo_me', '5K',   5000,    1380,   unixepoch()-18*86400, 1),
('0xdemo_me', '10K',  10000,   2940,   unixepoch()-40*86400, 1),
('0xdemo_me', 'Half', 21097,   7120,   unixepoch()-92*86400, 1),
('0xdemo_me', 'Full', 42195,   NULL,   NULL,                 1);

-- ---------- Streak + sweat points ----------

INSERT INTO streaks (athlete_id, current_days, longest_days, weekly_streak_weeks, staked_sweat, multiplier, is_demo) VALUES
('0xdemo_me', 5, 14, 3, 25, 1.15, 1);

INSERT INTO sweat_points (athlete_id, total, weekly, is_demo) VALUES
('0xdemo_me', 4280, 220, 1),
('0xdemo_ajoy', 48210, 1420, 1),
('0xdemo_harper', 18440, 620, 1),
('0xdemo_jun', 210420, 2840, 1);

-- ---------- Workouts + feed items (demo activity stream) ----------

INSERT INTO workouts (id, athlete_id, type, start_date, duration_seconds, distance_meters, energy_kcal, avg_heart_rate, points, verified, is_demo) VALUES
('w_demo_1', '0xdemo_ajoy',   'run',  unixepoch()-3*3600,   3120, 10200, 520, 148, 120, 1, 1),
('w_demo_2', '0xdemo_harper', 'ride', unixepoch()-6*3600,   4800, 42000, 780, 138, 140, 1, 1),
('w_demo_3', '0xdemo_jun',    'run',  unixepoch()-9*3600,   5400, 21100, 920, 155, 180, 1, 1),
('w_demo_4', '0xdemo_ris',    'hike', unixepoch()-26*3600,  7200, 12400, 840, 128, 110, 1, 1),
('w_demo_5', '0xdemo_dre',    'run',  unixepoch()-32*3600,  3600, 11800, 640, 152, 130, 1, 1),
('w_demo_6', '0xdemo_teddy',  'run',  unixepoch()-44*3600,  2400,  8000, 420, 148,  90, 1, 1),
('w_demo_7', '0xdemo_sam',    'run',  unixepoch()-52*3600,  4200, 14200, 720, 144, 150, 1, 1),
('w_demo_8', '0xdemo_zoe',    'run',  unixepoch()-60*3600,  9000, 28000,1100, 134, 230, 1, 1),
('w_demo_9', '0xdemo_nico',   'walk', unixepoch()-72*3600,  2700,  5200, 260, 108,  40, 1, 1),
('w_demo_10','0xdemo_maya',   'run',  unixepoch()-80*3600,  3000,  9800, 480, 142, 100, 1, 1);

INSERT INTO feed_items (id, athlete_id, workout_id, title, caption, map_preview_seed, kudos_count, comment_count, tipped_sweat, is_demo) VALUES
('fi_demo_1',  '0xdemo_ajoy',   'w_demo_1',  'Morning run',      'Clean miles. Negative split.',         11,  24, 3, 4, 1),
('fi_demo_2',  '0xdemo_harper', 'w_demo_2',  'Afternoon ride',   'Hills. My legs hate me.',              42,  18, 1, 0, 1),
('fi_demo_3',  '0xdemo_jun',    'w_demo_3',  'Evening run',      'Easy Zone 2. No complaints.',         112,  92, 8, 22, 1),
('fi_demo_4',  '0xdemo_ris',    'w_demo_4',  'Afternoon hike',    NULL,                                 244,  12, 0, 0, 1),
('fi_demo_5',  '0xdemo_dre',    'w_demo_5',  'Morning run',      'Hills, again. 5am squad.',            388,  31, 4, 6, 1),
('fi_demo_6',  '0xdemo_teddy',  'w_demo_6',  'Evening run',      'Track session. Coach happy.',         402,  14, 1, 0, 1),
('fi_demo_7',  '0xdemo_sam',    'w_demo_7',  'Weekend long run', 'Peak week of block 2.',               544,  22, 2, 3, 1),
('fi_demo_8',  '0xdemo_zoe',    'w_demo_8',  'Morning run',      'Rainy one. Didn''t miss a beat.',     611,  28, 3, 0, 1),
('fi_demo_9',  '0xdemo_nico',   'w_demo_9',  'Afternoon walk',   'Recovery day.',                       708,   8, 0, 0, 1),
('fi_demo_10', '0xdemo_maya',   'w_demo_10', 'Afternoon run',    'Coach Bennett told me to chill.',     822,  16, 2, 1, 1);

-- Kudos (unique by feed+athlete)
INSERT INTO kudos (id, feed_item_id, athlete_id, amount_sweat, is_demo) VALUES
('k_demo_1',  'fi_demo_1', '0xdemo_harper', 0, 1),
('k_demo_2',  'fi_demo_1', '0xdemo_jun',    2, 1),
('k_demo_3',  'fi_demo_1', '0xdemo_me',     0, 1),
('k_demo_4',  'fi_demo_3', '0xdemo_ajoy',   5, 1),
('k_demo_5',  'fi_demo_3', '0xdemo_ris',    0, 1),
('k_demo_6',  'fi_demo_3', '0xdemo_dre',    3, 1),
('k_demo_7',  'fi_demo_5', '0xdemo_jun',    4, 1),
('k_demo_8',  'fi_demo_7', '0xdemo_me',     1, 1),
('k_demo_9',  'fi_demo_10','0xdemo_harper', 0, 1);

-- Comments
INSERT INTO comments (id, feed_item_id, athlete_id, body, is_demo) VALUES
('c_demo_1', 'fi_demo_1', '0xdemo_harper','Sick pace 🔥',             1),
('c_demo_2', 'fi_demo_1', '0xdemo_jun',   'Tip incoming',             1),
('c_demo_3', 'fi_demo_3', '0xdemo_ajoy',  'Absolute unit',            1),
('c_demo_4', 'fi_demo_5', '0xdemo_zoe',   'Easy day 💀',              1),
('c_demo_5', 'fi_demo_7', '0xdemo_nico',  'You animal',               1),
('c_demo_6', 'fi_demo_10','0xdemo_teddy', 'Catch up to me lol',       1);

-- ---------- Follows ----------

INSERT INTO follows (follower_id, followee_id, is_demo) VALUES
('0xdemo_me',   '0xdemo_ajoy',  1),
('0xdemo_me',   '0xdemo_harper',1),
('0xdemo_me',   '0xdemo_jun',   1),
('0xdemo_me',   '0xdemo_ris',   1),
('0xdemo_me',   '0xdemo_dre',   1),
('0xdemo_ajoy', '0xdemo_me',    1),
('0xdemo_harper','0xdemo_me',   1);

UPDATE schema_meta SET value = '1', updated_at = unixepoch() WHERE key = 'demo_seeded';
