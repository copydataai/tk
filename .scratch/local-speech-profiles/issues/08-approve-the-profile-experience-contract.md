# Approve the Speech profile experience contract

Type: grilling
Status: resolved
Blocked by: 05, 06, 07
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

Does the combined portfolio, Settings prototype, lifecycle, compatibility behavior, plain-language limits, accessibility behavior, and offline guarantee form a complete acceptance contract ready for implementation planning, and what must change before approval?

## Answer

Approved. The decision-complete [Speech profile implementation and acceptance contract](../implementation-contract.md) is the release-ready planning handoff.

It reconciles the resolved portfolio, prototype, lifecycle, and compatibility decisions against the current app flow; fixes exact manifest facts and UI copy; defines the lifecycle state machine, persistence, accessibility, privacy, release notices, and acceptance checks; and consolidates every authorized assumption, explicit unknown, and out-of-scope boundary. The later lifecycle rule governs storage eligibility: a same-volume partial needs only the remaining artifact bytes, not a second full artifact copy.

No product code is implemented by this ticket. The Wayfinder destination is reached.
