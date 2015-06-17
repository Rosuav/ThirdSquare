-- Schema for the accounts database
-- There is precisely one of these, regardless of the number of entities
-- involved in the ticketing scheme. These entities could include toll roads
-- as well as public transport, could span as much geography as can be easily
-- contacted, and can cover multiple jurisdictions as long as currencies are
-- consistent across them all.

create table accounts (id serial primary key,
	contact varchar not null default '', -- Contact name, email address, whatever. Not managed by ThirdSquare directly.
	balance integer not null default 0, -- In cents
	comments varchar not null default ''
);

create table cards (
	-- Each creator is allocated a tiny number - preferably a single digit.
	-- Their ID allocations are then their own.
	creator smallint not null, id integer not null, primary key (creator, id),
	account integer not null references accounts,
	-- Inactive cards are treated as if they no longer exist. Their record is
	-- kept for historical information only.
	active boolean not null default true
);

create table transactions (id serial primary key,
	account integer not null references accounts,
	delta integer not null, -- Change to balance - negative for debit, positive for credit (TODO: Check with talldad)
	reason varchar not null, -- Machine-readable reason for transaction - possibly the ID of a row in some other table, tagged for uniqueness
	comments varchar not null default ''
);

-- The balance of any account must always match its transactions.
-- TODO: Will this check ever become too costly? Would it be better to archive old transactions
-- annually and coalesce them into a single entry for the year's net movement?
-- Note that this check actually can't be implemented as it stands. Currently, we trust the client
-- to maintain this at all times. With a check like this, though, and with client logins permitted
-- to insert into transactions but not update or delete, it would be possible to guarantee that the
-- invoices are indelible and accurate to the balances.
-- alter table accounts add check (balance = (select sum(delta) from transactions where account=accounts.id));
