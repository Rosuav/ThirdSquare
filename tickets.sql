-- Schema for the tickets databases
-- There is one of these for each entity capable of managing tickets.
-- Each one must have a single point of contact with the accounts database,
-- which will be recorded in its HBA file.

-- For convenience, it is possible to have a single database storing accounts
-- and one set of tickets. Consequently, table names must not conflict.


-- Active cards: Cards which have ever been used in this system.
-- When a new physical card is created, it is connected with an account (see accounts.sql),
-- but is not activated for any particular state's usage. On first touch in any given state,
-- it is automatically activated, by inserting a corresponding row into this table.
drop table if exists active_cards;
create table active_cards (id int primary key, -- Must first exist in accounts::cards
	touched_on date, -- NULL if card is touched off, otherwise is the date applicable to the next two fields
	touched_on_target int not null default 0, -- Ignored if touched_on is NULL, otherwise is the stop ID of the current end-of-trip, or the magic value for railway stations
	touched_on_vehicle varchar not null default 0, -- Ignored if touched_on is NULL or if target is the magic value, otherwise is the IP address of the vehicle
);

-- Active tickets. It MAY be worth maintaining eternal history, but the system depends only
-- on retrieving those rows whose expiration is in the future, or at most one day in the
-- past. (If a ticket for earlier today exists, it can be updated into a daily.)
drop table if exists tickets;
create table tickets (id serial primary key,
	card int not null references cards,
	validity int not null, -- For period tickets, is the bitmap of valid zones (always >0). For automated tickets, is 0 minus the number of zones already charged for.
	created timestamp with time zone not null default now(), -- Mainly for statistical purposes
	expiration timestamp with time zone not null
);

-- For automated tickets, this records the zone map. At no time can you ever know *which*
-- zones you have a ticket for, but you can know *how many* you need. The ticket price is
-- therefore scaled to the number of zones, and nothing more.
drop table if exists touches;
create table touches (
	ticket int not null references tickets,
	zone_map int not null, -- Bitmap of valid zones for this touch (copied from locations::zone_map)
	primary key (ticket, zone_map) -- If you touch twice in the exact same zone map, the second one won't affect your ticket in any way, and thus needn't be stored.
);

-- Every place on which your card shall touch must be referenced here. One such location
-- is special; it represents the target of all train journeys (Flinders Street Station),
-- and its ID is known in the system. All other locations are identified simply by their
-- zone maps, and possibly by fixed fees, which aren't currently implemented.
drop table if exists locations;
create table locations (id serial primary key,
	name varchar not null default '', -- Short human-readable name for the location - mainly for debugging
	zone_map int not null default 0, -- Bitmap of valid zones at this location; if 0, zones do not apply (and this probably will have a fixed_fee set).
	fixed_fee int not null default 0 -- Number of cents to charge anyone who touches at this location. Can theoretically be used alongside a zone_map (would create a 'premium' location), but more likely not.
);
