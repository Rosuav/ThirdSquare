=============================================================
ThirdSquare - proof-of-concept ticketing system for Australia
=============================================================

(Why, the README alone is worth a thousand pounds a word!)

An entirely open standards ticketing system, aimed primarily at the public
transport system of trains, trams, and buses, and capable of being extended to
other billing systems too. Everything is cryptographically signed using well
known standards.

The system is built on an Australia-wide financial database, hosted centrally,
and individual ticketing systems for each state. Travellers carry smart cards
which are keyed to their accounts; accounts store money, cards do not. Above
all, cards carry no editable information whatsoever - only a reference ID.
(Note that making the cards themselves uncopyable is outside the scope of this
proposal; at worst, it would be equivalent to stealing someone else's card. As
the cards carry no value of their own, cloning your own card would give you no
benefit. An expert on NFC hardware can doubtless advise on this point, and also
on the related point of permitting people to use their mobile phones as
ThirdSquare cards.)

All computers in this operation SHOULD have unique and stable IP addresses. In
an ideal world, IPv6 should be used; however, the code does not depend on this.

(The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in RFC 2119.)

The financial database is simply a PostgreSQL server. It has no custom software
and no access other than from the states' servers (ergo its HBA config can and
should stipulate that their IPs are the only ones permitted); each state gets a
dedicated database user, and standard security methods will be deployed to
ensure that this server cannot be tampered with. This is all unsurprising to a
PostgreSQL database admin.

Where things get interesting is the per-state servers. These contain a local
PostgreSQL database which records cards and open tickets, and also maintain a
running instance of the server script. The server receives touch-on and -off
requests, and sends back responses saying "OK, no charge", "OK, fare deducted"
(with an amount), or "Denied, insufficient funds". The client (which may be a
single validator, or may be a bank of validators) communicates solely with the
one local server.

A card will most often be used in the state that issued it, but this is not a
requirement. Whenever a card is used for the first time in a new state, it is
verified against an account, and then a new per-state record is created for it;
most likely, the account will then be debited the price of a ticket. This makes
multi-state usage almost transparent - a Melburnian commuter with some travel
credits can travel to Adelaide, the credits are ignored, and a few
dollars get debited to pay for local travel.

All communication goes through the local server, which is therefore in total
control of the system. It uses a Unix socket to access its local database, a
TCP/IP socket (with SSL) to access the financial database, and UDP (with
cryptographic signatures, but no encryption) to receive and respond to touch
requests. Note that this implies that a MITM could snoop on validations. If
this is deemed to be a problem, the payload can be encrypted using the target
server's public key, at the cost of forcing all packets to carry exactly 512
bytes of data, with a maximum of 245 bytes of true payload.

Cryptography is based around SSH keypairs, which can be generated with the Unix
'ssh-keygen' command; they are kept in their text format for convenience. Every
client will need a keypair, and the server will need a lookup table mapping IP
addresses to public keys; the server also needs a keypair, and the public key
can be embedded into the client software.

The system is built on a concept of touching on and touching off, but it's not
always possible to recognize one from the other, and touches off do not always
happen. When a touch occurs, check to see if it could plausibly be a touch off
for the previous touch-on: same mode of transport, same vehicle (if applicable;
all railway stations on one line are the "same vehicle", and the city loop is
the same vehicle as all other lines), and same day. If so, it's a touch off.

Any time there is a touch on for an already-touched-on card, and any time that
the card is probed and it's been more than a day since the touch on, the server
will register a "presumed touch off". This is done as the "longest logical"
journey from the touch-on point - the longest possible normal trip from there.
Touches on platforms (railway stations) use a separate handler; see below.

Terminology
===========

A "normal trip" is one which a traveller with broad knowledge of the system
would use to get from one origin to one destination. Fare calculation etc is
all predicated on normal trips; if someone boards a vehicle, rides it to its
terminus, stays on board until it reaches the far end, and begins another
round trip, this is an abnormal trip, and may be under-charged. Similarly,
riding three sides of a square may end up under-charged as if you had taken
the shorter distance.

This makes the system under-charge the gunzel and the geographically-challenged
traveller, in the interests of simplicity. It may, for instance, be cheaper to
fail to touch off, after riding the new tram up and down for half the day, as
the automated touch off will have already occurred. Frankly, we don't care; it
just isn't worth enforcing every little silly thing. The general assumption is
that people care primarily about time cost, and secondarily about money cost.

Accounts, fleets, and finances
==============================

An account is a financial entity. It may have multiple cards associated with
it, but has exactly one billing contact. In the simplest case, a new traveller
purchases a ThirdSquare ticket, which would be associated with a newly-created
account; other common cases would be the family fleet of cards (each family
member has a card, and a unified pool of funds is used), the business with a
large number of employees (as employees come and go, cards get reallocated),
the person who wants a backup card, etc. Additional cards for an account can be
offered fairly inexpensively (basically just price of manufacture, ideally),
and it should be possible to log in via the web and see all cards and their
activity (eg to audit corporate card use).

Each account would have a balance, and a credit limit. By default the credit
limit is zero, but a corporate account could be given a limit of (eg) $500,
permitting post-paid usage. In the simplest case, the balance must be kept
non-negative for travel to be permitted, but a web login could permit credit
card details to be recorded, allowing automatic debiting to reload the card.
(This could be set with a transaction minimum of, say, $20; if your ThirdSquare
balance would fall below zero, your credit card would be charged for $20, and
that credited to your account.)

Direct depletion of funds would be treated on par with the "Myki Money" system.
It isn't the most efficient way to travel regularly, but it's easy, convenient,
and flexible. For regular travel within one state's network, an alternative is
offered; note that each state may choose its own system, and I will describe
the Melbourne system only.

Travel credits
--------------

Instead of always depleting direct funds, a traveller can prepurchase travel
credits (preferably with some cool marketable name). Travel would require one
credit per zone touched per day, halved (rounded up) if all travel in that day
is within the off-peak hours. Instead of duration tickets, we could offer price
breaks that encourage bulk purchase of credits; for instance, normal rate might
be two dollars per credit, but you can buy 55 credits for $100 (10% bonus!) or
750 credits for $1000 (50% bonus, wow!).

You could customize your account to auto-purchase X credits whenever you run
out. This would allow extremely convenient usage with broadly predictable cost,
where you get to choose between lumpier billing ("ack, I just got charged a
hundred bucks!") and higher overall cost ("it's still costing me $2/credit!").
This purchase would deplete account funds, or debit a credit card.

Duration plans might be saleable features; like the "yearly ticket debited
monthly", you could sign up for a year to get 60 credits a month for $100.

This would combo off strongly with fleet purchases. Effectively, the monthly
or yearly usage can be split across cards in the fleet; you can take full
advantage of discounts applicable to your combined usage. This is then an
incentive for big companies to get all their staff onto public transport.

Fully automated ticketing
=========================

(The individual states have the power to customize any of this, independently
of the other states. Again, this is Melbourne's system.)

Whenever you touch a card to a reader, a number of checks are done to determine
the validity of the touch.

1. See if this is a touch-on or a touch-off. If it is a touch on and the card
   was already touched on, first add a presumed touch off, then proceed to add
   the current touch on. For a touch on, it's quite simple: just add the zone
   map to the current day's ticket, including its timestamp.
2. For a touch off, ascertain which distance category the trip falls under:
   * Local journeys are those which have at least one zone in common between their
     origin and destination. These are simple: you won't be charged for any extra
     zones. (Note that it's entirely possible for you to end up being charged for
     other zones than the one that was actually in common. Only very weird edge
     cases will have this be significantly different.)
   * Adjacent journeys are those which, while they don't have any zones in common,
     have some pair of zones which is in the adjacency table. So, for instance, a
     journey may begin in zone 1|4 and end in zone 2|5; if there exists a location
     in zone 1|5, then these locations are deemed to be adjacent. You will be
     charged for your two end points, plus the overlap pair; this will ensure that
     you are definitely charged for at least two zones, but in many situations, no
     more than two.
   * Cross-zone journeys are those which are neither local nor adjacent. For these
     trips, an additional zone must be charged for. This is done by adding a zone
     to the touch map which carries the magical property of vanishing as long as
     at least three real zones are being charged for.
3. Count the number of zones needed for this ticket. This is the smallest
   number of zones which can, between them, cover every touch done today.
    1. Take the union of all zones which have been used at all.
    2. For each zone in the union, remove it from the union, then iterate over
       all touches in the ticket, checking intersection with that touch's zones.
       If any intersection comes up empty, the zone is needed, and must be kept.
       Otherwise, it can be removed.
    3. For ultimate optimization, perform this search recursively and seek the
       minimum zone count. As an efficiency cheat, assume that any removal is a
       valid removal, but then acknowledge that there MAY be crazy edge cases
       that depend on the order of the checks done. As a general rule, working
       from the least frequently used zones will give optimal results; but in
       case edge cases exist, ensure that zones are checked in some consistent
       order (eg lexically by zone identifier) even when multiple have the same
       frequency. Frequency-based ordering is unnecessary if the full recursive
       search is performed, but this should be cheaper (I think!).
    4. If the mythic zone is needed, add it. If it's there but we have three
       or more real zones, remove it.
    5. The number of zones in the union at the end is the ticket's zone count.
4. If all of the day's touches are in off-peak times (10AM-3PM or 7PM-6AM, or
   all day on weekends and public holidays), halve the ticket price. A normal
   trip is entirely capable of touching on during off-peak and then continuing
   into shoulder-peak, but usually not into full peak when services are most
   packed; the discounted fare will thus help keep traffic away from peak.
   As long as no peak-time touch-on occurs, the ticket counts as off-peak.
5. If the current zone count exceeds the paid-for zone count, charge for the
   additional zone(s) and reject the touch if the charge is rejected.
   1. If there are sufficient ticket credits, deduct them and approve.
   2. If the account (or card, if credits are per-card) has requested that
      credits be purchased when low, purchase more credits, using account funds
      or credit card etc.
   3. Otherwise, charge the base charge for the journey, using account funds.
   4. If sufficient account funds are not available and the credit card (if
      any) declines the charge, reject the touch.

These steps are 100% reproducible and deterministic, and can never decrease the
ticket's zone count. They do, however, require examination of *every* touch in
the ticket's period. Handling this for a single day is reasonable (there won't
normally be more than maybe a dozen touches in a typical day), but allowing the
automated tickets to expand to weekly, monthly, or yearly (!!) would be utterly
unworkable; the algorithm as described above scales with the square of touches.
Additionally, while it's reasonable to count a single day's travel as covering
all applicable zones, trying to expand this to multiple days becomes hairier;
if a commuter steps outside his usual route for one day in a month, how should
this be charged? The safest solution is to keep each day's travel separate.
Thus all tickets are based on a single day's travel, and bulk discounts are
applied at a higher level.

Touch-Off Detection
===================

Conceptually, your ticket will be touched off automatically when the vehicle
you were on reaches its destination. Practically, however, this happens only on
the next touch or other pinging of the card (eg if you request a balance, the
system MAY at that time bill you for a previous trip). This ensures that your
ticket is still in its "touched on" state any time an AO checks it.

Each touch operation sends three signature values: where the vehicle is now,
where it will be at end-of-trip, and its run number. These three integers are
stored as the ticket's touched-on status. If the next touch is on the same
vehicle and has the same run number, it is a touch-off; otherwise it is deemed
a touch-on, and an implicit touch-off is performed at the end-of-trip location.
Edge case: As a vehicle approaches the end-of-trip location (usually a route
terminus), it MUST instantly update its end-of-trip and run number to be the
*next* end and run (which may be the terminus at the far end, a depot, or
0 meaning that touches-on are to be rejected (vehicle not taking passengers));
until it departs that location, all touches MUST be sent with an additional
"matching run number", the previous run identifier. A touched-on ticket that
used the previous run number is counted as a touch off.
Additional edge case: Railway stations don't have a concept of vehicles or trip
end locations. All stations are therefore given a common end location, and the
back-end knows the ID of this location, and will ignore the vehicle IP for the
purposes of touch-off recognition. (The IP is still used for public key lookup,
but if both touches use the same end location, it is a touch-off.) In order to
make this make sense, travellers will be told that they MUST touch off when
using the trains, else they will be charged an automatic fine (which would be
set to exceed the normal travel cost of any regular train trip). This fine can
be charged by simply making the end location a premium location, incurring an
immediate debit whenever it is auto-touched. To make this less disconcerting
for passengers, as many railway stations as possible should be equipped with
barriers, as anyone who physically jumps over barriers is generally going to be
aware that s/he is fare evading; where this is impractical, signage has to
suffice, and as we all know, signage is seldom noticed.
(Parenthesis: Train journeys can easily cross many zones, especially since
changing services at Flinner doesn't involve any touches. This makes a problem
for point-to-point fare calculation. See below.)
(Parenthesis: Train journeys can easily consume many hours, especially since
changing services doesn't involve any touches. This makes a problem for the
policy that touches-off do not affect ticket duration. This may need to be
special-cased; railway station touches may always affect duration. Don't like.)

This requires that a vehicle know in advance what its next trip will be, or
else to reject touches-on until it knows that.
Vehicles must also have run numbers, which are never reused; XKCD 1340 style
recommended, but not enforced. Since run numbers are per-vehicle (with the
exception of railway stations, which don't use them at all), it doesn't hurt
if there are collisions across vehicle types (eg if tram run numbers use a
different scheme from the one bus run numbers use), as long as the tuple of
(vehicle, run) is used once only. Once that vehicle begins a new run, it MUST
NOT re-enter the previous run.

Note that if multiple service modes (eg metro trams and trains) have validators
on platforms, they can work the same way, but with different targets (probably
the same premium fare, but separate to detect failure to touch off when going
from one to the other).

Timestamping
============

Date and time: The system is posited on a cycle of days, each with a known
beginning and end. This works very nicely with a system that has a regular
downtime (say, 2AM-4AM) during which few people travel, as it is possible for
trips spanning this time to be charged to both days (confusing and potentially
expensive for night travel). It doesn't hurt if a day contains additional hours
from midnight until some particular cut-off, just as long as it's consistent.
The stipulated day-break (and no, I don't mean the coronet) is handled as some
number of hours (possibly zero) after midnight in some time zone (possibly UTC)
and always, for all operations, treats those hours as belonging to the previous
day. Note that touches-off are detected on the basis of their run numbers, NOT
the date of operation; if you touch on prior to the roll-over, then touch off
after the roll-over, it will be correctly detected. However, if you then touch
on again, it will be deemed a new day, and will open a new ticket.

Note that currently, the system assumes that time increases monotonically, and
that touches are processed in chronological order. The former can be ensured by
slewing (rather than stepping) the server's clock, such that any date, once
over, will never be re-entered; if the server's clock is ever found to be too
far wrong, it must be corrected during an effective outage. The latter is a
major problem with the bus/tram retry loop - it is theoretically possible to
touch on, then touch off in a dead spot, make all haste to your next service,
touch on again, and then have the retry of your touch off arrive. This would
result in all three touches (and the touch off at the end of your second trip)
to be counted as touches-on. To reduce the chances of this occurring, coverage
at railway stations needs to be excellent; it may also be important to hammer
the retry loop, possibly with no gap exceeding 2 seconds. None of this can
entirely prevent the problem, but it will make it vanishingly unlikely.

NOTE: In time zones using Daylight Saving Time, it is possible to experience
times more than once; in many locations, this occurs between 2AM and 3AM, with
the times from 02:00:00 to 02:59:59.999 occurring twice, but the instant of
03:00:00 occurs only once. Avoid setting the day-break inside this duplicated
period, as it will result in a day being potentially restarted. Using 3AM as
the day-break would work with this scenario, but 2AM would not. Check your DST
rules before selecting a cut-off point.

Identifiers: Vehicles
=====================

ThirdSquare needs to be able to uniquely identify every tram and bus, in order
to correctly recognize a touch-off. Currently, the system is posited on the use
of fixed IP addresses to identify these vehicles; if no 3G/4G provider is able
to guarantee this, an alternative could be devised involving a lookup table,
but this has security implications. Even with that change, though, the system
depends on any given vehicle maintaining a unique and constant IP address for
the duration of one "session", with no passengers remaining on board across a
session break. For instance, a bus might return to the depot, shut down, and
relinquish its IP address, but if it reboots during a run, matters could become
extremely messy if its IP changes. More importantly, it is not possible for two
validation nodes to share an IP address (eg NAT).

The IP address is tied to a public key. Consequently, each vehicle must have a
single encryption computer; it may have multiple validators, but they will be
considered to be a single "unit". Notably, if a user touches on at one of the
validators and touches off at another one, they are considered to be the same
vehicle if and only if they use the same IP address and encryption key.

Railway stations do not have a concept of vehicles (the entire rail network is
treated as one vehicle), but must still tie encryption keys to IP addresses.
Whether a station has a single key+IP or multiple does not matter; it would be
perfectly reasonable to operate a two-platform island station off a single IP,
and equally reasonable to operate Spencer Street Station off several separate
nodes, just as long as each node has a dedicated IP address and keypair.

Identifiers: Locations
======================

Whenever a ThirdSquare card is touched to a validator, that validator MUST know
its current location. This location need not necessarily correspond to a single
point on the globe, but MUST carry a single zone map, and ideally, it should be
impractical for anyone to board a vehicle, ride, and then disembark, all within
a single location. The system MAY assume that a second touch in the location of
the latest touch on is a cancellation rather than a short trip. Note that using
the same location ID for multiple routes is acceptable as long as no route ever
exits a location and then reenters it, all while heading toward the same target
location; this could confuse location descriptors. In other words, it's fine to
exit a location, go to the terminus, then start a return journey that goes into
the same location in the opposite direction; but not to loop around and hit the
same place again after leaving it.

Locations SHOULD be identified in a service-specific way, such that bus, train,
and tram locations in near proximity are still distinguishable. This allows for
zone-map differences based on mode of travel, which may be important.

Regions which cross state boundaries (eg Albury-Wodonga) MUST be managed by one
state or the other for ticketing purposes. The region cannot be divided up such
that a single journey might involve multiple governing states. If a vehicle is
able to operate in two different states, it MUST know on startup which state it
is servicing this time. It may be simpler to avoid this scenario altogether.

Identifiers: Zones
==================

Ticketing zones are broad areas of coverage charged at the same rate. Any given
location may be in one single zone, or may be in the overlap of any number of
zones; a ticket for any of those zones is valid for travel at that location.
The set of all zones valid at a given location is that location's zone map.
A ticket's exact set of zones is ephemeral, and may change any time
a new touch is added; all that truly matters is the _count_ of zones.

Zones must be defined in a totally ordered manner. Identifying them with simple
numbers or alphabetizable strings is sufficient.

Rejected alternate sub-proposals
================================

Point-to-point fare calculation
-------------------------------

Currently, all fares are calculated on the basis of endpoints only. So long as
all routes run relatively short distances, this is not a problem - a bus might
go across one zone boundary, and include overlaps with several others, but no
single trip on any bus would ever cost more than two zones. Train journeys,
however, are often going to be longer, and may require line-based zoning. How
should this be calculated? See above - zones have no concept of geography, so
a vehicle that goes from zone 1|2 to zone 5|9 might have passed through any
other zones in between. One solution might be to maintain a table of zone
overlaps; for instance, the above would demonstrate that zones 1 and 2 overlap,
and likewise zones 5 and 9. In order to determine the actual fare, a complete
chain must be found. Suppose there is, somewhere in the system, a station in
zones 2|4, and another in zones 4|9. This would indicate that the trip would be
possible with constant overlap by progressing 1|2, 2|4, 4|9, 5|9, with the two
ends being the actual touch locations. The system would then presume touches in
all four locations instead of just one, and then bill accordingly; if this were
the only trip done on a ticket, then it would be charged as a three-zone ticket
(covering zones 2|4|9), which is thus sufficient to cover the entire zone set.

Unfortunately, while this can be implemented reasonably efficiently for a
single journey, it becomes increasingly difficult as more journeys get added;
instead of simply accepting the shortest path from point to point, we need to
find the shortest overall path, which might be quite different.

Additionally, consider the following touch sequence:

On in zone 1, off in zone 1|2. On in 1|2, off in 2|3. On in 2|3, off in 3.

What route did this person follow? What zones should be charged for? There are
two possibilities, exemplified thusly.

Begin travel deep inside zone 1, and ride eastward toward the zone 2 border.
Then, change services, and ride southward, **skirting** zone 2, and crossing
into zone 3. Finally, ride westward, deep into zone 3. Or...

Begin travel deep inside zone 1, and ride eastward to just into zone 2's area.
Then, change services, still travelling east, **traversing** zone 2 from end
to end, and disembarking near the zone 3 border. Finally, ride a further east,
deep into zone 3.

These two scenarios can be distinguished, in theory, by the presence or absence
of a zone 1|3 location. If one exists, skirting is possible, and zone 2 should
not be billed for; otherwise, it must have been traversal, and zone 2 must be
billed for (making this a three-zone ticket). But now consider a somewhat less
simplistic scenario, in which several of the locations have other zones added
to their zone maps, and perhaps the return journey uses slightly different
locations with different zone maps. How do you go about calculating the true
zone usage?

The upshot of all of this, and cf The Midga, Personal Communication, is that
every attempt to solve this problem just moves the edge cases around, without
actually curing anything. So instead, we simply categorize trips by distance,
as detailed in the main body.

This system ensures that any "wonk" in the fares is in the traveller's favour.
For instance, it is not possible to ever be charged for four or more zones in a
single journey; and it is also not possible for "closing the triangle" to cost
more than the original two sides have already cost. It is also simple, and has
very few hairinesses to explain. Staying in one zone? Charged for one. Going
from one zone into the next? Charged for two. Going a long way? Charged for
three zones, never more. As an added bonus, we don't have to stress too much
about the exact fare charged for a presumed touch-off, as it can never exceed
the three-zone charge for a cross-zone journey.

Ticket durations and touches-off
--------------------------------

Whenever you touch on, the current time is checked for validity, and if you do
not have an active ticket, one will be created (or a previous one extended) to
cover 'now'. What happens when you touch off explicitly, and what happens when
your ticket is automatically touched off for you?

If explicit touches extend tickets, then automated touches MUST also extend.
Otherwise, failing to touch off will frequently result in a lower fare than
touching off, which violates a fundamental principle of our Association.

If touches extend tickets, there may be extreme weirdnesses across a day-break.
Does your existing ticket get a "loading" for its extra hours? Is a new ticket
opened, and if so, for what zones? Or is there a special case, that touching
off after day-break doesn't extend your ticket? This would be an extremely odd
corner case, and maybe it's rare enough that people shouldn't need to worry
about it, but it's still hard to explain. The Zen of Python advises against
this proposal (lines 8 and 17), and while we're not governed by it, it's still
worth noting.

Also, if touches extend tickets, the deemed time of the automated touch becomes
significant. This may mean that people complain very loudly when their ticket
gets unexpectedly expanded to cover peak time (doubling their fare), and may
have other unintended consequences; it also worsens the day-break problem, as
any run which spans the boundary will trigger this for failed-touches-off.
Consistency could be achieved by deeming that ALL automated touches occur at
notional end-of-peak, which would mean that failing to touch off would always
result in a peak fare; this would likely cause resentment in other areas, and
doesn't improve the situation significantly, and so is not worth doing.

Conversely, if touches do NOT extend tickets, there is an incentive to cheat on
rail journeys. Suppose a commuter lives on one side of the city and works on
the other, in each case either walking to/from the station or using a bicycle.
If he travels to work in the morning and home again in the evening, he ought to
touch four times; conceptually, he should be charged for a daily ticket for all
zones of his journey (cf "Point-to-point" above, but certainly a daily ticket),
as he has travelled for (say) 90 minutes in the AMs and 90 more in the PMs. But
if he consistently fails to touch off, the system will detect only two touches
per day, one at his home station in the morning, and one at his work station in
the afternoon, and will treat the latter as a touch-off. Technically he is fare
evading by failing to touch off, but the reward is a half-price ticket, which
is extremely tempting, and the system is unable to detect this (without some
kind of silly boundary condition, like assuming that no train journey lasts
more than X hours - which would have its own stupid cases).

A messy system in which railway station touches always affect times but others
do not would further complicate matters, and I'm not sure it fixes the problem.

Thus it is decided that touches-off should not extend tickets. Fare evasion is
fare evasion, and while it is be nice to build evasion discouragement into the
code, it is not important enough to justify excessive complexity.

Ticket security and cloning
---------------------------

NFC devices could, in theory, clone your ticket and have an exact duplicate.
This could be abused in one of two ways: cloning your own card, or cloning
someone else's. Cloning your own card has minimal benefit; you would have two
cards that operate identically. It would potentially confuse the system some,
and while you might be able to abuse this to have two people travelling within
the same zones during the same hours and pay for only one ticket, it's not
usually going to be particularly beneficial. The main advantage could be given
legitimately by making it easy to have multiple cards issued against the same
account, thus allowing fleet usage to share billing details. This would be a
saleable feature, and if it's well enough known, nobody would need to bother
cloning their cards. (Notably, cloning a card does NOT clone the money on it,
as it would with a stored-value card; the two cards would simply deplete the
same pool.)

Cloning someone else's card, however, is more serious; it is effectively the
same as stealing the card, only worse, because  that the owner can't notice its
loss. As such, this would make a very effective form of fraud - move around a
crowded train with a device in your pocket that steals the details of any card
it gets near enough to.

This could be prevented by uprating the cards to perform cryptography. Assign
each card a unique keypair, and record the public key on the central server.
This would dramatically increase the processing cost (not intrinsically a
problem), and would also require far more disk pages to be read as part of a
touch operation, just for the unlikely event of a cloned card. (It needn't
increase latency; the entire operation can still be done as a single UDP
packet out and a single UDP packet back, though they may need to be larger in
order to carry the additional payload.) The most serious cost is that the
cards themselves now have to contain hardware capable of crypto, and enough
protection to prevent a device from leeching the key. This may prove to be
entirely impossible, or even if it is possible, economically unviable.

For comparison, credit cards (which use the same technology - see for instance
Visa PayWave) are worth a lot more to the issuer than a single ticket will be
(thus, the cost of improving the security is amortized over more transactions),
and can represent far greater dollar amounts (eg transaction limit of $100, and
daily limit of $1,000 - compared to ThirdSquare tickets where you'd be hard
pressed to spend a tenth that in a day)... and they have no protection against
this kind of attack. None whatsoever. All they'll do is let you dispute charges
after the event, and maybe, if you fill out the three-page form, and if you're
not found to have been careless with your card, they'll reverse the transaction
for you. For the present, we will content ourselves with merely bank-level
security, leaving open the possibility of improving on this later.

Per-card vs per-account credits
-------------------------------

If credits are isolated to a card, they are functionally identical to separate
weekly/monthly/yearly (actually 10x2hr, 40x2hr, etc) tickets. Maintaining a
fleet of 100 cards would require maintaining 100 credit balances.

On the other hand, having per-account credits means the account needs per-state
data, which otherwise does not happen. Or rather, the state needs per-account
data, as there's no way the central database will be burdened with this (both
for reasons of state isolation, and because we can't afford to hammer that DB).

Keeping credits on the account has internal problems; keeping them on the card
has external problems. Thus we opt for the former.
