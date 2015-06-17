-- Schema for the tickets databases
-- There is one of these for each entity capable of managing tickets.
-- Each one must have a single point of contact with the accounts database,
-- which will be recorded in its HBA file.

create table cards (id serial primary key,
	contact varchar not null default '' -- As with account contacts, this could be email address, phone, whatever. Not managed by ThirdSquare.
);

create table tickets (id serial primary key,
	card integer not null references cards,
	validity smallint not null, -- Zone or whatever else defines where this is valid
	created timestamp with time zone not null default now(), -- Mainly for statistical purposes
	expiration timestamp with time zone not null
);
