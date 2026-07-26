-- 2026-07-23 (vucko "nur Emoji, kein Text bei Reaktionen"): serverseitiger
-- Backstop. Der Dart-Client validiert bereits (EmojiGuard.isSingleEmoji),
-- aber RLS erlaubt bisher jeden Text als "Reaktion" — dieser CHECK verhindert
-- zumindest offensichtlichen Missbrauch (z.B. ein ganzer Absatz Text als
-- "Reaktion"), auch wenn ein voller Unicode-Emoji-Property-Check in
-- Postgres nicht eingebaut ist.
alter table public.community_message_reactions
  add constraint community_message_reactions_emoji_len
  check (char_length(emoji) between 1 and 16);

alter table public.group_message_reactions
  add constraint group_message_reactions_emoji_len
  check (char_length(emoji) between 1 and 16);
