-- p8lb schema

create table if not exists scores (
  game_id    text not null,
  user_id    text not null,   -- itch ID
  username   text not null,   -- cached for display
  score      real not null,   -- 16.16 float
  updated_at integer not null,
  primary key (game_id, user_id)
);

create index if not exists idx_scores_desc
  on scores (game_id, score desc, updated_at asc);
