-- Schema for the tickets databases
-- There is one of these for each entity capable of managing tickets.
-- Each one must have a single point of contact with the accounts database,
-- which will be recorded in its HBA file.

-- For convenience, it is possible to have a single database storing accounts
-- and one set of tickets. Consequently, table names must not conflict.

create table active_cards (id integer primary key, -- Must first exist in accounts::cards
	touched_on ????, -- NULL if card is touched off, otherwise is the place to presume a touch-off.
);

create table tickets (id serial primary key,
	card integer not null, -- references accounts::cards but not enforced in the database
	validity smallint not null, -- Zone or whatever else defines where this is valid
	created timestamp with time zone not null default now(), -- Mainly for statistical purposes
	expiration timestamp with time zone not null
);
