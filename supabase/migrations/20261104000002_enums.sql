-- Mama Haritası — 0002: enum tipleri (docs/backend-contract.md "Enum'lar" ile birebir)

create type public.spot_type         as enum ('food', 'water', 'shelter', 'mixed');
create type public.spot_species      as enum ('cat', 'dog', 'both');
create type public.spot_status       as enum ('fed_recent', 'fed_stale', 'unknown', 'needs_food');
create type public.spot_visibility   as enum ('public', 'fuzzed', 'private');
create type public.checkin_kind      as enum ('fed', 'water', 'need_food', 'need_water', 'broken');
create type public.food_amount       as enum ('low', 'medium', 'full');
create type public.animal_species    as enum ('cat', 'dog');
create type public.animal_sex        as enum ('female', 'male', 'unknown');
create type public.age_estimate      as enum ('baby', 'young', 'adult', 'senior', 'unknown');
create type public.animal_warning    as enum ('do_not_approach', 'skittish', 'may_bite');
create type public.need_type         as enum ('vet', 'neuter', 'vaccine', 'meds', 'shelter', 'water', 'adoption', 'lost_found');
create type public.need_urgency      as enum ('normal', 'urgent');
create type public.need_status       as enum ('open', 'claimed', 'resolved');
create type public.report_target     as enum ('spot', 'animal', 'need', 'checkin', 'photo', 'user');
create type public.report_reason     as enum ('inappropriate', 'spam', 'wrong_location', 'animal_harm', 'harassment', 'other');
create type public.report_status     as enum ('open', 'actioned', 'dismissed');
create type public.moderation_state  as enum ('approved', 'pending', 'rejected');
create type public.follow_target     as enum ('spot', 'animal');
create type public.notification_kind as enum ('need_food_nearby', 'followed_spot_changed', 'guardian_spot_unfed',
                                              'need_resolved', 'thanks_fed', 'donation_delivered');
