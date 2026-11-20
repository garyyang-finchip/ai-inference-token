#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Recomputes the two worked state examples of the optional entitlement profiles.

The reference ledger implements neither profile. This model applies the rules of the
specification to the event lists of its Test Cases section, prints the resulting tables and
fails if any stated number or any rule is violated. Run: python3 tools/profile_examples.py
"""


class Rejected(Exception):
    pass


class PeriodicModel:
    """Periodic allowance with activation.

    A right that is active in a period yields `allowance` denomination units in that period.
    Activation and deactivation take effect at the next period boundary. Active rights, and
    rights whose allowance still backs an unsettled request, cannot be transferred. A request
    is charged to the period in which its hold was placed. Nothing carries over.
    """

    def __init__(self, anchor, length, allowance, first=None, last=None):
        self.anchor, self.length, self.allowance = anchor, length, allowance
        self.first, self.last = first, last  # reservation window as period indices, inclusive
        self.owned = {}  # holder -> rights owned
        self.active_from = {}  # holder -> list of [rights, first_period, end_period or None]
        self.used = {}  # (holder, period) -> units deducted
        self.held = {}  # (holder, period) -> units currently held
        self.requests = {}  # id -> [holder, period, held]
        self.cancelled_from = None

    def period(self, t):
        return (t - self.anchor) // self.length

    def issue(self, holder, rights, active_from_period=None):
        self.owned[holder] = self.owned.get(holder, 0) + rights
        if active_from_period is not None:
            self.active_from.setdefault(holder, []).append([rights, active_from_period, None])

    def active_rights(self, holder, p):
        total = 0
        for rights, start, end in self.active_from.get(holder, []):
            if start <= p and (end is None or p < end):
                total += rights
        return total

    def granted(self, holder, p):
        if self.first is not None and not (self.first <= p <= self.last):
            return 0
        if self.cancelled_from is not None and p >= self.cancelled_from:
            return 0
        return self.active_rights(holder, p) * self.allowance

    def available(self, holder, p):
        return self.granted(holder, p) - self.used.get((holder, p), 0) - self.held.get((holder, p), 0)

    def activate(self, holder, rights, t):
        inactive = self.owned.get(holder, 0) - self.locked_rights(holder, t)
        if rights > inactive:
            raise Rejected("not enough inactive rights")
        self.active_from.setdefault(holder, []).append([rights, self.period(t) + 1, None])

    def deactivate(self, holder, rights, t):
        end = self.period(t) + 1
        remaining = rights
        for entry in self.active_from.get(holder, []):
            if entry[2] is None and remaining:
                if entry[0] > remaining:
                    raise Rejected("partial deactivation is not modelled")
                entry[2] = end
                remaining -= entry[0]
        if remaining:
            raise Rejected("not enough active rights")

    def locked_rights(self, holder, t):
        """Rights that cannot move: active now or later, or backing an unsettled request."""
        p = self.period(t)
        locked = 0
        for rights, start, end in self.active_from.get(holder, []):
            still_active = end is None or p < end
            backs_open_request = any(h == holder and start <= q and (end is None or q < end)
                                     for h, q, _ in self.requests.values())
            if still_active or backs_open_request:
                locked += rights
        return locked

    def transfer(self, sender, receiver, rights, t):
        if rights > self.owned.get(sender, 0) - self.locked_rights(sender, t):
            raise Rejected("rights are active or back an unsettled request")
        self.owned[sender] -= rights
        self.owned[receiver] = self.owned.get(receiver, 0) + rights

    def hold(self, request, holder, amount, t):
        p = self.period(t)
        if amount > self.available(holder, p):
            raise Rejected("no allowance left in this period")
        self.held[(holder, p)] = self.held.get((holder, p), 0) + amount
        self.requests[request] = [holder, p, amount]

    def settle(self, request, deducted):
        holder, p, held = self.requests.pop(request)
        assert deducted <= held
        self.held[(holder, p)] -= held
        self.used[(holder, p)] = self.used.get((holder, p), 0) + deducted
        return p, held - deducted

    def cancel_from(self, t):
        self.cancelled_from = self.period(t) + 1


def expect_rejected(action):
    try:
        action()
    except Rejected:
        return
    raise AssertionError("the specification rejects this step")


DAY, HOUR, MINUTE = 86400, 3600, 60


def periodic_example():
    m = PeriodicModel(anchor=0, length=DAY, allowance=10_000)
    m.issue("A", 5, active_from_period=0)
    rows = []

    def row(time, event, note):
        rows.append((time, event, note))

    d1, d2, d3 = 0, DAY, 2 * DAY
    row("day 1 00:00", "period 1 opens", f"A: granted {m.granted('A', 0):,}")
    m.hold("r1", "A", 20_000, d1 + 9 * HOUR)
    row("day 1 09:00", "hold r1, 20,000", f"A: available {m.available('A', 0):,}")
    m.settle("r1", 18_000)
    row("day 1 09:05", "settle r1, 18,000", f"A: used {m.used[('A', 0)]:,}, available {m.available('A', 0):,}")
    m.hold("r2", "A", 27_000, d1 + 14 * HOUR)
    m.settle("r2", 27_000)
    row("day 1 14:00", "hold and settle r2, 27,000", f"A: used {m.used[('A', 0)]:,}, available {m.available('A', 0):,}")
    m.deactivate("A", 5, d1 + 15 * HOUR)
    row("day 1 15:00", "A deactivates 5 rights", "effective at day 2 00:00")
    expect_rejected(lambda: m.transfer("A", "B", 5, d1 + 15 * HOUR + MINUTE))
    row("day 1 15:01", "A tries to transfer", "rejected: rights are active")
    m.hold("r3", "A", 5_000, d1 + 23 * HOUR + 58 * MINUTE)
    row("day 1 23:58", "hold r3, 5,000", f"A: available {m.available('A', 0):,}")
    assert m.granted("A", 1) == 0
    row("day 2 00:00", "period 2 opens", f"A: granted {m.granted('A', 1):,}; rights stay locked by r3")
    expect_rejected(lambda: m.transfer("A", "B", 5, d2 + MINUTE))
    row("day 2 00:01", "A tries to transfer", "rejected: r3 is unsettled")
    period, released = m.settle("r3", 4_200)
    assert period == 0 and released == 800
    row("day 2 00:03", "settle r3, 4,200", f"charged to period 1: used {m.used[('A', 0)]:,}; 800 released into a closed period and lost")
    m.transfer("A", "B", 5, d2 + 8 * HOUR)
    row("day 2 08:00", "A transfers 5 rights to B", "accepted")
    m.activate("B", 5, d2 + 8 * HOUR + MINUTE)
    row("day 2 08:01", "B activates 5 rights", "effective at day 3 00:00")
    expect_rejected(lambda: m.hold("r4", "B", 1, d2 + 12 * HOUR))
    row("day 2 12:00", "B tries to hold 1", f"rejected: B granted {m.granted('B', 1):,} in period 2")
    row("day 3 00:00", "period 3 opens", f"B: granted {m.granted('B', 2):,}")

    # What the example states.
    assert m.used[("A", 0)] == 49_200
    assert m.available("A", 0) == 800  # unusable: the period is closed
    for p in range(3):
        assert m.granted("A", p) + m.granted("B", p) <= 50_000, "five rights never yield more than 50,000 a period"
    assert (m.granted("A", 0), m.granted("B", 0)) == (50_000, 0)
    assert (m.granted("A", 1), m.granted("B", 1)) == (0, 0)
    assert (m.granted("A", 2), m.granted("B", 2)) == (0, 50_000)
    return rows


def reserved_example():
    start = 10 * HOUR
    m = PeriodicModel(anchor=start, length=10 * MINUTE, allowance=60_000, first=0, last=5)
    m.issue("H", 1, active_from_period=0)
    rows = []

    def at(h, mi):
        return h * HOUR + mi * MINUTE

    def row(time, event, note):
        rows.append((time, event, note))

    m.hold("a", "H", 45_000, at(10, 2))
    m.settle("a", 45_000)
    row("10:02", "hold and settle, 45,000", "interval 0: used 45,000")
    row("10:10", "interval 0 closes", f"{m.available('H', 0):,} unused, lost")
    m.hold("b", "H", 30_000, at(10, 12))
    m.settle("b", 30_000)
    row("10:12", "hold and settle, 30,000", "interval 1: used 30,000")
    m.hold("c", "H", 20_000, at(10, 19))
    row("10:19", "hold c, 20,000", f"interval 1: available {m.available('H', 1):,}")
    row("10:20", "interval 1 closes", f"{m.available('H', 1):,} unused, lost; 20,000 still held by c")
    period, released = m.settle("c", 18_000)
    assert period == 1 and released == 2_000
    row("10:21", "settle c, 18,000", f"charged to interval 1: used {m.used[('H', 1)]:,}; 2,000 released into a closed interval and lost")
    m.hold("d", "H", 60_000, at(10, 22))
    m.settle("d", 60_000)
    row("10:22", "hold and settle, 60,000", "interval 2: used 60,000")
    expect_rejected(lambda: m.hold("e", "H", 5_000, at(10, 28)))
    row("10:28", "tries to hold 5,000", "rejected: interval 2 is exhausted")
    row("10:30", "interval 2 closes", f"{m.available('H', 2):,} unused")
    m.hold("f", "H", 10_000, at(10, 33))
    m.settle("f", 10_000)
    row("10:33", "hold and settle, 10,000", "interval 3: used 10,000")
    m.cancel_from(at(10, 35))
    row("10:35", "holder cancels the rest", "effective at 10:40: intervals 4 and 5 return to the supplier")
    row("10:40", "interval 3 closes", f"{m.available('H', 3):,} unused, lost")

    used = sum(m.used.get(("H", p), 0) for p in range(6))
    lost = sum(m.available("H", p) for p in range(4))
    cancelled = 2 * 60_000
    assert [m.used.get(("H", p), 0) for p in range(6)] == [45_000, 48_000, 60_000, 10_000, 0, 0]
    assert (used, lost, cancelled) == (163_000, 77_000, 120_000)
    assert used + lost + cancelled == 6 * 60_000
    assert m.granted("H", 4) == 0 and m.granted("H", 5) == 0
    per_interval = [m.available("H", p) for p in range(4)]
    assert per_interval == [15_000, 12_000, 0, 50_000]
    rows.append(("total", "6 x 60,000 = 360,000",
                 f"used {used:,} + lost {lost:,} ({' + '.join(f'{x:,}' for x in per_interval)}) + cancelled {cancelled:,}"))
    return rows


def table(rows):
    lines = ["| Time | Event | State |", "| --- | --- | --- |"]
    lines += [f"| {t} | {e} | {n} |" for t, e, n in rows]
    return "\n".join(lines)


if __name__ == "__main__":
    print("Periodic allowance: 5 rights, 10,000 units per right per day, no carry-over\n")
    print(table(periodic_example()))
    print("\nReserved capacity: 10:00 to 11:00, 10-minute intervals, 60,000 units per interval\n")
    print(table(reserved_example()))
    print("\nok")
