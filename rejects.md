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
